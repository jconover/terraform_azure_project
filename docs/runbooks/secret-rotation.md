# Secret Rotation Runbook

**Version:** 1.0.0
**Last Updated:** 2026-03-03
**Owner:** Platform Security Team
**Classification:** Internal — Restricted

---

## Table of Contents

1. [Overview of Secret Management Architecture](#1-overview-of-secret-management-architecture)
2. [Secret Rotation Schedule and Policy](#2-secret-rotation-schedule-and-policy)
3. [Rotating Application Secrets](#3-rotating-application-secrets)
4. [Rotating Storage Account Keys](#4-rotating-storage-account-keys)
5. [Rotating Service Principal Credentials](#5-rotating-service-principal-credentials)
6. [Certificate Renewal Procedures](#6-certificate-renewal-procedures)
7. [Automated Rotation with Azure Key Vault Auto-Rotation](#7-automated-rotation-with-azure-key-vault-auto-rotation)
8. [Verifying Secret Rotation Success](#8-verifying-secret-rotation-success)
9. [Emergency Secret Compromise Response](#9-emergency-secret-compromise-response)
10. [Audit Trail and Compliance Reporting](#10-audit-trail-and-compliance-reporting)

---

## 1. Overview of Secret Management Architecture

### 1.1 Architecture Summary

All secrets, keys, and certificates for this project are stored in Azure Key Vault. The Key Vault is provisioned via Terraform (`modules/key-vault/`) with the following security controls enforced at the infrastructure layer:

| Control | Configuration | Terraform Variable |
|---|---|---|
| Authorization model | RBAC (not legacy access policies) | `enable_rbac_authorization = true` |
| Purge protection | Enabled | `purge_protection_enabled = true` |
| Soft delete retention | 90 days | `soft_delete_retention_days = 90` |
| Network default action | Deny | `network_acls_default_action = "Deny"` |
| Public network access | Disabled | `public_network_access_enabled = false` |
| Network bypass | AzureServices only | hardcoded in `network_acls` block |
| Audit logging | AuditEvent + AllMetrics to Log Analytics | `log_analytics_workspace_id` |

### 1.2 RBAC Access Model

Because `enable_rbac_authorization = true`, access to Key Vault data plane operations is controlled exclusively through Azure RBAC role assignments. Legacy access policies are not used. The relevant built-in roles are:

| Role | Permissions | Typical Assignees |
|---|---|---|
| Key Vault Administrator | Full control of keys, secrets, certificates | Break-glass accounts only |
| Key Vault Secrets Officer | Create, read, update, delete secrets | CI/CD service principals, rotation automation |
| Key Vault Secrets User | Read secrets (get, list) | Application managed identities |
| Key Vault Crypto Officer | Manage keys | Key rotation automation |
| Key Vault Certificates Officer | Manage certificates | Certificate renewal automation |
| Key Vault Reader | Read metadata (not secret values) | Monitoring, auditors |

No human operator should hold `Key Vault Secrets Officer` or higher as a persistent assignment. Use Privileged Identity Management (PIM) for just-in-time elevation.

### 1.3 Secret Categories

| Category | Examples | Storage Object Type |
|---|---|---|
| Application secrets | API keys, database passwords, OAuth client secrets | Key Vault Secret |
| Storage credentials | Storage account shared keys, SAS tokens | Key Vault Secret |
| Service principal credentials | Client secrets, federated credentials | Key Vault Secret |
| Encryption keys | Customer-managed keys (CMK), data encryption keys | Key Vault Key |
| TLS/mTLS certificates | App Gateway certs, internal mTLS certs | Key Vault Certificate |

### 1.4 Naming Convention

All Key Vault objects follow the pattern:

```
<application>-<environment>-<purpose>[-<version>]
```

Examples:
- `myapp-prod-db-password`
- `myapp-prod-storage-key1`
- `myapp-prod-sp-client-secret`
- `myapp-prod-tls-cert`

Secret versions are managed natively by Key Vault. The current version is always resolved by applications using the versionless URI:

```
https://<vault-name>.vault.azure.net/secrets/<secret-name>
```

### 1.5 Network Access

The Key Vault network ACL defaults to `Deny`. Access is permitted only from:
- Explicitly listed CIDR ranges (`network_acls_ip_rules`)
- Explicitly listed VNet subnets (`network_acls_virtual_network_subnet_ids`)
- Azure trusted services (bypass = `AzureServices`)

Rotation operations from a workstation require either VPN connectivity into an allowed subnet or a temporary IP allowlist entry (see Section 3.2).

---

## 2. Secret Rotation Schedule and Policy

### 2.1 Rotation Policy by Secret Type

| Secret Type | Maximum Lifetime | Rotation Frequency | Method |
|---|---|---|---|
| Application API keys | 90 days | Every 60 days | Manual or auto-rotation |
| Database passwords | 90 days | Every 60 days | Manual |
| Storage account keys | 90 days | Every 60 days | Auto-rotation via Event Grid |
| Service principal client secrets | 180 days | Every 90 days | Manual with PIM |
| Managed identity credentials | N/A (platform-managed) | N/A | No action required |
| TLS certificates (public CA) | 398 days | 30 days before expiry | Auto-renewal via Key Vault |
| TLS certificates (internal CA) | 1 year | 60 days before expiry | Manual or auto-renewal |
| Customer-managed keys (CMK) | 1 year | Every 12 months | Auto-rotation policy |

### 2.2 Rotation Principles

- **Zero-downtime rotation:** All rotation procedures use a two-version approach. The new secret is stored and validated before the old secret is revoked.
- **Rotation does not equal deletion:** After rotation, the old version remains in Key Vault in a disabled state for the duration of the soft-delete retention period (90 days) for rollback purposes.
- **Applications must not cache secrets indefinitely:** Applications must reload secrets from Key Vault on startup and must implement a refresh interval no longer than 15 minutes for long-running processes. Use the Azure SDK's `SecretClient` with `GetSecret` (versionless URI) to always retrieve the current version.
- **Rotation must be logged:** Every rotation event must produce an entry in the Key Vault audit log (forwarded to Log Analytics) and a corresponding entry in the change management system.
- **Principle of least privilege during rotation:** Rotation automation runs under a dedicated service principal or managed identity with `Key Vault Secrets Officer` scoped to the target vault only.

### 2.3 Rotation Triggers

Rotation is triggered by any of the following:

1. Scheduled rotation (per the table above)
2. Employee offboarding when the departing individual had access to a secret value
3. Suspected or confirmed secret compromise (see Section 9)
4. Security audit finding
5. Application redeployment that changes the consuming identity
6. Key Vault access policy or RBAC change that may have inadvertently exposed a secret

### 2.4 Pre-Rotation Checklist

Before beginning any rotation procedure, confirm the following:

- [ ] Change management ticket created and approved
- [ ] Maintenance window scheduled (if rotation may cause application restarts)
- [ ] Rollback plan documented
- [ ] On-call engineer notified and available
- [ ] You have PIM-elevated access to `Key Vault Secrets Officer` on the target vault
- [ ] Network access confirmed (VPN connected or IP allowlisted)
- [ ] Applications consuming the secret identified and their restart procedure documented

---

## 3. Rotating Application Secrets

Application secrets include database passwords, third-party API keys, OAuth client secrets stored by the application, and any other string secret the application consumes at runtime.

### 3.1 Prerequisites

```bash
# Required tools
az --version          # Azure CLI 2.50.0+
jq --version          # jq 1.6+

# Authenticate
az login --tenant <tenant-id>

# Activate PIM role (Key Vault Secrets Officer)
# Navigate to: Entra ID > Privileged Identity Management > My roles > Activate
# Or via CLI:
az rest --method POST \
  --url "https://management.azure.com/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/<request-id>?api-version=2022-04-01-preview" \
  --body '{"properties":{"principalId":"<your-object-id>","roleDefinitionId":"<secrets-officer-role-id>","requestType":"SelfActivate","justification":"Secret rotation per ticket <TICKET-ID>","scheduleInfo":{"expiration":{"type":"AfterDuration","duration":"PT4H"}}}}'
```

### 3.2 Temporary Network Access (if required)

If your workstation IP is not in the Key Vault allowlist:

```bash
# Get your current public IP
MY_IP=$(curl -s https://api.ipify.org)

VAULT_NAME="<vault-name>"
RESOURCE_GROUP="<resource-group>"

# Add temporary IP rule
az keyvault update \
  --name "$VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --add networkRuleSet.ipRules "value=${MY_IP}/32"

echo "Temporary access granted for $MY_IP. Remove after rotation."
```

**Important:** Remove the temporary IP rule immediately after rotation is complete (see Section 3.6 cleanup step).

### 3.3 Step-by-Step: Rotate an Application Secret

**Step 1 — Identify the secret and its current version**

```bash
VAULT_NAME="<vault-name>"
SECRET_NAME="<application>-<env>-<purpose>"

# List all versions to understand history
az keyvault secret list-versions \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "[].{Version:id, Created:attributes.created, Enabled:attributes.enabled}" \
  --output table
```

**Step 2 — Generate the new secret value**

For passwords, use a cryptographically random generator. Never use human-chosen values.

```bash
# Generate a 48-character random secret (alphanumeric + special chars)
NEW_SECRET=$(openssl rand -base64 36 | tr -d '=+/' | cut -c1-48)
echo "New secret length: ${#NEW_SECRET}"
# Do NOT echo the secret value itself in a shared terminal session
```

For third-party API keys: obtain the new key from the provider's portal or API before proceeding to the next step.

**Step 3 — Store the new version in Key Vault**

```bash
# Set the new secret. Key Vault automatically creates a new version.
az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --value "$NEW_SECRET" \
  --description "Rotated on $(date -u +%Y-%m-%dT%H:%M:%SZ) — ticket <TICKET-ID>"

# Capture the new version ID
NEW_VERSION=$(az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "id" \
  --output tsv)

echo "New version stored: $NEW_VERSION"
```

**Step 4 — Set a content type and expiration on the new version**

```bash
ROTATION_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EXPIRY_DATE=$(date -u -d "+60 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
              date -u -v+60d +%Y-%m-%dT%H:%M:%SZ)  # macOS fallback

az keyvault secret set-attributes \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --expires "$EXPIRY_DATE" \
  --tags "rotatedOn=$ROTATION_DATE" "rotatedBy=$(az account show --query user.name -o tsv)" "ticket=<TICKET-ID>"
```

**Step 5 — Update the consuming application**

The approach depends on how the application reads the secret:

- **Managed identity + Azure SDK (recommended):** The application reads the versionless URI at startup. Restart the application or trigger a configuration reload. No code change required.
- **Environment variable via App Service / Container Apps:** Update the App Service application setting or Container Apps secret reference to point to the new version URI, then perform a revision restart.
- **Kubernetes / AKS with CSI driver:** The CSI Secret Store provider syncs automatically on the configured poll interval (default 2 minutes). Verify the pod's mounted secret file has updated before proceeding.
- **Hard-coded version in app config:** Update the version reference in the application configuration and redeploy.

```bash
# For Azure App Service: trigger a restart after confirming new secret is live
az webapp restart --name "<app-name>" --resource-group "<resource-group>"

# For Container Apps: create a new revision
az containerapp revision restart \
  --name "<app-name>" \
  --resource-group "<resource-group>" \
  --revision "<revision-name>"
```

**Step 6 — Validate the application is using the new secret**

```bash
# Check application health endpoint
curl -sf https://<app-fqdn>/health | jq .

# Check application logs for auth errors in the 5 minutes following restart
az monitor app-insights query \
  --app "<app-insights-name>" \
  --analytics-query "exceptions | where timestamp > ago(10m) | where outerMessage contains 'auth' or outerMessage contains 'credential' | count" \
  --output table
```

**Step 7 — Disable the old secret version**

Only disable the old version after confirming the application is healthy with the new secret.

```bash
# List versions and identify the old one
OLD_VERSION_ID=$(az keyvault secret list-versions \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "sort_by([?attributes.enabled==\`true\`], &attributes.created)[-2].id" \
  --output tsv)

if [ -n "$OLD_VERSION_ID" ]; then
  # Extract just the version component
  OLD_VERSION=$(basename "$OLD_VERSION_ID")

  az keyvault secret set-attributes \
    --vault-name "$VAULT_NAME" \
    --name "$SECRET_NAME" \
    --version "$OLD_VERSION" \
    --enabled false

  echo "Old version $OLD_VERSION disabled."
else
  echo "No previous enabled version found — nothing to disable."
fi
```

**Step 8 — Revoke the secret at the source (if applicable)**

For third-party API keys: revoke the old key in the provider's portal. For database passwords: change the password at the database level (the Key Vault operation in Step 3 only updates the stored copy — the actual credential must be changed at the source).

**Step 9 — Cleanup**

```bash
# Remove temporary IP allowlist entry if added in Step 3.2
az keyvault update \
  --name "$VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --remove networkRuleSet.ipRules 0
  # Note: index 0 assumes the temp rule was the only addition; verify before removing

# Clear secret from shell history and environment
unset NEW_SECRET
history -d $(history 1 | awk '{print $1}')
```

---

## 4. Rotating Storage Account Keys

Azure Storage accounts have two access keys (key1 and key2). Rotate them alternately to maintain continuous access.

### 4.1 Prerequisites

- PIM elevation to `Key Vault Secrets Officer` on the target vault
- `Storage Account Key Operator Service Role` on the storage account (or equivalent RBAC)
- Knowledge of all applications consuming the storage account key

### 4.2 Identify the Active Key

```bash
VAULT_NAME="<vault-name>"
STORAGE_ACCOUNT="<storage-account-name>"
RESOURCE_GROUP="<resource-group>"
SECRET_NAME_KEY1="<app>-<env>-storage-key1"
SECRET_NAME_KEY2="<app>-<env>-storage-key2"

# Check which key is currently active in Key Vault
CURRENT_KEY=$(az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME_KEY1" \
  --query "value" \
  --output tsv 2>/dev/null)

ACTUAL_KEY1=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?keyName=='key1'].value" \
  --output tsv)

if [ "$CURRENT_KEY" = "$ACTUAL_KEY1" ]; then
  echo "Active key: key1. Will rotate key2, then update applications to key2, then rotate key1."
  KEY_TO_ROTATE="key2"
  KEY_SECRET_TO_UPDATE="$SECRET_NAME_KEY2"
else
  echo "Active key: key2. Will rotate key1, then update applications to key1, then rotate key2."
  KEY_TO_ROTATE="key1"
  KEY_SECRET_TO_UPDATE="$SECRET_NAME_KEY1"
fi
```

### 4.3 Step-by-Step: Rotate Storage Account Key

**Step 1 — Regenerate the inactive key**

```bash
az storage account keys renew \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --key "$KEY_TO_ROTATE"

# Retrieve the new key value
NEW_KEY_VALUE=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?keyName=='$KEY_TO_ROTATE'].value" \
  --output tsv)
```

**Step 2 — Store the new key in Key Vault**

```bash
az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name "$KEY_SECRET_TO_UPDATE" \
  --value "$NEW_KEY_VALUE" \
  --description "Rotated $KEY_TO_ROTATE on $(date -u +%Y-%m-%dT%H:%M:%SZ)"

unset NEW_KEY_VALUE
```

**Step 3 — Update applications to use the new key**

Update any application configuration or connection strings that reference the old active key, pointing them to the newly rotated key. Restart or redeploy as needed.

**Step 4 — Validate applications are healthy**

Wait at least 5 minutes and monitor for storage-related errors before proceeding.

**Step 5 — Rotate the previously active key**

After confirming all applications are using the new key successfully, regenerate the old active key so it is no longer valid.

```bash
OLD_KEY=$([ "$KEY_TO_ROTATE" = "key2" ] && echo "key1" || echo "key2")

az storage account keys renew \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --key "$OLD_KEY"

# Update Key Vault with the newly regenerated old key value (for completeness)
OLD_KEY_SECRET=$([ "$KEY_TO_ROTATE" = "key2" ] && echo "$SECRET_NAME_KEY1" || echo "$SECRET_NAME_KEY2")
NEW_OLD_KEY_VALUE=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?keyName=='$OLD_KEY'].value" \
  --output tsv)

az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name "$OLD_KEY_SECRET" \
  --value "$NEW_OLD_KEY_VALUE"

unset NEW_OLD_KEY_VALUE
```

### 4.4 Preferred Alternative: Use Managed Identities

Where possible, replace storage account key usage with Azure managed identity assignments to the Storage Blob Data Contributor / Reader roles. This eliminates the need for key rotation entirely. Storage account key rotation should only remain in scope for legacy integrations that cannot use managed identities.

---

## 5. Rotating Service Principal Credentials

Service principal client secrets have a maximum lifetime. This procedure covers rotating client secrets stored in Key Vault. For service principals that can use federated credentials (workload identity federation), migrate away from client secrets — federated credentials do not require rotation.

### 5.1 Prerequisites

- PIM elevation to `Application Administrator` or `Cloud Application Administrator` in Entra ID
- PIM elevation to `Key Vault Secrets Officer` on the target vault
- The Object ID and Application ID of the service principal

### 5.2 Step-by-Step: Rotate a Service Principal Client Secret

**Step 1 — Identify the service principal and existing credentials**

```bash
APP_DISPLAY_NAME="<service-principal-display-name>"

APP_ID=$(az ad app list \
  --display-name "$APP_DISPLAY_NAME" \
  --query "[0].appId" \
  --output tsv)

SP_OBJECT_ID=$(az ad sp show \
  --id "$APP_ID" \
  --query "id" \
  --output tsv)

echo "App ID: $APP_ID"
echo "SP Object ID: $SP_OBJECT_ID"

# List existing credentials (shows key IDs and expiry — not the secret values)
az ad app credential list \
  --id "$APP_ID" \
  --query "[].{KeyId:keyId, DisplayName:displayName, EndDate:endDateTime}" \
  --output table
```

**Step 2 — Create a new client secret with defined expiry**

```bash
# Create new credential with 90-day expiry
NEW_CRED=$(az ad app credential reset \
  --id "$APP_ID" \
  --append \
  --display-name "rotation-$(date +%Y%m%d)-ticket-<TICKET-ID>" \
  --years 0.25 \
  --query "{clientSecret:password, keyId:keyId}" \
  --output json)

NEW_CLIENT_SECRET=$(echo "$NEW_CRED" | jq -r '.clientSecret')
NEW_KEY_ID=$(echo "$NEW_CRED" | jq -r '.keyId')
echo "New credential key ID: $NEW_KEY_ID"
```

**Step 3 — Store the new secret in Key Vault**

```bash
VAULT_NAME="<vault-name>"
SECRET_NAME="<app>-<env>-sp-client-secret"
EXPIRY_DATE=$(date -u -d "+85 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
              date -u -v+85d +%Y-%m-%dT%H:%M:%SZ)

az keyvault secret set \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --value "$NEW_CLIENT_SECRET" \
  --expires "$EXPIRY_DATE" \
  --description "SP: $APP_DISPLAY_NAME | KeyId: $NEW_KEY_ID | Rotated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

unset NEW_CLIENT_SECRET
unset NEW_CRED
```

**Step 4 — Update all consumers of the service principal**

Identify every workload that uses this service principal (pipeline variables, app configuration, other Key Vault references) and update them to read the new Key Vault secret version. Trigger restarts or pipeline re-runs as needed.

**Step 5 — Validate the new credential works**

```bash
TENANT_ID="<tenant-id>"

# Test authentication with the new credential (retrieve from vault — do not echo)
NEW_SECRET_VAL=$(az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "value" \
  --output tsv)

az login \
  --service-principal \
  --username "$APP_ID" \
  --password "$NEW_SECRET_VAL" \
  --tenant "$TENANT_ID" \
  --allow-no-subscriptions

echo "Authentication test result: $?"
az logout
unset NEW_SECRET_VAL
```

**Step 6 — Remove the old credential from Entra ID**

Only after confirming all consumers are operating successfully with the new credential:

```bash
OLD_KEY_ID="<key-id-of-old-credential>"

az ad app credential delete \
  --id "$APP_ID" \
  --key-id "$OLD_KEY_ID"

echo "Old credential $OLD_KEY_ID removed."
```

### 5.3 Migration Path: Federated Credentials

To eliminate client secret rotation for workloads running on Azure (AKS, Container Apps, VMs), migrate to managed identities. For workloads running in GitHub Actions or Azure DevOps, configure workload identity federation:

```bash
# Example: add federated credential for GitHub Actions
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "github-actions-<repo>",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<org>/<repo>:environment:<env>",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

Once federated credentials are in place, remove all client secrets from the application registration.

---

## 6. Certificate Renewal Procedures

### 6.1 Certificate Types and Storage

Key Vault stores certificates as first-class objects. When a certificate is stored in Key Vault as a `Certificate` object (not a `Secret`), its associated private key and public certificate are accessible via both the Certificate and Secret APIs. Applications should always retrieve the certificate via the Secret API (PFX/PEM) to get the full chain.

### 6.2 Checking Certificate Expiry

```bash
VAULT_NAME="<vault-name>"

# List all certificates with expiry dates
az keyvault certificate list \
  --vault-name "$VAULT_NAME" \
  --include-pending true \
  --query "[].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires, NotBefore:attributes.notBefore}" \
  --output table

# Check a specific certificate
CERT_NAME="<app>-<env>-tls-cert"
az keyvault certificate show \
  --vault-name "$VAULT_NAME" \
  --name "$CERT_NAME" \
  --query "{Subject:policy.x509CertificateProperties.subject, SANs:policy.x509CertificateProperties.subjectAlternativeNames, Expires:attributes.expires, Issuer:policy.issuerParameters.name, AutoRenew:policy.lifetimeActions}" \
  --output json
```

### 6.3 Auto-Renewal via Key Vault (Managed Certificates)

For certificates issued by integrated CAs (DigiCert, GlobalSign via Key Vault integration), configure auto-renewal:

```bash
# Configure renewal 30 days before expiry
az keyvault certificate set-attributes \
  --vault-name "$VAULT_NAME" \
  --name "$CERT_NAME" \
  --policy '{
    "lifetimeActions": [
      {
        "trigger": {"daysBeforeExpiry": 30},
        "action": {"actionType": "AutoRenew"}
      },
      {
        "trigger": {"daysBeforeExpiry": 10},
        "action": {"actionType": "EmailContacts"}
      }
    ]
  }'

# Set certificate contacts for expiry notifications
az keyvault certificate contact add \
  --vault-name "$VAULT_NAME" \
  --email-address "platform-security@<domain>"
```

### 6.4 Manual Certificate Renewal

For certificates that cannot be auto-renewed (self-signed, internal PKI without Key Vault integration):

**Step 1 — Generate a Certificate Signing Request (CSR) via Key Vault**

```bash
CERT_NAME="<app>-<env>-tls-cert"
DOMAIN="<app.domain.com>"

az keyvault certificate create \
  --vault-name "$VAULT_NAME" \
  --name "${CERT_NAME}-new" \
  --policy '{
    "keyProperties": {
      "keyType": "RSA",
      "keySize": 4096,
      "reuseKey": false,
      "exportable": true
    },
    "secretProperties": {"contentType": "application/x-pkcs12"},
    "x509CertificateProperties": {
      "subject": "CN='"$DOMAIN"'",
      "subjectAlternativeNames": {"dnsNames": ["'"$DOMAIN"'"]},
      "keyUsage": ["digitalSignature", "keyEncipherment"],
      "ekus": ["1.3.6.1.5.5.7.3.1"],
      "validityInMonths": 12
    },
    "issuerParameters": {"name": "Unknown", "certificateTransparency": true},
    "lifetimeActions": [
      {"trigger": {"daysBeforeExpiry": 30}, "action": {"actionType": "EmailContacts"}}
    ]
  }'

# Download the CSR for signing
az keyvault certificate pending show \
  --vault-name "$VAULT_NAME" \
  --name "${CERT_NAME}-new" \
  --query "csr" \
  --output tsv | base64 -d > "${CERT_NAME}.csr"
```

**Step 2 — Submit CSR to CA and retrieve signed certificate**

Submit `${CERT_NAME}.csr` to your CA (internal PKI or public CA). Retrieve the signed certificate in PEM format.

**Step 3 — Merge the signed certificate into Key Vault**

```bash
# Convert PEM cert to base64
CERT_BASE64=$(base64 -w 0 signed-cert.pem)

az keyvault certificate complete \
  --vault-name "$VAULT_NAME" \
  --name "${CERT_NAME}-new" \
  --certificate "${CERT_BASE64}"
```

**Step 4 — Update application to use the new certificate**

For Azure Application Gateway, Front Door, or App Service, update the certificate binding:

```bash
# App Service: update SSL binding
az webapp config ssl bind \
  --name "<app-name>" \
  --resource-group "<resource-group>" \
  --certificate-thumbprint "<new-thumbprint>" \
  --ssl-type SNI

# Application Gateway: update HTTP listener
# (Use az network application-gateway ssl-cert and update listener accordingly)
```

**Step 5 — Disable and archive the old certificate**

```bash
OLD_VERSION=$(az keyvault certificate list-versions \
  --vault-name "$VAULT_NAME" \
  --name "$CERT_NAME" \
  --query "sort_by([?attributes.enabled==\`true\`], &attributes.created)[-2].id" \
  --output tsv | xargs basename)

az keyvault certificate set-attributes \
  --vault-name "$VAULT_NAME" \
  --name "$CERT_NAME" \
  --version "$OLD_VERSION" \
  --enabled false
```

---

## 7. Automated Rotation with Azure Key Vault Auto-Rotation

### 7.1 Architecture Overview

Azure Key Vault supports automated rotation for secrets via an Event Grid + Azure Functions pattern:

```
Key Vault (SecretNearExpiry event)
    --> Azure Event Grid Topic
        --> Azure Function (rotation logic)
            --> Generate new secret at source
            --> az keyvault secret set (new version)
            --> Notify via email/Teams/PagerDuty
```

Key Vault also supports native auto-rotation for storage account keys via the managed storage account feature.

### 7.2 Enable Managed Storage Account Rotation (Native)

This is the simplest form of automated rotation and requires no custom code:

```bash
VAULT_NAME="<vault-name>"
STORAGE_ACCOUNT="<storage-account-name>"
RESOURCE_GROUP="<resource-group>"

# Grant Key Vault the Storage Account Key Operator role
KV_OBJECT_ID=$(az keyvault show \
  --name "$VAULT_NAME" \
  --query "identity.principalId" \
  --output tsv)

STORAGE_ID=$(az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" \
  --output tsv)

az role assignment create \
  --role "Storage Account Key Operator Service Role" \
  --assignee-object-id "$KV_OBJECT_ID" \
  --scope "$STORAGE_ID"

# Register the storage account with Key Vault for management
az keyvault storage add \
  --vault-name "$VAULT_NAME" \
  --name "$STORAGE_ACCOUNT" \
  --account-resource-id "$STORAGE_ID" \
  --active-key-name key1 \
  --auto-regenerate-key true \
  --regeneration-period P60D
```

### 7.3 Event Grid-Based Rotation for Application Secrets

**Step 1 — Deploy the rotation function (Terraform / bicep)**

The rotation function must be deployed to the same VNet that is allowlisted in the Key Vault network ACLs. Its managed identity must have `Key Vault Secrets Officer`.

**Step 2 — Configure the Key Vault Near-Expiry event subscription**

```bash
VAULT_ID=$(az keyvault show \
  --name "$VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "id" \
  --output tsv)

FUNCTION_ENDPOINT="https://<function-app>.azurewebsites.net/api/RotateSecret?code=<function-key>"

az eventgrid event-subscription create \
  --name "kv-secret-near-expiry" \
  --source-resource-id "$VAULT_ID" \
  --endpoint "$FUNCTION_ENDPOINT" \
  --endpoint-type webhook \
  --included-event-types "Microsoft.KeyVault.SecretNearExpiry" \
  --advanced-filter data.ObjectName StringBeginsWith "myapp-prod-"
```

**Step 3 — Configure rotation policy on individual secrets**

```bash
SECRET_NAME="myapp-prod-db-password"

az keyvault secret set-attributes \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --expires "$(date -u -d '+60 days' +%Y-%m-%dT%H:%M:%SZ)"

# The SecretNearExpiry event fires at 30 days and 10 days before expiry by default.
# The rotation function handles the event and rotates before expiry.
```

### 7.4 Rotation Function Contract

The rotation Azure Function must implement the following contract:

1. Receive the `Microsoft.KeyVault.SecretNearExpiry` event payload
2. Extract `data.ObjectName` (secret name) and `data.VaultName`
3. Look up the rotation procedure for the secret based on naming convention or a configuration table
4. Generate the new credential at the authoritative source (database, third-party API, etc.)
5. Call `az keyvault secret set` (or SDK equivalent) to store the new version
6. Set expiry on the new version
7. Disable the old version
8. Emit a rotation completion event to Log Analytics and alerting channel
9. Return HTTP 200 on success; Key Vault Event Grid retries on non-200

### 7.5 Monitoring Automated Rotation

```bash
# Query Log Analytics for rotation events in the past 7 days
az monitor log-analytics query \
  --workspace "$LOG_ANALYTICS_WORKSPACE_ID" \
  --analytics-query "
    AzureDiagnostics
    | where ResourceType == 'VAULTS'
    | where OperationName == 'SecretSet'
    | where ResultType == 'Success'
    | where TimeGenerated > ago(7d)
    | project TimeGenerated, CallerIPAddress, identity_claim_appid_g, requestUri_s
    | order by TimeGenerated desc
  " \
  --output table
```

---

## 8. Verifying Secret Rotation Success

After any rotation procedure, complete all of the following verification checks before closing the change ticket.

### 8.1 Key Vault State Verification

```bash
VAULT_NAME="<vault-name>"
SECRET_NAME="<secret-name>"

# 1. Confirm new version is the current enabled version
az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "{CurrentVersion:id, Enabled:attributes.enabled, Expires:attributes.expires, Updated:attributes.updated}" \
  --output json

# 2. Confirm old versions are disabled
az keyvault secret list-versions \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "[].{Version:id, Enabled:attributes.enabled, Created:attributes.created}" \
  --output table

# 3. Confirm expiry is set on the new version (should not be null)
EXPIRY=$(az keyvault secret show \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "attributes.expires" \
  --output tsv)

if [ -z "$EXPIRY" ] || [ "$EXPIRY" = "None" ]; then
  echo "WARNING: No expiry set on secret. Set an expiry to enable auto-rotation events."
else
  echo "Expiry set: $EXPIRY"
fi
```

### 8.2 Application Health Verification

```bash
# Check HTTP health endpoint returns 200
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://<app-fqdn>/health)
if [ "$HTTP_STATUS" = "200" ]; then
  echo "PASS: Application health check returned 200"
else
  echo "FAIL: Application health check returned $HTTP_STATUS — investigate immediately"
fi

# Check for authentication errors in App Insights (last 15 minutes)
az monitor app-insights query \
  --app "<app-insights-name>" \
  --analytics-query "
    exceptions
    | where timestamp > ago(15m)
    | where severityLevel >= 3
    | summarize count() by outerType
  " \
  --output table
```

### 8.3 Audit Log Verification

```bash
LOG_ANALYTICS_WORKSPACE_ID="<workspace-id>"

# Confirm the SecretSet operation appears in the audit log
az monitor log-analytics query \
  --workspace "$LOG_ANALYTICS_WORKSPACE_ID" \
  --analytics-query "
    AzureDiagnostics
    | where ResourceType == 'VAULTS'
    | where ResourceId contains '$VAULT_NAME'
    | where OperationName in ('SecretSet', 'SecretSetAttributes', 'SecretDelete')
    | where TimeGenerated > ago(2h)
    | project TimeGenerated, OperationName, ResultType, CallerIPAddress, requestUri_s
    | order by TimeGenerated desc
    | limit 20
  " \
  --output table
```

### 8.4 Rotation Verification Checklist

After completing rotation, confirm every item:

- [ ] New secret version is enabled in Key Vault
- [ ] New secret version has an expiry date set
- [ ] All previous versions are disabled
- [ ] Rotation timestamp tag is present on the new version
- [ ] Application health endpoint returns 200
- [ ] No new authentication or authorization errors in App Insights
- [ ] SecretSet operation visible in Key Vault audit log in Log Analytics
- [ ] Old credential has been revoked at the source (if applicable — DB password, API key, SP credential)
- [ ] Change management ticket updated with rotation details
- [ ] Temporary network access rules removed (if added)
- [ ] Local shell environment cleared of secret values

---

## 9. Emergency Secret Compromise Response

Use this procedure when a secret is confirmed or suspected to have been exposed. Treat all suspected compromises as confirmed until proven otherwise. Speed is critical — the goal is to revoke the compromised credential and replace it within 30 minutes of detection.

### 9.1 Severity Classification

| Severity | Criteria | Target Revocation Time |
|---|---|---|
| P0 - Critical | Production secret in public repository, active exfiltration evidence | < 15 minutes |
| P1 - High | Production secret exposed to unauthorized internal party, credential in logs | < 30 minutes |
| P2 - Medium | Non-production secret exposed, no evidence of use | < 4 hours |
| P3 - Low | Suspected exposure, no confirmation | < 24 hours |

### 9.2 Immediate Response Steps

**Step 0 — Declare incident and notify**

```
Notify: Security team, on-call engineer, application owner
Channel: #security-incidents (or equivalent)
Incident ticket: Create immediately with:
  - Affected secret name
  - Suspected exposure vector (commit hash, log link, etc.)
  - Time of suspected exposure
  - P-level classification
```

**Step 1 — Disable the compromised secret version immediately**

Do not wait for a new secret to be ready. Disable the compromised version now, even if it causes a service disruption. A service outage is preferable to continued unauthorized access.

```bash
VAULT_NAME="<vault-name>"
SECRET_NAME="<compromised-secret-name>"

# Disable ALL versions of the secret immediately
for VERSION_ID in $(az keyvault secret list-versions \
  --vault-name "$VAULT_NAME" \
  --name "$SECRET_NAME" \
  --query "[?attributes.enabled==\`true\`].id" \
  --output tsv); do

  VERSION=$(basename "$VERSION_ID")
  az keyvault secret set-attributes \
    --vault-name "$VAULT_NAME" \
    --name "$SECRET_NAME" \
    --version "$VERSION" \
    --enabled false
  echo "Disabled version: $VERSION"
done
```

**Step 2 — Revoke the credential at the authoritative source**

- **Database password:** Change the password immediately at the database level
- **API key:** Revoke via the API provider's portal or admin API
- **Service principal client secret:** Delete the specific key ID from Entra ID (Section 5.2, Step 6)
- **Storage account key:** Regenerate the key immediately (Section 4.3, Step 1)
- **Certificate:** Initiate revocation with the issuing CA

**Step 3 — Review Key Vault audit logs for unauthorized access**

```bash
LOG_ANALYTICS_WORKSPACE_ID="<workspace-id>"

# Check for any secret access (GetSecret) in the window before compromise detection
az monitor log-analytics query \
  --workspace "$LOG_ANALYTICS_WORKSPACE_ID" \
  --analytics-query "
    AzureDiagnostics
    | where ResourceType == 'VAULTS'
    | where ResourceId contains '$VAULT_NAME'
    | where OperationName == 'SecretGet'
    | where requestUri_s contains '$SECRET_NAME'
    | where TimeGenerated > ago(72h)
    | project TimeGenerated, OperationName, CallerIPAddress, identity_claim_appid_g, ResultType, requestUri_s
    | order by TimeGenerated asc
  " \
  --output table
```

**Step 4 — Assess blast radius**

1. Identify all resources accessible using the compromised credential
2. Review access logs on those resources for unauthorized activity during the exposure window
3. Determine if data was read, modified, or exfiltrated
4. If exfiltration is suspected, escalate to a data breach response procedure

**Step 5 — Generate and deploy the replacement secret**

Follow the full procedure from Section 3 (application secrets), Section 4 (storage keys), or Section 5 (service principal) as appropriate. Expedite — skip the maintenance window requirement but follow all other steps.

**Step 6 — Re-enable service**

After the new secret is in place and validated, confirm applications are healthy and restore normal operation.

**Step 7 — Post-incident review**

Within 48 hours of resolution, hold a post-incident review covering:
- Root cause of the exposure
- Timeline from exposure to detection to remediation
- Systems accessed during the exposure window
- Process improvements to prevent recurrence
- Metrics: time-to-detect (TTD), time-to-revoke (TTR), time-to-recover (TTRec)

Document findings in the incident ticket and schedule follow-up remediation items.

### 9.3 Scanning for Secrets in Version Control

If the compromise vector is a code repository:

```bash
# Install truffleHog or gitleaks if not present
# gitleaks detect: scan current working tree
gitleaks detect --source . --report-format json --report-path gitleaks-report.json

# If the secret is found in git history, rotate immediately and then sanitize history
# (History sanitization is a separate procedure — do not delay secret rotation for it)
```

After rotation, notify all contributors to the repository to re-clone, as history sanitization rewrites commit SHAs.

---

## 10. Audit Trail and Compliance Reporting

### 10.1 Log Analytics Queries for Compliance

The Key Vault diagnostic setting forwards `AuditEvent` and `AzurePolicyEvaluationDetails` category logs to Log Analytics. All secret operations (Get, Set, Delete, List, Backup, Restore) produce audit records.

**All secret operations in a time range:**

```kql
AzureDiagnostics
| where ResourceType == "VAULTS"
| where OperationName in (
    "SecretGet", "SecretSet", "SecretDelete",
    "SecretList", "SecretListVersions", "SecretSetAttributes",
    "SecretBackup", "SecretRestore", "SecretPurge"
  )
| where TimeGenerated between (datetime(<start>) .. datetime(<end>))
| project
    TimeGenerated,
    OperationName,
    ResultType,
    CallerIPAddress,
    identity_claim_upn_s,
    identity_claim_appid_g,
    requestUri_s
| order by TimeGenerated desc
```

**Failed access attempts (potential unauthorized access):**

```kql
AzureDiagnostics
| where ResourceType == "VAULTS"
| where ResultType != "Success"
| where OperationName in ("SecretGet", "SecretSet", "SecretDelete")
| where TimeGenerated > ago(30d)
| summarize
    FailureCount = count(),
    UniqueSecrets = dcount(requestUri_s),
    UniqueCallers = dcount(CallerIPAddress)
    by OperationName, ResultSignature, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

**Secrets accessed by humans (vs. service principals):**

```kql
AzureDiagnostics
| where ResourceType == "VAULTS"
| where OperationName == "SecretGet"
| where isnotempty(identity_claim_upn_s)  // UPN present = human account
| where TimeGenerated > ago(30d)
| project TimeGenerated, UserPrincipalName = identity_claim_upn_s, requestUri_s, CallerIPAddress
| order by TimeGenerated desc
```

**Secrets not rotated within policy window:**

```kql
AzureDiagnostics
| where ResourceType == "VAULTS"
| where OperationName == "SecretSet"
| where TimeGenerated > ago(180d)
| summarize LastRotated = max(TimeGenerated) by SecretName = tostring(split(requestUri_s, "/")[4])
| extend DaysSinceRotation = datetime_diff("day", now(), LastRotated)
| where DaysSinceRotation > 60
| order by DaysSinceRotation desc
```

### 10.2 Generating a Compliance Report

Run the following script to produce a point-in-time rotation compliance report:

```bash
#!/usr/bin/env bash
set -euo pipefail

VAULT_NAME="<vault-name>"
RESOURCE_GROUP="<resource-group>"
LOG_ANALYTICS_WORKSPACE_ID="<workspace-id>"
REPORT_DATE=$(date -u +%Y-%m-%d)
REPORT_FILE="kv-rotation-compliance-${REPORT_DATE}.json"

echo "Generating Key Vault secret rotation compliance report for $VAULT_NAME"
echo "Report date: $REPORT_DATE"

# Collect all secrets with their current version metadata
az keyvault secret list \
  --vault-name "$VAULT_NAME" \
  --query "[].{
    Name: name,
    Enabled: attributes.enabled,
    Expires: attributes.expires,
    Updated: attributes.updated,
    ContentType: contentType
  }" \
  --output json > "${REPORT_FILE}.tmp"

# Enrich with version count
python3 - <<'PYEOF'
import json, subprocess, sys

with open("${REPORT_FILE}.tmp") as f:
    secrets = json.load(f)

enriched = []
for s in secrets:
    name = s["Name"]
    versions = json.loads(subprocess.check_output([
        "az", "keyvault", "secret", "list-versions",
        "--vault-name", "${VAULT_NAME}",
        "--name", name,
        "--output", "json"
    ]))
    s["VersionCount"] = len(versions)
    s["EnabledVersions"] = sum(1 for v in versions if v["attributes"]["enabled"])
    enriched.append(s)

with open("${REPORT_FILE}", "w") as f:
    json.dump({"reportDate": "${REPORT_DATE}", "vault": "${VAULT_NAME}", "secrets": enriched}, f, indent=2)
PYEOF

echo "Report written to $REPORT_FILE"
rm "${REPORT_FILE}.tmp"
```

### 10.3 Alert Rules for Rotation Compliance

Create the following Azure Monitor alert rules on the Log Analytics workspace:

| Alert Name | Query | Condition | Action |
|---|---|---|---|
| KV Secret Not Rotated | Secrets with `Updated` > 60 days ago | Count > 0 | PagerDuty P2 + email |
| KV Secret Near Expiry | Secrets with `Expires` < 14 days | Count > 0 | PagerDuty P1 + email |
| KV Secret Expired | Secrets with `Expires` < now() | Count > 0 | PagerDuty P0 + email |
| KV Unauthorized Access | Failed `SecretGet` for same caller 5+ times in 5 min | Count > 5 | PagerDuty P0 |
| KV Human Secret Access | `SecretGet` with UPN (non-SP) caller | Count > 0 | Security team email |
| KV Secret Access Outside Hours | `SecretGet` outside 06:00-20:00 UTC | Count > 0 | Security team email |

### 10.4 Compliance Evidence Collection (SOC 2 / ISO 27001)

For audit evidence, collect the following artifacts quarterly:

1. **Secret inventory report** — Output of `az keyvault secret list` with expiry and rotation dates
2. **Rotation history** — Log Analytics query output for all `SecretSet` operations in the audit period
3. **Access review** — RBAC role assignments on the Key Vault (`az role assignment list --scope <vault-id>`)
4. **Failed access report** — Log Analytics query for all non-success operations
5. **Alert configuration** — Export of Azure Monitor alert rules
6. **Diagnostic setting proof** — Output of `az monitor diagnostic-settings list --resource <vault-id>`

```bash
# Collect all evidence items into a dated directory
EVIDENCE_DIR="kv-audit-evidence-$(date +%Y-Q%q)" 2>/dev/null || EVIDENCE_DIR="kv-audit-evidence-$(date +%Y-%m)"
mkdir -p "$EVIDENCE_DIR"

# Secret inventory
az keyvault secret list --vault-name "$VAULT_NAME" --output json > "$EVIDENCE_DIR/secret-inventory.json"

# RBAC assignments
az role assignment list \
  --scope "$(az keyvault show --name "$VAULT_NAME" --query id -o tsv)" \
  --output json > "$EVIDENCE_DIR/rbac-assignments.json"

# Diagnostic settings
az monitor diagnostic-settings list \
  --resource "$(az keyvault show --name "$VAULT_NAME" --query id -o tsv)" \
  --output json > "$EVIDENCE_DIR/diagnostic-settings.json"

echo "Evidence collected in $EVIDENCE_DIR/"
```

### 10.5 Retention Requirements

| Log / Artifact | Minimum Retention | Storage Location |
|---|---|---|
| Key Vault audit logs (AuditEvent) | 1 year (2 years for PCI/HIPAA) | Log Analytics workspace |
| Access log exports (compliance evidence) | 3 years | Azure Blob Storage (immutable policy) |
| Secret rotation records (change tickets) | 3 years | ITSM system |
| Incident reports | 5 years | Secure document storage |

Ensure the Log Analytics workspace retention is configured to at least 365 days:

```bash
az monitor log-analytics workspace update \
  --workspace-name "<workspace-name>" \
  --resource-group "<resource-group>" \
  --retention-time 365
```

---

## Appendix A: Quick Reference

| Task | Section | Estimated Duration |
|---|---|---|
| Rotate an application secret | 3 | 20-40 minutes |
| Rotate a storage account key | 4 | 15-30 minutes |
| Rotate a service principal secret | 5 | 30-45 minutes |
| Renew a certificate | 6 | 45-90 minutes |
| Respond to a compromised secret | 9 | 15 minutes to revoke, 1-2 hours to fully remediate |

## Appendix B: Role Requirements Summary

| Operation | Required Azure RBAC Role | Required Entra ID Role |
|---|---|---|
| Read a secret value | Key Vault Secrets User | — |
| Create / update a secret | Key Vault Secrets Officer | — |
| Disable a secret version | Key Vault Secrets Officer | — |
| Delete a secret | Key Vault Secrets Officer | — |
| Purge a deleted secret | Key Vault Administrator | — |
| Manage Key Vault RBAC | Owner or User Access Administrator | — |
| Create SP client secret | — | Application Administrator |
| Delete SP client secret | — | Application Administrator |
| Add federated credential | — | Application Administrator |

All elevated roles must be activated via PIM with a justified reason referencing the change ticket, scoped to the minimum required resource, for a maximum duration of 4 hours.

## Appendix C: Related Documents

- `docs/runbooks/` — Additional operational runbooks
- `docs/adr/` — Architecture Decision Records (RBAC model selection, network ACL design)
- `modules/key-vault/main.tf` — Key Vault Terraform module
- `modules/key-vault/variables.tf` — Key Vault module input variables
- Azure Key Vault best practices: https://learn.microsoft.com/azure/key-vault/general/best-practices
- Azure Key Vault secret rotation documentation: https://learn.microsoft.com/azure/key-vault/secrets/tutorial-rotation
