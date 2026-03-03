# Terraform Azure Infrastructure Platform

A production-grade, Terraform-first Azure infrastructure platform demonstrating enterprise-scale patterns for automated provisioning and lifecycle management of Azure services.

## Overview

This project provides a comprehensive module library and operational framework for managing Azure infrastructure using Terraform. It covers:

- **13+ reusable Terraform modules** for core Azure services
- **Production-grade CI/CD** pipelines for Azure DevOps
- **RBAC and access governance** as code
- **AKS and Storage** reference implementations
- **Microsoft Fabric** automation
- **Bicep-to-Terraform** migration strategy and tooling

## Architecture

| Layer | Components |
|-------|-----------|
| Foundation | Naming, Resource Groups, VNet, Subnets, NSGs, Key Vault, Log Analytics |
| Identity | Managed Identities, RBAC Assignments, Custom Roles |
| Compute | AKS Clusters (managed identity, autoscaling, CNI Overlay) |
| Data | Storage Accounts (private endpoints, lifecycle, CMK) |
| Analytics | Microsoft Fabric Capacity |
| Governance | Azure Policy, Tagging, Naming Standards |

## Quick Start

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.60.0
- [TFLint](https://github.com/terraform-linters/tflint) >= 0.50.0
- Azure subscription with Contributor access

### Getting Started

```bash
# 1. Clone
git clone <repo-url> && cd terraform_azure_project

# 2. Authenticate
az login
az account set --subscription <subscription-id>

# 3. Bootstrap state backend (one-time)
make bootstrap

# 4. Configure environment
vi environments/dev/dev.tfvars  # Set your subscription_id

# 5. Initialize and plan
make init ENV=dev
make plan ENV=dev
```

## Repository Structure

```
terraform_azure_project/
├── modules/           # Reusable Terraform modules
├── environments/      # Root configs per environment (dev/staging/prod)
├── tests/             # Automated terraform tests
├── policies/          # Azure Policy definitions and assignments
├── pipelines/         # Azure DevOps pipeline definitions
├── scripts/           # Helper scripts (bootstrap, docs, import)
├── migration/         # Bicep-to-Terraform migration artifacts
└── docs/              # Documentation, ADRs, runbooks
```

## Modules

| Module | Description | Status |
|--------|-------------|--------|
| `naming` | Azure-compliant resource name generation | Available |
| `resource-group` | Resource group with standard tags | Planned |
| `virtual-network` | VNet with configurable address space | Planned |
| `subnet` | Subnets with delegation and service endpoints | Planned |
| `network-security-group` | NSG with configurable rules | Planned |
| `private-endpoint` | Generic private endpoint with DNS | Planned |
| `key-vault` | Key Vault with RBAC mode | Planned |
| `log-analytics` | Log Analytics workspace | Planned |
| `managed-identity` | User/system-assigned managed identity | Planned |
| `rbac-assignment` | Role assignments with least-privilege | Planned |
| `storage-account` | Storage with private endpoints and lifecycle | Planned |
| `aks-cluster` | AKS with managed identity and autoscaling | Planned |
| `fabric-capacity` | Microsoft Fabric capacity provisioning | Planned |
| `azure-policy` | Policy definitions and assignments | Planned |

## CI/CD

Pipelines target **Azure DevOps** with workload identity federation (OIDC):

- **Module CI**: Validates modules on PR (fmt, validate, lint, test)
- **Environment CD**: Deploys on merge (plan -> approval -> apply)
- **Drift Detection**: Scheduled daily checks

## Key Design Decisions

See [Architecture Decision Records](docs/adr/) for detailed rationale:

- [ADR-001: AzureRM Provider 4.x](docs/adr/001-provider-version.md)
- [ADR-002: Monorepo Structure](docs/adr/002-repo-structure.md)
- [ADR-003: Per-Environment State](docs/adr/003-state-management.md)
- [ADR-004: Naming Convention](docs/adr/004-naming-convention.md)

## Make Targets

```
make help         # Show all targets
make all          # fmt + lint + validate + test
make plan ENV=dev # Plan changes for an environment
make apply ENV=dev
make drift ENV=dev
make docs         # Regenerate module READMEs
make cost ENV=dev # Infracost estimate
```

## Tech Stack

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.6.0 | Infrastructure as Code |
| AzureRM Provider | ~> 4.0 | Azure resource management |
| AzureAD Provider | ~> 3.0 | Entra ID integration |
| TFLint | >= 0.50.0 | Terraform linting |
| terraform-docs | >= 0.18.0 | Documentation generation |
| Azure DevOps | - | CI/CD pipelines |
