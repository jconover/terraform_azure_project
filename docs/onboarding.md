# Onboarding Guide — Terraform Azure Infrastructure Platform

Welcome to the team. This guide walks you through everything you need to be productive on this project: tooling setup, repository layout, day-one tasks, the development workflow, module conventions, how changes reach production, and a glossary of project-specific terms.

Read this document top to bottom on your first day, then keep it as a reference.

---

## Table of Contents

1. [Prerequisites and Tooling Setup](#1-prerequisites-and-tooling-setup)
2. [Repository Structure Walkthrough](#2-repository-structure-walkthrough)
3. [First-Day Tasks](#3-first-day-tasks)
4. [Development Workflow](#4-development-workflow)
5. [Module Conventions](#5-module-conventions)
6. [Environment Promotion Flow](#6-environment-promotion-flow)
7. [Key Contacts and Escalation Paths](#7-key-contacts-and-escalation-paths)
8. [Glossary](#8-glossary)

---

## 1. Prerequisites and Tooling Setup

### 1.1 Required Tool Versions

| Tool | Minimum Version | Purpose |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.6.0 | Infrastructure as Code engine |
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) | >= 2.60.0 | Azure authentication and imperative operations |
| [TFLint](https://github.com/terraform-linters/tflint) | >= 0.50.0 | Terraform linter with AzureRM ruleset |
| [terraform-docs](https://terraform-docs.io/user-guide/installation/) | >= 0.18.0 | Auto-generates module README files |
| [pre-commit](https://pre-commit.com/#install) | latest | Runs fmt, validate, lint, and docs checks before every commit |
| [Infracost](https://www.infracost.io/docs/) | latest | Cost estimation via `make cost` (optional for local use) |

### 1.2 Installing the Tools

**Terraform** (via tfenv is recommended for version management):

```bash
# Using tfenv
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
tfenv install 1.6.0
tfenv use 1.6.0
terraform version
```

**Azure CLI**:

```bash
# Linux / WSL
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az version
```

**TFLint**:

```bash
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
tflint --version
```

**terraform-docs**:

```bash
curl -sSLo terraform-docs.tar.gz \
  https://terraform-docs.io/dl/v0.18.0/terraform-docs-v0.18.0-linux-amd64.tar.gz
tar -xzf terraform-docs.tar.gz terraform-docs
chmod +x terraform-docs && sudo mv terraform-docs /usr/local/bin/
terraform-docs --version
```

**pre-commit**:

```bash
pip install pre-commit
# After cloning the repo:
pre-commit install
```

### 1.3 Azure Access

You need Contributor access (or a custom role scoped to your team's subscription) to run `plan` and `apply` locally against dev. Request access through your manager before proceeding.

Verify your access:

```bash
az login
az account show
az account list --output table   # confirm the correct subscription is active
az account set --subscription <subscription-id>
```

### 1.4 TFLint Plugin Setup

The repository ships a `.tflint.hcl` at the root. The first time you run `tflint`, it needs to download the AzureRM ruleset plugin:

```bash
tflint --init
```

This installs `tflint-ruleset-azurerm` v0.27.0 locally. Subsequent runs use the cached plugin.

### 1.5 Pre-commit Hooks

After cloning, install the hooks once:

```bash
pre-commit install
```

The following checks run automatically on every `git commit`:

| Hook | What it checks |
|---|---|
| `terraform_fmt` | Code formatting (`terraform fmt`) |
| `terraform_validate` | Configuration validity (`terraform validate`) |
| `terraform_tflint` | Lint rules (AzureRM ruleset + recommended Terraform rules) |
| `terraform_docs` | terraform-docs output matches the committed README |
| `trailing-whitespace` | No trailing whitespace |
| `end-of-file-fixer` | Files end with a newline |
| `check-merge-conflict` | No unresolved merge conflict markers |
| `detect-private-key` | No accidentally committed private keys |

To run all hooks manually without committing:

```bash
pre-commit run --all-files
```

---

## 2. Repository Structure Walkthrough

```
terraform_azure_project/
├── modules/              # Reusable, independently testable Terraform modules
│   ├── naming/           # Resource name generation (use this in every environment)
│   ├── resource-group/
│   ├── virtual-network/
│   ├── subnet/
│   ├── network-security-group/
│   ├── private-endpoint/
│   ├── key-vault/
│   ├── log-analytics/
│   ├── managed-identity/
│   ├── rbac-assignment/
│   ├── azure-policy/
│   ├── storage-account/
│   ├── aks-cluster/
│   └── fabric-capacity/
├── environments/         # Root Terraform configurations, one directory per environment
│   └── dev/
│       ├── main.tf       # Module calls for this environment
│       ├── providers.tf  # Provider and Terraform version constraints
│       ├── backend.tf    # Remote state backend configuration
│       ├── variables.tf  # Input variable declarations
│       ├── outputs.tf    # Environment-level outputs
│       └── dev.tfvars    # Variable values for dev (committed; no secrets)
├── tests/                # Terraform native tests (.tftest.hcl files)
│   ├── modules/          # Per-module unit tests
│   └── integration/      # Cross-module integration tests
├── pipelines/            # Azure DevOps YAML pipeline definitions
│   ├── module-ci.yml     # PR validation: fmt, validate, lint, test, docs-check
│   ├── environment-cd.yml # Deployment: dev (auto) -> staging (1-approver) -> prod (2-approver)
│   ├── drift-check.yml   # Scheduled daily drift detection across all environments
│   └── templates/        # Reusable pipeline step templates
├── policies/             # Azure Policy definitions and assignment configurations
├── scripts/              # Operational helper scripts
│   ├── bootstrap-state-backend.sh  # One-time state backend provisioning
│   ├── generate-docs.sh            # Wrapper for terraform-docs
│   └── import-helper.sh            # Assists with importing existing resources
├── migration/            # Bicep-to-Terraform migration artifacts
│   ├── MIGRATION-PLAN.md
│   ├── bicep-source/     # Original Bicep templates being migrated
│   ├── examples/         # Example import configurations
│   └── mappings/         # Bicep-to-Terraform resource type mappings
└── docs/
    ├── adr/              # Architecture Decision Records (ADR-001 through ADR-007)
    ├── diagrams/         # Architecture diagrams
    ├── runbooks/         # Operational runbooks (state recovery, incident response)
    └── onboarding.md     # This file
```

### 2.1 Key File Relationships

- Every environment's `main.tf` calls modules from `../../modules/`. Modules are never called directly from another module in this project — only from environment root configurations.
- The `naming` module is instantiated first in every environment and its outputs feed the `name` arguments of all other module calls. Never hard-code resource names.
- `dev.tfvars` (and the equivalent per-environment `.tfvars` files) contain variable values. They are committed to source control. They must never contain secrets — use Key Vault references instead.
- The `backend.tf` in each environment specifies which blob key holds that environment's state file (`dev.terraform.tfstate`, `staging.terraform.tfstate`, `prod.terraform.tfstate`).

### 2.2 Architecture Decision Records

The `docs/adr/` directory contains the rationale behind every major technical decision. Read these before proposing changes to foundational choices. Current ADRs:

| ADR | Decision |
|---|---|
| ADR-001 | Use AzureRM Provider ~> 4.0 (not 3.x) |
| ADR-002 | Monorepo structure |
| ADR-003 | Per-environment state in Azure Blob Storage |
| ADR-004 | Custom naming module with structured convention |
| ADR-005 | Microsoft Fabric scope and capacity sizing |
| ADR-006 | OIDC / Workload Identity Federation for CI/CD auth |
| ADR-007 | AKS feature profile and CNI configuration |

---

## 3. First-Day Tasks

Work through these steps in order. Each step depends on the previous one completing successfully.

### Step 1 — Clone the Repository

```bash
git clone <repo-url>
cd terraform_azure_project
```

Install pre-commit hooks immediately after cloning:

```bash
pre-commit install
tflint --init    # downloads the AzureRM TFLint plugin
```

### Step 2 — Authenticate to Azure

```bash
az login
az account list --output table
az account set --subscription <your-dev-subscription-id>
az account show   # confirm the correct subscription
```

### Step 3 — Bootstrap the State Backend (first-time only)

The remote state backend is a Storage Account that must exist before `terraform init` can run. If it does not yet exist in your subscription, run the bootstrap script:

```bash
bash scripts/bootstrap-state-backend.sh \
  --subscription <your-dev-subscription-id> \
  --project platform \
  --location eastus2
```

The script creates:
- Resource group `rg-terraform-state`
- Storage Account `stterraform<hash>` (name derived from subscription ID hash)
- Blob container `tfstate`
- A `CanNotDelete` resource lock protecting the state backend

Or via Make:

```bash
make bootstrap
```

If the state backend already exists in the team's subscription, skip this step — the bootstrap script is idempotent and will report existing resources without recreating them.

### Step 4 — Configure Your Environment Variables

Open `environments/dev/dev.tfvars` and set your subscription ID:

```hcl
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # your real subscription ID
project         = "platform"
environment     = "dev"
location        = "eastus2"
owner           = "platform-team"
cost_center     = "infrastructure"
```

The `subscription_id` is the only value you need to change. All other defaults are correct for dev.

### Step 5 — Initialize Terraform

```bash
make init ENV=dev
# Equivalent to: cd environments/dev && terraform init
```

A successful init ends with:
```
Terraform has been successfully initialized!
```

### Step 6 — Run Your First Plan

```bash
make plan ENV=dev
# Equivalent to: cd environments/dev && terraform plan -var-file=dev.tfvars -out=tfplan
```

Review the plan output. At this stage the environment only instantiates the `naming` module, so you should see zero infrastructure changes. This confirms your authentication and backend connectivity are working.

### Step 7 — Run the Full Validation Suite

```bash
make all
# Runs: fmt, lint, validate, test
```

All checks should pass on a clean checkout. If any fail, check that your tool versions meet the minimums in section 1.1.

---

## 4. Development Workflow

### 4.1 Branch Strategy

All work happens on feature branches. The `main` branch is protected — direct pushes are blocked.

```bash
git checkout -b feat/your-feature-name   # new feature
git checkout -b fix/issue-description    # bug fix
git checkout -b chore/task-description   # maintenance (docs, refactor, tooling)
```

Branch naming convention: `<type>/<short-description-in-kebab-case>`

### 4.2 Making Changes

**For module changes** (most common):

1. Edit files under `modules/<module-name>/`
2. Run format and lint checks:
   ```bash
   make fmt
   make lint
   make validate ENV=dev
   ```
3. Run module tests:
   ```bash
   make test-module MODULE=<module-name>
   # e.g.: make test-module MODULE=key-vault
   ```
4. If you changed variable or output signatures, regenerate the README:
   ```bash
   make docs
   ```
5. Commit — pre-commit hooks run automatically and will catch any remaining issues.

**For environment changes** (less common; needs careful review):

1. Edit files under `environments/<env>/`
2. Run validate and plan:
   ```bash
   make validate ENV=dev
   make plan ENV=dev
   ```
3. Review the plan output thoroughly before committing.

### 4.3 Local Validation Targets

| Command | What it does |
|---|---|
| `make fmt` | Runs `terraform fmt -recursive` across the entire repo |
| `make lint` | Runs `tflint --recursive` with the AzureRM ruleset |
| `make validate ENV=dev` | Runs `terraform validate` in `environments/dev/` |
| `make test` | Runs all `.tftest.hcl` files in `tests/` |
| `make test-module MODULE=<name>` | Runs tests for a single named module |
| `make docs` | Regenerates all module `README.md` files via terraform-docs |
| `make all` | Runs fmt + lint + validate + test in sequence |
| `make drift ENV=dev` | Checks for infrastructure drift against the live environment |
| `make cost ENV=dev` | Produces an Infracost estimate for the dev environment |
| `make clean` | Removes `.terraform/` directories and cached plan files |

### 4.4 Raising a Pull Request

Before opening a PR:

```bash
make all              # must pass with zero errors
make plan ENV=dev     # review and confirm the plan is intentional
git push origin feat/your-feature-name
```

PR checklist (also enforced by the Module CI pipeline):

- [ ] `terraform fmt` passes (no formatting diff)
- [ ] `terraform validate` passes for all touched environments
- [ ] `tflint` passes with zero warnings or errors
- [ ] Module tests pass (`make test-module MODULE=<name>`)
- [ ] `terraform-docs` README is up to date (`make docs`)
- [ ] Plan output reviewed and pasted or linked in the PR description
- [ ] No secrets or subscription IDs committed (use placeholder `00000000-...` in examples)

### 4.5 What Happens After Merge

When your PR merges to `main`:

1. The **Module CI** pipeline re-runs as a post-merge validation gate.
2. The **Environment CD** pipeline triggers automatically:
   - Dev: plan + auto-apply (no manual gate)
   - Staging: plan + manual approval required before apply
   - Prod: plan + 2-approver gate before apply

Monitor the pipeline run in Azure DevOps after your merge.

---

## 5. Module Conventions

All modules in `modules/` follow the same layout and coding conventions. Consistency is enforced by pre-commit hooks and the CI pipeline's docs-check stage.

### 5.1 Standard File Layout

Every module must contain exactly these files:

```
modules/<module-name>/
├── main.tf        # Resource definitions only — no variables, no outputs
├── variables.tf   # All input variable declarations
├── outputs.tf     # All output declarations
├── versions.tf    # terraform{} block with required_version and required_providers
├── README.md      # Auto-generated by terraform-docs (do not edit manually)
└── examples/
    └── basic/
        └── main.tf    # Minimal working example of the module
```

Optional additional files when complexity warrants it:
- `locals.tf` — complex local value computations
- `data.tf` — data source lookups
- `<logical-group>.tf` — for large modules, split resources by logical grouping

### 5.2 versions.tf

Every module declares its own provider requirements:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
```

Do not pin to a specific patch version — use `~>` to allow patch updates within the minor version.

### 5.3 variables.tf Conventions

- Every variable must have a `description`.
- Every variable must have an explicit `type`.
- Use `validation` blocks to enforce allowed values at plan time rather than letting invalid input reach the Azure API.
- Prefer `default = null` over omitting a default when a value is optional but typed.
- Never use `sensitive = true` as a substitute for proper secret management — all secrets come from Key Vault.

Example of a well-formed variable:

```hcl
variable "sku_name" {
  description = "SKU name for the Key Vault (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU name must be one of: standard, premium."
  }
}
```

### 5.4 outputs.tf Conventions

- Every output must have a `description`.
- Outputs should expose the resource `id` and `name` at minimum.
- For resources with connection strings or URIs, expose those too.
- Never expose secrets as outputs.

Example:

```hcl
output "id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.this.name
}

output "uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}
```

### 5.5 Resource Naming Inside Modules

Modules receive a pre-computed `name` variable generated by the `naming` module. Do not construct names inside a module. The calling environment is responsible for generating names and passing them in.

```hcl
# In environments/dev/main.tf
module "naming" {
  source      = "../../modules/naming"
  project     = var.project
  environment = var.environment
  location    = var.location
  unique_seed = var.subscription_id
}

module "key_vault" {
  source              = "../../modules/key-vault"
  name                = module.naming.key_vault   # name comes from naming module
  resource_group_name = module.resource_group.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.common_tags
}
```

### 5.6 Naming Pattern

The naming module produces names following this pattern:

```
{project}-{environment}-{location_short}-{resource_abbreviation}[-{suffix}]
```

Examples for `project=platform`, `environment=dev`, `location=eastus2`:

| Resource type | Generated name |
|---|---|
| Resource Group | `platform-dev-eus2-rg` |
| Virtual Network | `platform-dev-eus2-vnet` |
| Subnet | `platform-dev-eus2-snet` |
| NSG | `platform-dev-eus2-nsg` |
| Key Vault | `platform-dev-eus2-kv` (max 24 chars) |
| Storage Account | `platformdeveus2st<hash>` (no hyphens, max 24 chars) |
| AKS Cluster | `platform-dev-eus2-aks` |
| Log Analytics | `platform-dev-eus2-law` |
| Managed Identity | `platform-dev-eus2-id` |

Storage accounts and Key Vaults receive special handling due to Azure character and length restrictions. The naming module handles this automatically.

### 5.7 Tagging Convention

All resources receive a standard set of tags via the `common_tags` local in each environment's `main.tf`:

```hcl
locals {
  common_tags = merge(
    {
      environment = var.environment
      project     = var.project
      managed_by  = "terraform"
      owner       = var.owner
      cost_center = var.cost_center
    },
    var.tags
  )
}
```

Pass `tags = local.common_tags` to every module call. Azure Policy enforces that `environment`, `project`, and `managed_by` tags are present on all resources.

### 5.8 Diagnostics Convention

Every module that manages a resource capable of emitting diagnostics accepts an optional `log_analytics_workspace_id` variable. When non-empty, the module creates an `azurerm_monitor_diagnostic_setting` resource pointed at the workspace. This pattern ensures observability by default without making Log Analytics a hard dependency.

```hcl
variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings. Leave empty to disable diagnostics."
  type        = string
  default     = ""
}
```

### 5.9 Resource Identifier Convention

Inside `main.tf`, name the primary resource `this` when the module manages a single instance of that resource type. This keeps `resource.type.this.id` consistent across all modules:

```hcl
resource "azurerm_key_vault" "this" {
  # ...
}
```

Use descriptive names only when a module manages multiple resources of the same type (e.g., `azurerm_subnet.aks` and `azurerm_subnet.services`).

### 5.10 Writing Module Tests

Tests live under `modules/<name>/` alongside the module code, using Terraform's native test framework (`.tftest.hcl` files). Each test file uses `mock_provider` blocks to avoid requiring real Azure credentials in unit tests.

Run a single module's tests:

```bash
make test-module MODULE=naming
```

Run all tests across the repo:

```bash
make test
```

### 5.11 Updating Module Documentation

Module `README.md` files are auto-generated. Never edit them directly — your changes will be overwritten. To regenerate after changing variables or outputs:

```bash
make docs
# or for a single module:
terraform-docs markdown table --output-file README.md --output-mode inject modules/<name>/
```

The CI pipeline's `DocsCheck` stage verifies that committed READMEs match what `terraform-docs` would generate, causing the build to fail on stale documentation.

---

## 6. Environment Promotion Flow

### 6.1 Overview

Changes flow through environments in strict order. No environment can be skipped.

```
Feature Branch
     |
     v
Pull Request --> Module CI (fmt, validate, lint, test, docs-check)
     |
     v (merge to main)
     |
     v
Dev  --> auto-plan --> auto-apply
     |
     v (dev apply successful)
     |
     v
Staging --> plan --> [manual approval: 1 approver] --> apply
     |
     v (staging apply successful)
     |
     v
Prod --> plan --> [manual approval: 2 approvers] --> apply
```

### 6.2 Environment Descriptions

| Environment | Purpose | Apply Gate | State File |
|---|---|---|---|
| dev | Integration testing, feature validation | Automatic on merge | `dev.terraform.tfstate` |
| staging | Pre-production validation, load testing | 1 approver in Azure DevOps | `staging.terraform.tfstate` |
| prod | Live production workloads | 2 approvers in Azure DevOps | `prod.terraform.tfstate` |

### 6.3 CI/CD Pipeline Details

**Module CI** (`pipelines/module-ci.yml`) — triggers on PRs touching `modules/**`:
- Stage 1 `Validate`: `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`, `tflint` for every module
- Stage 2 `Test`: `terraform test` for modules with `.tftest.hcl` files
- Stage 3 `DocsCheck`: Verifies committed README matches `terraform-docs` output

**Environment CD** (`pipelines/environment-cd.yml`) — triggers on merges to `main` touching `environments/**` or `modules/**`:
- Each environment runs in a separate stage using the `AzureCLI@2` task with `useWorkloadIdentityFederation: true`
- No secrets are stored in Azure DevOps — OIDC tokens are issued at runtime
- Plan artifacts are published and consumed by the apply job to guarantee plan-apply consistency
- The service connection name is `azure-terraform-oidc`

**Drift Detection** (`pipelines/drift-check.yml`) — scheduled daily at 06:00 UTC:
- Runs `terraform plan -detailed-exitcode` against all three environments simultaneously (parallel stages)
- Exit code 2 means drift detected; the pipeline reports it without applying changes
- Alerts the team to manual changes made outside Terraform

### 6.4 Running Environment Operations Locally

Local operations against dev are permitted for troubleshooting. Staging and prod should only be modified through the CD pipeline.

```bash
# Initialize (required once, or after provider/backend changes)
make init ENV=dev

# Plan — always review before applying
make plan ENV=dev

# Apply — only after reviewing the saved plan
make apply ENV=dev

# Check for drift without applying
make drift ENV=dev

# Estimate costs
make cost ENV=dev

# Destroy (dev only — never run against staging or prod locally)
make destroy ENV=dev
```

### 6.5 State Backend

State is stored in Azure Blob Storage using blob lease locking to prevent concurrent modifications. Key properties:

- **Soft delete**: 30-day retention — accidental deletions are recoverable
- **Versioning**: enabled — every state write creates a new version
- **Resource lock**: `CanNotDelete` on the state resource group — prevents accidental destruction of the backend
- **Authentication**: OIDC in CI/CD; `az login` (interactive) locally
- **Cross-environment access**: Use `data` sources to look up resources from another environment. Do not use `terraform_remote_state` — it creates tight coupling between environments.

For state recovery procedures, see `docs/runbooks/state-recovery.md`.

### 6.6 Provider Authentication

The AzureRM provider authenticates via:

- **Locally**: Azure CLI credentials (`az login`) — the provider picks these up automatically
- **CI/CD**: Workload Identity Federation (OIDC) — the pipeline sets `ARM_USE_OIDC=true`, `ARM_CLIENT_ID`, and `ARM_TENANT_ID` from the service connection. No client secrets are stored anywhere.

If you see authentication errors locally, confirm you are logged in to the correct subscription:

```bash
az account show
az account set --subscription <subscription-id>
```

---

## 7. Key Contacts and Escalation Paths

> The following sections are placeholders. Update these with real names, handles, and links before distributing this guide.

### 7.1 Team Contacts

| Role | Name | Contact |
|---|---|---|
| Platform Lead | `<Platform Lead Name>` | `<email / Teams handle>` |
| Senior Infrastructure Engineer | `<Name>` | `<email / Teams handle>` |
| Azure DevOps / Pipeline Owner | `<Name>` | `<email / Teams handle>` |
| Security / RBAC Owner | `<Name>` | `<email / Teams handle>` |

### 7.2 Communication Channels

| Channel | Purpose |
|---|---|
| `<#team-channel>` | Day-to-day discussion, questions |
| `<#incidents>` | Production incidents and alerts |
| `<#terraform-prs>` | PR notifications and review requests |
| Weekly sync | `<day/time>` — sprint review and planning |

### 7.3 Escalation Path

1. **Blocked on code / design question**: Post in `<#team-channel>` or ask the Platform Lead directly.
2. **Azure permission issue**: Raise a request with `<Security / RBAC Owner>`. Include the subscription, required role, and justification.
3. **CI/CD pipeline failure**: Check the Azure DevOps run log first. If the issue is with the service connection or OIDC configuration, contact the Pipeline Owner.
4. **Production incident**: Post in `<#incidents>` immediately, then follow `docs/runbooks/incident-response.md`.
5. **State file corruption or lock**: Do not attempt manual state operations without guidance. Contact the Platform Lead and refer to `docs/runbooks/state-recovery.md`.

### 7.4 Access Requests

| System | How to request access |
|---|---|
| Azure Subscription (dev) | `<link to access request process>` |
| Azure Subscription (staging/prod) | `<link — read-only by default; write requires approval>` |
| Azure DevOps | `<link to org / project>` |
| Key Vault (dev secrets) | `<process>` |

---

## 8. Glossary

The following terms have specific meanings within this project. Some differ slightly from their generic industry definitions.

**AzureRM Provider 4.x**
The Terraform provider for Azure Resource Manager, pinned to `~> 4.0`. This project deliberately targets 4.x rather than 3.x for consistent argument naming (`*_enabled` convention) and support for newer Azure services. See ADR-001.

**Backend**
The Azure Blob Storage account that holds Terraform state files. Each environment has its own state blob (`dev.terraform.tfstate`, `staging.terraform.tfstate`, `prod.terraform.tfstate`). The backend is bootstrapped outside of Terraform using `scripts/bootstrap-state-backend.sh` to avoid the chicken-and-egg problem of needing state to manage the state backend.

**Bootstrap**
The one-time process of creating the Terraform state backend infrastructure (resource group, storage account, container, lock) using the Azure CLI directly. Run `make bootstrap` or `bash scripts/bootstrap-state-backend.sh`. Idempotent — safe to re-run.

**CAF (Cloud Adoption Framework)**
Microsoft's set of Azure best practices and naming conventions. The project's resource abbreviations are aligned to CAF (e.g., `rg` for resource groups, `vnet` for virtual networks, `kv` for Key Vaults). See ADR-004.

**Common Tags**
The standard set of tags applied to every resource: `environment`, `project`, `managed_by`, `owner`, `cost_center`. Defined as a `locals` block in each environment's `main.tf` and enforced by Azure Policy.

**Drift**
A difference between the actual state of Azure resources and the Terraform state file (or configuration). Drift occurs when someone makes a manual change in the Azure portal or via CLI outside of Terraform. The drift-check pipeline runs daily at 06:00 UTC to detect it. Resolve drift by either importing the change into Terraform or reverting the manual change.

**Environment**
One of `dev`, `staging`, or `prod`. Each environment is a separate Terraform root configuration under `environments/<env>/` with its own state file, `.tfvars` file, and Azure subscription (or resource group scope). Environments are promoted in order: dev first, then staging, then prod.

**Fabric Capacity**
A Microsoft Fabric compute capacity resource managed by the `fabric-capacity` module. Fabric is Microsoft's unified analytics platform. The project automates capacity provisioning and scaling.

**Immutable Infrastructure**
The design principle that running infrastructure is never modified directly — all changes are applied through Terraform and CI/CD. Manual portal edits are prohibited and detected as drift.

**Module**
A reusable, independently testable unit of Terraform configuration that manages a single Azure resource type or a tightly related group of resources. All modules live under `modules/` and follow the standard file layout (section 5.1). Modules are versioned implicitly by the repository; there is no separate module registry.

**Naming Module**
The `modules/naming/` module. It is the single source of truth for resource names. It takes `project`, `environment`, `location`, and optional `suffix`/`unique_seed` inputs and produces standardized names for all resource types. Every environment must instantiate this module first and pass its outputs to all other module calls.

**OIDC / Workload Identity Federation (WIF)**
The authentication method used by the CI/CD pipelines. Instead of storing a service principal client secret in Azure DevOps, the pipeline exchanges a short-lived OIDC token (issued by Azure DevOps) for an Azure access token at runtime. No credentials are stored. See ADR-006.

**Plan Artifact**
The binary `tfplan` file produced by `terraform plan -out=tfplan`. In the CD pipeline, the plan is produced by the `Plan` job, published as a pipeline artifact, then consumed by the `Apply` job. This guarantees that exactly the reviewed plan is applied — the apply step cannot introduce additional changes.

**Pre-commit**
The pre-commit framework configured via `.pre-commit-config.yaml`. It runs a set of hooks before every `git commit`. Hooks include `terraform_fmt`, `terraform_validate`, `terraform_tflint`, and `terraform_docs`. Install with `pre-commit install` after cloning.

**Root Configuration**
A Terraform configuration that has a `backend.tf` and is initialized with `terraform init`. In this project, root configurations live under `environments/<env>/`. Modules under `modules/` are not root configurations — they have no backend and are always called from a root configuration.

**State File**
The JSON file (`*.terraform.tfstate`) that Terraform uses to map configuration resources to real Azure resources. It is stored in Azure Blob Storage. Never edit the state file manually. Use `terraform state` subcommands (`list`, `mv`, `rm`, `import`) for state operations, and always consult the Platform Lead before doing so.

**State Lock**
A lease held on the state blob during `terraform plan` and `terraform apply` operations to prevent concurrent modifications from multiple operators or pipeline runs. If a lock is stuck (e.g., a pipeline was killed mid-run), it can be broken with `terraform force-unlock <lock-id>` — but only after confirming no other operation is actually in progress.

**TFLint**
A Terraform linter configured via `.tflint.hcl`. This project uses the `tflint-ruleset-azurerm` plugin (v0.27.0) in addition to the built-in `terraform` ruleset. Rules enforced include: resource argument validation against the AzureRM schema, snake_case naming for all identifiers, documented variables and outputs, and typed variables.

**terraform-docs**
A tool that generates Markdown documentation from Terraform variable and output definitions. Module `README.md` files are generated by terraform-docs and must not be edited by hand. Run `make docs` to regenerate all READMEs. The CI pipeline fails if committed READMEs are stale.

**tfvars File**
A `.tfvars` file (e.g., `dev.tfvars`) that supplies values for Terraform input variables. One file per environment, committed to source control. Must not contain secrets. Passed to Terraform via `-var-file=dev.tfvars`.

**Unique Seed**
The `unique_seed` input to the naming module. Set to the Azure subscription ID. Used to generate a deterministic 6-character hash that makes storage account names globally unique across subscriptions while remaining stable across plan/apply cycles.

---

*Last updated: 2026-03-03. To propose corrections or additions, open a PR against this file.*
