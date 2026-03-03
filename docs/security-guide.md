# Security Guide

## Table of Contents

1. [Security Architecture Overview](#1-security-architecture-overview)
2. [Authentication Model](#2-authentication-model)
3. [Authorization Model](#3-authorization-model)
4. [Network Security](#4-network-security)
5. [Secret Management](#5-secret-management)
6. [Policy Enforcement](#6-policy-enforcement)
7. [State File Security](#7-state-file-security)
8. [CI/CD Security](#8-cicd-security)
9. [Security Scanning](#9-security-scanning)
10. [Incident Response](#10-incident-response)
11. [Compliance Mapping](#11-compliance-mapping)
12. [Security Review Checklist for PRs](#12-security-review-checklist-for-prs)

---

## 1. Security Architecture Overview

This project implements a defense-in-depth security model across six layers. No single control is relied upon in isolation; each layer assumes the previous layer may be compromised and adds an independent barrier.

| Layer | Mechanism | Where Defined |
|-------|-----------|---------------|
| Authentication | Workload Identity Federation (OIDC), Managed Identities | CI/CD pipeline, `managed-identity` module |
| Authorization | RBAC as code, custom roles, Owner guard precondition | `rbac-assignment` module |
| Secrets | Azure Key Vault with RBAC access model | `key-vault` module |
| Network | Private endpoints, NSGs with default-deny-inbound | `nsg`, `private-ep`, `subnet` modules |
| Policy | Azure Policy enforces tagging, HTTPS, no public access | `azure-policy` module |
| State | Encrypted at rest, blob lease locking, soft-delete | `storage-acc` module, backend config |

### Design Principles

- **No stored credentials.** All authentication uses federated identities or managed identities. No service principal passwords, no shared access signatures stored in code or environment variables.
- **Infrastructure as code is the sole source of truth.** All RBAC assignments, policies, and network rules exist in Terraform. Manual portal changes are not permitted and will be overwritten on the next apply.
- **Least privilege by default.** Every identity receives only the permissions it needs to perform its defined function. Elevated permissions require explicit justification in code.
- **Auditability.** All resources emit diagnostics to Log Analytics. All RBAC assignments carry a `description` field that records intent. All policy assignments are version-controlled.

---

## 2. Authentication Model

### Workload Identity Federation (OIDC) for CI/CD

The CI/CD pipeline authenticates to Azure using OpenID Connect (OIDC) token exchange, not stored credentials. The pipeline's identity provider (GitHub Actions, Azure DevOps, or equivalent) issues a short-lived OIDC token for each run. Azure AD exchanges this token for a short-lived access token scoped to the specific run.

**What this means in practice:**

- No client secrets or certificates are stored in the pipeline's secret store.
- Tokens expire automatically after each job; there is nothing to rotate or revoke on a schedule.
- Token exchange is subject to subject-claim conditions (branch, environment, workflow name) that are configured on the Azure AD federated credential. A compromised pipeline job cannot authenticate as a production identity if its subject claim does not match the production federated credential's conditions.

**Configuration requirements:**

- The federated credential on the Azure AD application must pin the `subject` claim to the specific branch or environment (e.g., `repo:org/repo:environment:production`).
- The `audience` claim must match the Azure AD default (`api://AzureADTokenEndpoint`) or your tenant's custom audience.
- Wildcards in subject claims must not be used; each environment (dev, staging, prod) must have its own federated credential with a precise subject.

### Managed Identities for Azure Workloads

Azure resources that need to access other Azure services (e.g., AKS pods accessing Key Vault, storage account accessing another service) use system-assigned or user-assigned managed identities. Managed identities are provisioned through the `managed-identity` module and RBAC assignments are made through the `rbac-assignment` module.

**Rules:**

- Prefer user-assigned managed identities over system-assigned when the identity needs to be shared across resources or when the lifecycle of the identity should be independent of the resource.
- System-assigned managed identities are acceptable for single-resource, single-purpose identities where the identity should be destroyed with the resource.
- No workload may use a service principal with a password or certificate stored in an application configuration file, environment variable, or Kubernetes secret in plaintext.

### What Is Explicitly Prohibited

- Storing `ARM_CLIENT_SECRET` or any equivalent credential in pipeline environment variables, repository secrets, or `.env` files.
- Using shared access signatures (SAS tokens) with long expiry windows. If SAS tokens are required for a specific integration, they must be generated on demand with the minimum permissions and shortest acceptable expiry.
- Embedding connection strings, storage account keys, or API keys in Terraform variable files, application configuration, or container images.

---

## 3. Authorization Model

### RBAC as Code

All Azure role assignments are managed exclusively through the `rbac-assignment` module. The module wraps `azurerm_role_assignment` and `azurerm_role_definition` resources:

```hcl
# modules/rbac-assignment/main.tf
resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  description          = each.value.description

  lifecycle {
    precondition {
      condition     = each.value.role_definition_name != "Owner" || can(regex("EXCEPTION-APPROVED", each.value.description))
      error_message = "Owner role assignments require 'EXCEPTION-APPROVED' in the description field."
    }
  }
}
```

The `precondition` block enforces a hard policy at plan time: **any attempt to assign the Owner role without the string `EXCEPTION-APPROVED` in the description field will fail before any change is made to Azure.** This ensures that Owner assignments are never accidental and are always accompanied by a documented justification.

### Custom Role Definitions

Where built-in Azure roles are too broad, custom roles are defined through `azurerm_role_definition` in the same module. Custom roles must:

- List only the specific `actions` and `data_actions` required.
- Use `not_actions` and `not_data_actions` to explicitly exclude sensitive operations (e.g., `*/delete`, `Microsoft.Authorization/*/Write`) unless those operations are the specific purpose of the role.
- Restrict `assignable_scopes` to the narrowest possible scope (subscription, resource group, or individual resource — not management group unless necessary).

### Least Privilege Rules

| Scenario | Correct Approach |
|----------|-----------------|
| Application reads from Key Vault | `Key Vault Secrets User` on the specific vault, not on the subscription |
| AKS node pool pulls from ACR | `AcrPull` on the specific registry |
| CI/CD applies Terraform | Custom role with only the permissions required by the modules in use |
| Monitoring agent writes to Log Analytics | `Log Analytics Contributor` scoped to the specific workspace |
| Developer inspects resources | `Reader` at resource group scope; never at subscription scope without approval |

### Reviewing Existing Assignments

Run the following to audit all role assignments managed by Terraform:

```bash
terraform state list | grep azurerm_role_assignment
terraform state show <resource_address>
```

To audit Azure directly (catches any out-of-band assignments):

```bash
az role assignment list --all --output table
```

Any assignment that does not correspond to a resource in the Terraform state is unauthorized and must be removed or brought under Terraform management.

---

## 4. Network Security

### Virtual Network Layout

All resources are deployed inside a single VNet (`10.0.0.0/16`) segmented into purpose-specific subnets:

| Subnet | CIDR | Purpose |
|--------|------|---------|
| AKS | 10.0.0.0/22 | Kubernetes node pools and pod networking |
| Services | 10.0.4.0/24 | Internal platform services |
| Private Endpoints | 10.0.5.0/24 | Private endpoint NICs for PaaS resources |
| App Gateway | 10.0.6.0/24 | Application Gateway / ingress |

### Network Security Groups

Every subnet has an NSG applied. The baseline rule set for all NSGs is:

- **Default deny all inbound.** No inbound traffic is permitted unless an explicit allow rule exists with a lower priority number.
- **Allow only what is documented.** Each allow rule in the NSG must correspond to a known traffic flow with a business justification recorded in the rule's `description` field.
- **Deny outbound to Internet from private subnets.** Subnets hosting backend services (Services, Private Endpoints) must not have unrestricted outbound Internet access. Route tables or NSG outbound rules must restrict egress to known destinations.

Adding a broad inbound allow rule (e.g., `source: Any`, `destination: Any`, `port: *`) to any NSG is a security incident and must be reverted immediately.

### Private Endpoints

Azure Key Vault and the Terraform state Storage Account do not have public network access. All access occurs over private endpoints in the `10.0.5.0/24` subnet. Private DNS zones are configured to resolve the service's public FQDN to the private endpoint's private IP address, so no code changes are needed to use the private endpoint.

**Checklist for new PaaS resources:**

- [ ] Public network access disabled on the Azure resource.
- [ ] Private endpoint deployed in the `10.0.5.0/24` subnet through the `private-ep` module.
- [ ] Private DNS zone record created and linked to the VNet.
- [ ] NSG on the private endpoint subnet allows traffic from the expected consumer subnets only.

### No Public IPs on Backend Resources

Backend VMs, AKS nodes, and database resources must not have public IP addresses. Inbound traffic from the Internet reaches the cluster only through the Application Gateway subnet. Any PR that adds a public IP to a non-gateway resource must be blocked.

---

## 5. Secret Management

### Azure Key Vault

Key Vault is the only permitted storage location for secrets, certificates, and encryption keys used by application workloads. The vault is configured with the RBAC access model (not the legacy vault access policy model), which means permissions are managed through Azure role assignments and are therefore subject to the same `rbac-assignment` module controls described in Section 3.

**Permitted Key Vault roles:**

| Role | Who receives it |
|------|----------------|
| `Key Vault Secrets Officer` | CI/CD pipeline identity (to write secrets during deployment) |
| `Key Vault Secrets User` | Application managed identities (read-only access to specific secrets) |
| `Key Vault Administrator` | Break-glass emergency identity only; assignment requires `EXCEPTION-APPROVED` and a linked incident ticket |

### No Hardcoded Secrets

The `.gitignore` file blocks the following file patterns from being committed:

```
*.pem
*.key
.env
*.auto.tfvars
```

The `*.auto.tfvars` exclusion is critical: Terraform automatically loads files matching this pattern, making it easy to accidentally put secrets into a file that gets committed. Use the blocked pattern list and pre-commit hooks to enforce this.

**Pre-commit hook recommendation:**

Install `detect-secrets` or `gitleaks` as a pre-commit hook to catch secrets before they reach the repository:

```bash
# Using gitleaks
gitleaks protect --staged --redact

# Using detect-secrets
detect-secrets scan --baseline .secrets.baseline
```

### Passing Secrets to Terraform

When Terraform resources need secret values (e.g., a database password for initial provisioning), the correct pattern is:

1. Generate the secret value outside of Terraform (or use `random_password`).
2. Store it in Key Vault via the pipeline using the Key Vault Secrets Officer role.
3. Reference it in Terraform using a `data "azurerm_key_vault_secret"` data source — never via a variable passed on the command line or stored in a `.tfvars` file.

The `sensitive = true` attribute must be set on any Terraform output that contains secret material to prevent it from appearing in plan output.

### Secret Rotation

- Application secrets stored in Key Vault should have an expiry date set. Key Vault will emit near-expiry events to Event Grid, which should trigger an automated rotation workflow.
- Managed identity credentials do not require rotation — this is a primary reason managed identities are preferred over service principal credentials.

---

## 6. Policy Enforcement

### Azure Policy as Code

Azure Policy definitions and assignments are managed through the `azure-policy` module:

```hcl
# modules/azure-policy/main.tf
resource "azurerm_policy_definition" "this" {
  for_each = var.policy_definitions

  name                = each.key
  policy_type         = "Custom"
  mode                = each.value.mode
  display_name        = each.value.display_name
  description         = each.value.description
  management_group_id = var.scope
  policy_rule         = each.value.policy_rule
  metadata            = each.value.metadata != "" ? each.value.metadata : null
  parameters          = each.value.parameters != "" ? each.value.parameters : null
}

resource "azurerm_subscription_policy_assignment" "this" {
  for_each = var.policy_assignments

  name                 = each.key
  policy_definition_id = each.value.policy_definition_id
  subscription_id      = each.value.scope
  enforce              = each.value.enforce
  ...
}
```

The `enforce` field controls whether the policy effect is `Deny` (blocking non-compliant deployments) or `Audit` (logging non-compliant resources without blocking). New policies should start in `Audit` mode to assess impact before being moved to `Deny`.

### Enforced Policy Categories

| Category | Example Policies | Effect |
|----------|-----------------|--------|
| Tagging | All resources must have `environment`, `owner`, `cost-center` tags | Deny |
| Transport security | Storage accounts must require HTTPS; App Services must use HTTPS only | Deny |
| Public access | Storage accounts must disable public blob access; Key Vault must disable public network access | Deny |
| Encryption | Managed disks must use platform-managed or customer-managed keys | Audit (escalate to Deny after baseline) |
| Diagnostic logs | All resources must send diagnostic logs to Log Analytics | Audit |

### Adding a New Policy

1. Define the policy rule JSON and add it to the `policy_definitions` variable input.
2. Create a corresponding entry in `policy_assignments` with `enforce = false` (Audit mode).
3. Run `terraform plan` and verify the policy definition and assignment appear as expected.
4. Deploy to dev; review the compliance report after 24 hours.
5. If the compliance impact is understood, set `enforce = true` and promote through environments.
6. Document the policy's purpose and CIS/regulatory alignment in the `description` field.

### Policy Exemptions

If a resource legitimately cannot comply with a policy (e.g., a third-party integration that requires HTTP), an exemption must be created through Terraform (not the portal) and must include:

- A link to the approved exception request or change ticket.
- An expiry date no longer than 12 months.
- The scope narrowed to the specific resource, not a resource group or subscription.

---

## 7. State File Security

### Encryption at Rest

The Terraform state backend is an Azure Storage Account with the following security configuration:

- **Encryption**: Azure Storage encryption (AES-256) is enabled by default and cannot be disabled. State files are encrypted at rest without any additional configuration.
- **Infrastructure-level encryption**: If the storage account is configured with customer-managed keys (CMK) in Key Vault, the encryption key is under the team's control and can be rotated independently.

### Locking During Operations

Terraform uses Azure Blob Storage lease-based locking. When a `terraform apply` or `terraform plan` begins, it acquires an exclusive lease on the state blob. Any concurrent operation that attempts to acquire the same lease will fail immediately with a lock error. This prevents state corruption from concurrent applies.

If a lock is orphaned (e.g., a pipeline job is killed mid-run), the lock can be released with:

```bash
terraform force-unlock <LOCK_ID>
```

This command requires the Lock ID from the error message. It must only be run after confirming that no operation is actually in progress.

### Soft Delete and Versioning

The state storage account has soft delete enabled with a 30-day retention period and blob versioning enabled. If state is accidentally corrupted or deleted:

1. Navigate to the storage account in the Azure portal (or use the Azure CLI).
2. Enable the "Show deleted blobs" option to view soft-deleted state files.
3. Restore the previous version using blob versioning.
4. Verify the restored state matches the actual Azure resources before running any further Terraform operations.

### State File Access Control

Access to the state storage account follows the same private endpoint and RBAC model as other storage resources:

- Public network access to the storage account is disabled.
- The CI/CD pipeline identity has `Storage Blob Data Contributor` on the state container only, not on the storage account as a whole.
- Developer identities have `Storage Blob Data Reader` on the state container for read-only inspection. They do not have write access and cannot modify state manually.
- No SAS tokens with long expiry are issued for state access.

### What Must Never Be in State

Terraform state can contain sensitive values (passwords, keys) in plaintext even when `sensitive = true` is set on outputs — the `sensitive` flag suppresses display but does not affect state storage. For this reason:

- The state storage account's access logs must be enabled and sent to Log Analytics.
- Any access to the state blob by an identity other than the CI/CD pipeline must be treated as a potential security event and investigated.
- Secrets should flow through Key Vault data sources rather than being stored as Terraform resource attributes where possible.

---

## 8. CI/CD Security

### Environment Promotion Flow

```
Feature Branch --> PR --> Module CI (validate + lint + tfsec/checkov)
                           |
                      Merge to main
                           |
                  Dev: auto-plan --> auto-apply
                           |
             Staging: plan --> single-approver gate --> apply
                           |
               Prod: plan --> two-approver gate --> apply
```

No environment can be skipped. A change cannot be applied to production without first being applied to dev and staging. This ensures the plan has been reviewed against a realistic environment before production execution.

### Branch Protection Requirements

The `main` branch must have the following protections enabled:

- Require pull request reviews (minimum 1 reviewer for staging changes, minimum 2 for production-impacting changes).
- Require status checks to pass (Terraform validate, lint, tfsec, checkov) before merge.
- Require branches to be up to date before merging.
- Disallow force pushes.
- Disallow deletion of the branch.

### Approval Gates

Production applies require two approvers drawn from the list of designated approvers. Approvers must review the full `terraform plan` output, not just the PR diff. The plan is attached to the pipeline run as an artifact and linked in the approval request.

Approvers must verify:
- The resources being created, modified, or destroyed match the intent of the PR.
- No role assignments are being added without documented justification.
- No security group or firewall rules are being loosened.
- No public access is being enabled on any resource.

### Pipeline Identity Permissions

The pipeline identity (the managed identity or Azure AD application used via OIDC) should hold only the permissions required by the modules in the current repository. A CI/CD identity with `Owner` at the subscription level is a critical risk: a compromised pipeline could grant itself any permission and exfiltrate any secret.

Recommended scope model:

| Environment | Scope | Maximum Role |
|------------|-------|-------------|
| Dev | Dev resource group | Custom Terraform deployer role |
| Staging | Staging resource group | Custom Terraform deployer role |
| Prod | Prod resource group | Custom Terraform deployer role |

The custom Terraform deployer role should enumerate only the specific resource providers and operations used by the modules. It should explicitly deny `Microsoft.Authorization/roleAssignments/write` unless RBAC management is a required pipeline capability.

### Secret Hygiene in Pipelines

- Pipeline environment variables must not contain credentials. Use OIDC token exchange instead.
- If a secret must be passed to a pipeline step (e.g., a seed password for initial database setup), retrieve it from Key Vault at runtime using the pipeline's managed identity — do not store it as a pipeline secret variable.
- Pipeline logs must not print secrets. Mask any value retrieved from Key Vault using the pipeline's log masking feature.
- Audit pipeline run logs periodically to confirm no secrets are being inadvertently printed.

---

## 9. Security Scanning

### tfsec

`tfsec` performs static analysis of Terraform code and detects misconfigurations before deployment.

**Installation:**

```bash
# Using Homebrew (macOS/Linux)
brew install tfsec

# Using go install
go install github.com/aquasecurity/tfsec/cmd/tfsec@latest
```

**Running locally:**

```bash
# Scan the entire repository
tfsec .

# Scan a specific module
tfsec modules/key-vault/

# Output as JUnit XML for CI integration
tfsec . --format junit --out tfsec-results.xml
```

**CI integration:**

Add a tfsec step to the module CI workflow that runs on every PR. Treat HIGH and CRITICAL severity findings as build failures. MEDIUM findings should be reviewed and either fixed or suppressed with a documented justification.

To suppress a false positive or an accepted risk, add a `tfsec:ignore` comment inline:

```hcl
resource "azurerm_storage_account" "this" {
  # tfsec:ignore:azure-storage-queue-services-logging-enabled
  # Justification: Queue services not used; logging not applicable.
  ...
}
```

### checkov

`checkov` is a policy-as-code framework that covers Terraform, Kubernetes manifests, Dockerfiles, and CI configuration.

**Installation:**

```bash
pip install checkov
```

**Running locally:**

```bash
# Scan Terraform files
checkov -d . --framework terraform

# Scan with a specific check list
checkov -d . --check CKV_AZURE_1,CKV_AZURE_2

# Skip specific checks with justification
checkov -d . --skip-check CKV_AZURE_44 --skip-reason "Private endpoint used instead of service endpoint"

# Output results as SARIF for GitHub Code Scanning
checkov -d . --output sarif --output-file-path checkov-results.sarif
```

**Recommended checks to enable:**

| Check ID | Description |
|----------|-------------|
| CKV_AZURE_1 | Ensure Azure Instance does not use basic authentication |
| CKV_AZURE_2 | Ensure that managed disks use a specific set of disk encryption sets |
| CKV_AZURE_8 | Ensure AKS cluster has an API Server Authorized IP Ranges enabled |
| CKV_AZURE_35 | Ensure Key Vault is recoverable |
| CKV_AZURE_36 | Ensure Key Vault enables soft delete |
| CKV_AZURE_41 | Ensure the key vault is recoverable |
| CKV_AZURE_59 | Ensure Storage Account is not publicly accessible |
| CKV_AZURE_109 | Ensure that Azure storage account disables public access |

### Additional Tools

| Tool | Purpose | Run Frequency |
|------|---------|---------------|
| `trivy` | Container image and IaC vulnerability scanning | Every PR, nightly on images |
| `gitleaks` | Secret detection in git history and staged changes | Pre-commit hook, every PR |
| `terraform validate` | Syntax and provider schema validation | Every PR |
| `tflint` | Terraform linting and best practice enforcement | Every PR |
| Microsoft Defender for Cloud | Runtime posture assessment and threat detection | Continuous (always-on) |

### Handling Scan Findings

1. **Critical / High:** Block the PR. The finding must be fixed before merge. If it is a confirmed false positive, the suppression comment must include the justification and a ticket reference.
2. **Medium:** Non-blocking but must be triaged within five business days. If not fixed, a tracking issue must be opened.
3. **Low / Informational:** Logged for awareness. Address during scheduled hardening cycles.

---

## 10. Incident Response

### Credential Compromise

If a service principal secret, SAS token, or any credential is suspected to have been compromised:

1. **Contain immediately.** Revoke the credential in Azure AD or regenerate the storage key before investigating. Time between detection and revocation is the primary risk window.
   ```bash
   # Revoke a service principal credential
   az ad app credential delete --id <app-id> --key-id <key-id>

   # Regenerate a storage account key
   az storage account keys renew --account-name <name> --resource-group <rg> --key primary
   ```
2. **Assess scope.** Review Azure AD sign-in logs and resource audit logs for the time period the credential was valid. Determine which resources the credential could have accessed.
3. **Review Key Vault access logs.** If the compromised identity had Key Vault access, review which secrets were accessed and assume all accessed secrets are compromised.
4. **Rotate affected secrets.** Any secret that the compromised identity could have read must be rotated, not just revoked. Rotation includes updating all consumers of the secret.
5. **Document and report.** Open a security incident record. Document the timeline, scope, and remediation steps.

### Unauthorized RBAC Assignment

If a role assignment is discovered that does not correspond to a Terraform resource:

1. Identify the principal and the scope of the unauthorized assignment.
2. Check Azure AD audit logs for who created the assignment and from where.
3. Remove the assignment immediately:
   ```bash
   az role assignment delete --assignee <principal-id> --role <role-name> --scope <scope>
   ```
4. Prevent recurrence by verifying the CI/CD identity does not have `Microsoft.Authorization/roleAssignments/write` beyond what is required.
5. Open a security incident record.

### State File Tampering

If Terraform state is suspected to have been modified outside of a legitimate pipeline run:

1. Do not run `terraform apply` until the state is verified.
2. Compare the current state file against the last known-good version (use blob versioning to retrieve it).
3. If the state has been altered, restore the previous version and run `terraform plan` to identify the delta.
4. Review Log Analytics for storage account access events around the time of the suspected tampering.
5. Audit all identities with access to the state storage account and revoke any that are not expected.

### Public Exposure of a Private Resource

If a resource (storage blob, Key Vault, VM) is found to have public network access enabled:

1. Disable public access immediately through the Azure portal or CLI — do not wait for a Terraform run.
   ```bash
   # Disable public blob access on a storage account
   az storage account update --name <name> --resource-group <rg> --allow-blob-public-access false
   ```
2. Review access logs for the duration the resource was publicly accessible.
3. Update the Terraform configuration to ensure the resource is correctly configured.
4. Determine how public access was enabled (manual change, policy gap, module misconfiguration) and fix the root cause.

### Escalation Contacts

Define and maintain a current list of escalation contacts for security incidents. At minimum:

- Security team or CISO contact.
- Azure subscription owner.
- On-call engineering contact.
- Microsoft support (for Azure platform-level incidents): [https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade](https://portal.azure.com/#blade/Microsoft_Azure_Support/HelpAndSupportBlade)

---

## 11. Compliance Mapping

The following table maps the project's security controls to the CIS Microsoft Azure Foundations Benchmark (v2.0). Controls marked as Covered are addressed by the current Terraform configuration. Controls marked as Partial require additional configuration or process controls outside of Terraform.

### CIS Section 1: Identity and Access Management

| CIS Control | Description | Status | Implementation |
|-------------|-------------|--------|---------------|
| 1.1 | Ensure that multi-factor authentication is enabled for all privileged users | Partial | Enforced via Azure AD Conditional Access; not managed in this repo |
| 1.2 | Ensure that multi-factor authentication is enabled for all non-privileged users | Partial | Enforced via Azure AD Conditional Access |
| 1.21 | Ensure that no custom subscription Owner roles are created | Covered | `rbac-assignment` module precondition blocks unapproved Owner assignments |
| 1.22 | Ensure that no custom subscription roles are created that allow `*` actions | Covered | Custom role definitions enumerate specific actions; code review checklist enforces this |

### CIS Section 2: Microsoft Defender for Cloud

| CIS Control | Description | Status | Implementation |
|-------------|-------------|--------|---------------|
| 2.1 | Ensure Microsoft Defender for Servers is enabled | Partial | Enable via Azure Security Center; consider adding Terraform resource |
| 2.2 | Ensure Microsoft Defender for App Service is enabled | Partial | Enable via Azure Security Center |
| 2.13 | Ensure that Microsoft Defender for Key Vault is enabled | Partial | Enable via Azure Security Center |

### CIS Section 3: Storage Accounts

| CIS Control | Description | Status | Implementation |
|-------------|-------------|--------|---------------|
| 3.1 | Ensure that "Secure transfer required" is enabled | Covered | Azure Policy enforces HTTPS on storage accounts |
| 3.2 | Ensure that storage account access keys are periodically regenerated | Partial | Process control; consider automating via Azure Automation |
| 3.5 | Ensure that "Public access level" is disabled for storage accounts with blob containers | Covered | Azure Policy denies public blob access |
| 3.6 | Ensure that shared access signature tokens expire within an hour | Partial | Process control; enforced by team convention |
| 3.8 | Ensure soft delete is enabled for storage accounts | Covered | `storage-acc` module enables soft delete |

### CIS Section 4: Database Services

| CIS Control | Description | Status | Implementation |
|-------------|-------------|--------|---------------|
| 4.1–4.5 | Ensure SSL, audit logging, TDE enabled on database services | Partial | Depends on database services deployed; modules must enforce these |

### CIS Section 5: Logging and Monitoring

| CIS Control | Description | Status | Implementation |
|-------------|-------------|--------|---------------|
| 5.1 | Ensure that a diagnostic setting exists | Covered | Design principle: all resources emit diagnostics to Log Analytics |
| 5.1.5 | Ensure Storage logging is enabled for Blob service for read, write, and delete requests | Covered | State storage account logging enabled and sent to Log Analytics |

### CIS Section 6: Networking

| CIS Control | Description | Status | Implementation |
|-------------|-------------|--------|---------------|
| 6.1 | Ensure that RDP access from the Internet is evaluated and restricted | Covered | NSG default-deny-inbound; no RDP allow rules exist |
| 6.2 | Ensure that SSH access from the Internet is evaluated and restricted | Covered | NSG default-deny-inbound; no SSH allow rules exist |
| 6.3 | Ensure that UDP services are restricted from the Internet | Covered | NSG default-deny-inbound |
| 6.5 | Ensure that Network Watcher is enabled | Partial | Consider adding `azurerm_network_watcher` resource |

### CIS Section 8: Key Vault

| CIS Control | Description | Status | Implementation |
|-------------|-------------|--------|---------------|
| 8.1 | Ensure that Azure Key Vault disables public network access | Covered | Private endpoint enforced; public access disabled in `key-vault` module |
| 8.2 | Ensure Key Vault is recoverable | Covered | Soft delete and purge protection enabled in `key-vault` module |
| 8.5 | Ensure that the expiry date is set on all secrets | Partial | Process control; expiry dates should be set when writing secrets |

---

## 12. Security Review Checklist for PRs

Use this checklist when reviewing a pull request that modifies Terraform code. All items marked Required must be verified before approving. Items marked Recommended represent best practice but may be waived with documented justification.

### Authentication and Identity

- [ ] **Required** No new service principal credentials (client secrets, certificates) are introduced. OIDC or managed identity is used instead.
- [ ] **Required** No credentials, tokens, passwords, or keys appear in any `.tf`, `.tfvars`, `.auto.tfvars`, or variable default values.
- [ ] **Required** New managed identities are assigned only the specific roles they need.
- [ ] **Recommended** User-assigned managed identities are used in preference to system-assigned where the identity is shared or long-lived.

### RBAC and Authorization

- [ ] **Required** All new `azurerm_role_assignment` resources use the `rbac-assignment` module, not the raw resource directly.
- [ ] **Required** No new Owner role assignments are present unless `EXCEPTION-APPROVED` appears in the description with a linked ticket.
- [ ] **Required** Custom role definitions enumerate specific actions and do not contain wildcard (`*`) actions or data actions without explicit review.
- [ ] **Required** `assignable_scopes` on custom roles are narrowed to the minimum required scope.
- [ ] **Recommended** Each role assignment's `description` field states why the principal needs the role.

### Network Security

- [ ] **Required** No new public IP addresses are assigned to backend resources (non-gateway resources).
- [ ] **Required** No NSG rules open inbound access from `Internet` or `Any` source to any port other than 80/443 on gateway resources.
- [ ] **Required** New PaaS resources that support private endpoints have public network access disabled and a private endpoint configured.
- [ ] **Required** New subnets have an NSG associated.
- [ ] **Recommended** NSG rule descriptions explain the traffic flow being permitted.

### Secret Management

- [ ] **Required** No secrets are read from variable defaults or `.tfvars` files. Secrets are sourced from Key Vault data sources.
- [ ] **Required** Terraform outputs containing sensitive values have `sensitive = true` set.
- [ ] **Required** Any new Key Vault is configured with the RBAC access model, not vault access policies.
- [ ] **Recommended** New secrets written to Key Vault have an expiry date set.

### Policy and Compliance

- [ ] **Required** New resources have all required tags (`environment`, `owner`, `cost-center` at minimum).
- [ ] **Required** New storage resources comply with the no-public-access and HTTPS-only policies.
- [ ] **Recommended** New policy definitions start in Audit mode before being promoted to Deny.

### Scanning Results

- [ ] **Required** `tfsec` reports no new HIGH or CRITICAL findings. Any suppressed findings include an inline justification comment.
- [ ] **Required** `checkov` reports no new HIGH or CRITICAL findings. Any suppressed checks include justification.
- [ ] **Required** `terraform validate` passes.
- [ ] **Required** `tflint` reports no new errors.
- [ ] **Recommended** `gitleaks` pre-commit hook has run on all commits in the PR.

### State and Operations

- [ ] **Required** No changes to the Terraform backend configuration without explicit review from the platform team.
- [ ] **Required** Destructive changes (resources being destroyed) are called out explicitly in the PR description and have been reviewed.
- [ ] **Recommended** The PR description includes the `terraform plan` summary (counts of resources to add, change, destroy).

### General

- [ ] **Required** The PR does not add any files matching `.gitignore` exclusion patterns (`*.pem`, `*.key`, `.env`, `*.auto.tfvars`).
- [ ] **Required** Any exemptions from Azure Policy are implemented in Terraform with an expiry date and linked ticket, not through the portal.
- [ ] **Recommended** Infrastructure changes follow the environment promotion flow: dev first, then staging, then production.
