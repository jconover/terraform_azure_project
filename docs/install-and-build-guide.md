# Install & Build Guide

Step-by-step guide to building out the Azure infrastructure platform from scratch.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Tool Installation](#2-tool-installation)
3. [Azure Authentication](#3-azure-authentication)
4. [Repository Setup](#4-repository-setup)
5. [Bootstrap State Backend](#5-bootstrap-state-backend)
6. [Understanding the Architecture](#6-understanding-the-architecture)
7. [Deploy Dev Environment](#7-deploy-dev-environment)
8. [Verify Your Deployment](#8-verify-your-deployment)
9. [Day-to-Day Workflow](#9-day-to-day-workflow)
10. [Deploy Staging & Production](#10-deploy-staging--production)
11. [Teardown](#11-teardown)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

Before you start, you need:

- **An Azure subscription** with Owner or Contributor role
- **An Azure AD tenant** (comes with your subscription)
- **Git** installed
- **A terminal** (bash or zsh on macOS/Linux, WSL2 on Windows)

### Azure Permissions Required

| Action | Required Role |
|--------|--------------|
| Create resource groups, VNets, storage | **Contributor** on subscription |
| Create Key Vault with RBAC | **Contributor** + **Key Vault Administrator** |
| Create service principals (CI/CD) | **Application Administrator** in Azure AD |
| Assign RBAC roles | **User Access Administrator** on subscription |

---

## 2. Tool Installation

Install these tools in order. All versions are pinned for compatibility.

### 2.1 Terraform (1.6.0)

The project uses [tfenv](https://github.com/tfutils/tfenv) to manage Terraform versions.

```bash
# Install tfenv
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Install the pinned version (reads .terraform-version automatically)
cd /path/to/terraform_azure_project
tfenv install    # Installs 1.6.0
tfenv use 1.6.0

# Verify
terraform version
# Expected: Terraform v1.6.0
```

**Alternative (direct install):**
```bash
# macOS
brew tap hashicorp/tap && brew install hashicorp/tap/terraform@1.6.0

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip -d /usr/local/bin/
```

### 2.2 Azure CLI (2.60.0+)

```bash
# macOS
brew install azure-cli

# Linux (Ubuntu/Debian)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Windows (WSL2)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Verify
az --version
# Expected: azure-cli 2.60.0 or later
```

### 2.3 TFLint (0.50.0+)

```bash
# macOS
brew install tflint

# Linux
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# Verify
tflint --version
```

### 2.4 terraform-docs (0.18.0+)

```bash
# macOS
brew install terraform-docs

# Linux
curl -sSLo ./terraform-docs.tar.gz https://terraform-docs.io/dl/v0.18.0/terraform-docs-v0.18.0-$(uname)-amd64.tar.gz
tar -xzf terraform-docs.tar.gz
chmod +x terraform-docs
mv terraform-docs /usr/local/bin/

# Verify
terraform-docs --version
```

### 2.5 pre-commit

```bash
# macOS
brew install pre-commit

# Linux / pip
pip install pre-commit

# Verify
pre-commit --version
```

### 2.6 Infracost (optional — cost estimation)

```bash
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh

# Register for a free API key
infracost auth login

# Verify
infracost --version
```

### Quick Verification

Run this to confirm all tools are ready:

```bash
terraform version      # v1.6.0
az --version           # 2.60.0+
tflint --version       # 0.50.0+
terraform-docs version # 0.18.0+
pre-commit --version   # any recent
```

---

## 3. Azure Authentication

### 3.1 Login to Azure

```bash
# Interactive login (opens browser)
az login

# List your subscriptions
az account list --output table

# Set the subscription you want to use
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Verify
az account show --output table
```

### 3.2 Set Environment Variables (optional but recommended)

Terraform can authenticate via environment variables instead of relying on `az login`:

```bash
export ARM_SUBSCRIPTION_ID="your-subscription-id"
export ARM_TENANT_ID="your-tenant-id"

# If using a service principal (CI/CD):
export ARM_CLIENT_ID="your-client-id"
export ARM_CLIENT_SECRET="your-client-secret"
```

For local development, `az login` is sufficient. The provider reads your Azure CLI credentials automatically.

---

## 4. Repository Setup

```bash
# Clone the repo
git clone https://github.com/jconover/terraform_azure_project.git
cd terraform_azure_project

# Install pre-commit hooks (runs linting on every git commit)
pre-commit install

# Run all hooks once to verify your setup
pre-commit run --all-files

# Create your dev variable file
cp environments/dev/dev.tfvars.example environments/dev/dev.tfvars
```

### 4.1 Edit Your Variables

Open `environments/dev/dev.tfvars` and set your subscription ID:

```hcl
# environments/dev/dev.tfvars
subscription_id = "your-actual-subscription-id-here"
```

> **IMPORTANT**: `dev.tfvars` is gitignored (via `*.auto.tfvars` pattern). Never commit real subscription IDs.

---

## 5. Bootstrap State Backend

The state backend stores your Terraform state file remotely in Azure Blob Storage so your team can collaborate safely.

> **Note**: The dev environment currently uses a **local backend** (state stored on your machine). You can skip this step for solo dev work, but it's required for team collaboration and CI/CD.

### 5.1 Run Bootstrap

```bash
make bootstrap
```

This script (`scripts/bootstrap-state-backend.sh`) creates:

| Resource | Name | Purpose |
|----------|------|---------|
| Resource Group | `rg-terraform-state` | Holds the state storage account |
| Storage Account | `stterraform{hash}` | Stores `.tfstate` files |
| Blob Container | `tfstate` | Container for state files |
| Resource Lock | CanNotDelete | Prevents accidental deletion |

The storage account is hardened: soft-delete (30 days), versioning enabled, HTTPS-only, TLS 1.2.

### 5.2 Update Backend Config (optional)

After bootstrap, update `environments/dev/backend.tf` to use remote state:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformXXXXXX"  # from bootstrap output
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
    use_oidc             = true
  }
}
```

For local-only development, leave the default local backend as-is.

---

## 6. Understanding the Architecture

### What Gets Created

When you run `make apply ENV=dev`, Terraform reads `environments/dev/main.tf` and creates this infrastructure:

```
┌─────────────────────────────────────────────────────────┐
│  Azure Subscription                                     │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Resource Group: platform-dev-eus2-rg             │  │
│  │                                                   │  │
│  │  ┌─────────────────┐  ┌────────────────────────┐  │  │
│  │  │  Log Analytics   │  │  Key Vault             │  │  │
│  │  │  Workspace       │◄─┤  platform-dev-eus2-kv  │  │  │
│  │  │  (central logs)  │  │  (secrets, RBAC)       │  │  │
│  │  └────────┬─────────┘  └────────────────────────┘  │  │
│  │           │                                        │  │
│  │           │ diagnostics                            │  │
│  │           ▼                                        │  │
│  │  ┌─────────────────────────────────────────────┐   │  │
│  │  │  Virtual Network: platform-dev-eus2-vnet    │   │  │
│  │  │  Address Space: 10.0.0.0/16                 │   │  │
│  │  │                                             │   │  │
│  │  │  ┌───────────────────────────────────────┐  │   │  │
│  │  │  │  Subnet: platform-dev-eus2-snet       │  │   │  │
│  │  │  │  CIDR: 10.0.1.0/24                    │  │   │  │
│  │  │  │  NSG: platform-dev-eus2-nsg (attached) │  │   │  │
│  │  │  │  Endpoints: KeyVault, Storage          │  │   │  │
│  │  │  └───────────────────────────────────────┘  │   │  │
│  │  └─────────────────────────────────────────────┘   │  │
│  │                                                    │  │
│  │  ┌────────────────────────┐                        │  │
│  │  │  Storage Account       │                        │  │
│  │  │  platformdeveus2sta... │                        │  │
│  │  │  (Standard LRS)        │                        │  │
│  │  └────────────────────────┘                        │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### Module Dependency Chain

Modules are applied in this order (Terraform figures this out automatically):

```
naming (generates all resource names)
  └─► resource-group
        ├─► log-analytics
        ├─► virtual-network ──► subnet
        ├─► network-security-group ──► (attached to subnet)
        ├─► key-vault
        └─► storage-account
```

### File Map

```
environments/dev/
├── main.tf          ← Calls all modules, wires them together
├── variables.tf     ← Input variables (project, env, location, CIDRs)
├── dev.tfvars       ← Your variable values (gitignored)
├── providers.tf     ← AzureRM 4.0 + AzureAD 3.0 provider config
├── backend.tf       ← State storage config (local or Azure Blob)
└── outputs.tf       ← Resource IDs/names exported after apply

modules/
├── naming/          ← Generates standardized names (no resources created)
├── resource-group/  ← Azure Resource Group
├── log-analytics/   ← Log Analytics Workspace
├── virtual-network/ ← VNet + optional diagnostics
├── subnet/          ← Subnet + optional NSG association
├── network-security-group/ ← NSG with default deny-all-inbound
├── key-vault/       ← Key Vault with RBAC + optional diagnostics
├── storage-account/ ← Storage Account + containers + lifecycle rules
└── aks-cluster/     ← AKS (not used in dev yet)
```

---

## 7. Deploy Dev Environment

### Step 1: Initialize Terraform

```bash
make init ENV=dev
```

This downloads providers (AzureRM ~> 4.0, AzureAD ~> 3.0) and initializes the backend.

**Expected output**: `Terraform has been successfully initialized!`

### Step 2: Preview Changes

```bash
make plan ENV=dev
```

This generates an execution plan showing exactly what will be created. Review the output carefully.

**Expected output**: `Plan: 12 to add, 0 to change, 0 to destroy.` (approximate — includes resources + diagnostic settings)

The plan is saved to `environments/dev/tfplan`.

### Step 3: Apply

```bash
make apply ENV=dev
```

This creates all resources in Azure. It reads the saved `tfplan` file, so it applies exactly what you previewed.

**Expected output**: `Apply complete! Resources: 12 added, 0 changed, 0 destroyed.`

### Step 4: Check Outputs

After apply, Terraform prints your resource details:

```
Outputs:

key_vault = {
  id       = "/subscriptions/.../platform-dev-eus2-kv"
  name     = "platform-dev-eus2-kv"
  vault_uri = "https://platform-dev-eus2-kv.vault.azure.net/"
}

resource_group = {
  id       = "/subscriptions/.../platform-dev-eus2-rg"
  name     = "platform-dev-eus2-rg"
  location = "eastus2"
}
...
```

---

## 8. Verify Your Deployment

### In the Azure Portal

1. Go to [portal.azure.com](https://portal.azure.com)
2. Navigate to **Resource Groups**
3. Find `platform-dev-eus2-rg`
4. You should see all 7 resources listed

### Via Azure CLI

```bash
# List all resources in the resource group
az resource list --resource-group platform-dev-eus2-rg --output table

# Check Key Vault
az keyvault show --name platform-dev-eus2-kv --output table

# Check VNet
az network vnet show --name platform-dev-eus2-vnet \
  --resource-group platform-dev-eus2-rg --output table

# Check Storage Account
az storage account show --name platformdeveus2sta02cf2 --output table
```

### Via Terraform

```bash
# Show current state
cd environments/dev
terraform state list

# Show a specific resource
terraform state show module.foundation_kv.azurerm_key_vault.this
```

### Check for Drift

```bash
make drift ENV=dev
# Exit code 0 = no drift (everything matches)
# Exit code 2 = drift detected (something changed outside Terraform)
```

---

## 9. Day-to-Day Workflow

### Making Changes

```bash
# 1. Create a feature branch
git checkout -b feature/add-container-to-storage

# 2. Make your changes (edit .tf files)

# 3. Format and validate
make fmt
make validate ENV=dev

# 4. Preview
make plan ENV=dev

# 5. Apply (if plan looks good)
make apply ENV=dev

# 6. Run full pre-commit checks
make all

# 7. Commit and push
git add -A
git commit -m "feat(storage): add data container to storage account"
git push -u origin feature/add-container-to-storage

# 8. Create PR to main
```

### Useful Commands

| Command | What it does |
|---------|-------------|
| `make all` | Run fmt + lint + validate + test (do this before every PR) |
| `make plan ENV=dev` | Preview changes without applying |
| `make apply ENV=dev` | Apply the saved plan |
| `make drift ENV=dev` | Check if anything changed outside Terraform |
| `make cost ENV=dev` | Estimate monthly costs (requires Infracost) |
| `make test` | Run all Terraform native tests |
| `make test-module MODULE=naming` | Test a single module |
| `make docs` | Regenerate module READMEs |
| `make clean` | Remove .terraform dirs and plan files |

---

## 10. Deploy Staging & Production

Staging and production use the same modules with different variable values.

### Staging

```bash
# Copy and edit staging variables
cp environments/staging/staging.tfvars.example environments/staging/staging.tfvars
# Edit staging.tfvars with staging-appropriate values

make init ENV=staging
make plan ENV=staging
make apply ENV=staging
```

### Production

```bash
# Copy and edit prod variables
cp environments/prod/prod.tfvars.example environments/prod/prod.tfvars
# Edit prod.tfvars with production values

make init ENV=prod
make plan ENV=prod
make apply ENV=prod
```

### Environment Differences

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| Public network access | Enabled | Restricted | Disabled |
| Purge protection | Disabled | Enabled | Enabled |
| Soft delete retention | 7 days | 30 days | 90 days |
| Replication type | LRS | GRS | RAGRS |
| Network ACL default | Allow | Deny | Deny |
| Approval gates (CI/CD) | Auto | 1 approver | 2 approvers |

---

## 11. Teardown

To destroy all resources in an environment:

```bash
# DANGER: This deletes everything in the environment
make destroy ENV=dev
```

Terraform will show what will be destroyed and ask for confirmation. Type `yes` to proceed.

To remove local Terraform files without destroying infrastructure:

```bash
make clean
```

---

## 12. Troubleshooting

### "Error: building AzureRM Client"

**Cause**: Not logged in to Azure.
**Fix**: Run `az login` and `az account set --subscription YOUR_SUB_ID`

### "Error: Invalid count argument"

**Cause**: Using string comparison on values unknown at plan time.
**Fix**: Use `enable_diagnostics = true` boolean instead of checking workspace ID.

### "Error: Unsupported block type — mock_provider"

**Cause**: Test files use `mock_provider` which requires Terraform 1.7+.
**Fix**: Replace with `provider "azurerm" { features {} }` in test files.

### Pre-commit hooks fail

**Cause**: Missing tools or formatting issues.
**Fix**:
```bash
make fmt          # Fix formatting
make docs         # Regenerate READMEs
git add -u        # Re-stage auto-fixed files
git commit        # Retry
```

### "Error: Backend configuration changed"

**Cause**: Switched between local and remote backend.
**Fix**: Run `make init ENV=dev` to re-initialize. If migrating state, use `terraform init -migrate-state`.

### State is locked

**Cause**: A previous operation crashed or another user is running.
**Fix**:
```bash
# Check who holds the lock
terraform force-unlock LOCK_ID
```

---

## Quick Reference Card

```bash
# === FIRST TIME SETUP ===
az login
az account set --subscription "YOUR_SUB_ID"
cp environments/dev/dev.tfvars.example environments/dev/dev.tfvars
# Edit dev.tfvars with your subscription_id
pre-commit install
make init ENV=dev
make plan ENV=dev
make apply ENV=dev

# === DAILY WORKFLOW ===
git checkout -b feature/my-change
# ... make changes ...
make plan ENV=dev       # preview
make apply ENV=dev      # deploy
make all                # validate everything
git add && git commit && git push
# Create PR → merge → CI/CD handles staging/prod
```
