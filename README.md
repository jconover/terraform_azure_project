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
| `resource-group` | Resource group with standard tags | Available |
| `virtual-network` | VNet with configurable address space | Available |
| `subnet` | Subnets with delegation and service endpoints | Available |
| `network-security-group` | NSG with configurable rules | Available |
| `private-endpoint` | Generic private endpoint with DNS | Available |
| `key-vault` | Key Vault with RBAC mode | Available |
| `log-analytics` | Log Analytics workspace | Available |
| `managed-identity` | User/system-assigned managed identity | Available |
| `rbac-assignment` | Role assignments with least-privilege | Available |
| `storage-account` | Storage with private endpoints and lifecycle | Available |
| `aks-cluster` | AKS with managed identity and autoscaling | Available |
| `fabric-capacity` | Microsoft Fabric capacity provisioning | Available |
| `azure-policy` | Policy definitions and assignments | Available |

## CI/CD

Pipelines target **Azure DevOps** with workload identity federation (OIDC):

- **Module CI**: Validates modules on PR (fmt, validate, lint, test)
- **Environment CD**: Deploys on merge (plan -> approval -> apply)
- **Drift Detection**: Scheduled daily checks

## Documentation

| Document | Description |
|----------|-------------|
| [Onboarding Guide](docs/onboarding.md) | First-day setup, authentication, and first plan/apply walkthrough |
| [Contributing Guide](docs/contributing.md) | Branch strategy, PR checklist, coding standards, and review process |
| [Module Usage Guide](docs/module-usage-guide.md) | Practical examples consuming each module from environment roots |
| [Module Development Guide](docs/module-development.md) | Standards and patterns for authoring new modules |
| [CI/CD Guide](docs/ci-cd-guide.md) | Azure DevOps pipeline stages, OIDC setup, and approval gates |
| [Security Guide](docs/security-guide.md) | RBAC, Key Vault access, private endpoints, CMK, and policy guardrails |
| [Network Architecture](docs/network-architecture.md) | Reference topology: VNet, subnet, NSG, and private endpoint design |
| [Cost Management](docs/cost-management.md) | Infracost usage, tagging for cost allocation, and budget alerts |
| [Troubleshooting Guide](docs/troubleshooting.md) | Common errors, root causes, and remediation steps |
| [Migration Guide](docs/migration-guide.md) | Migrating existing Bicep deployments to Terraform modules |
| [Runbook: AKS Scaling](docs/runbooks/aks-scaling.md) | Scale AKS node pools, drain/cordon procedures |
| [Runbook: State Recovery](docs/runbooks/state-recovery.md) | Recover from corrupted or lost Terraform remote state |
| [Runbook: Drift Remediation](docs/runbooks/drift-remediation.md) | Investigate and resolve configuration drift |
| [Runbook: Secret Rotation](docs/runbooks/secret-rotation.md) | Rotate Key Vault secrets and credentials with zero downtime |
| [Runbook: Disaster Recovery](docs/runbooks/disaster-recovery.md) | Region failover, state restoration, and environment re-provisioning |

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
