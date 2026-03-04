# Changelog

All notable changes to the Terraform Azure Infrastructure Platform are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

---

## Phase 8 — Documentation, Runbooks, and Final Polish

### Added
- `docs/onboarding.md` — step-by-step guide for engineers joining the project, covering prerequisites, authentication, first plan/apply, and troubleshooting tips.
- `docs/contributing.md` — contribution guidelines including branch strategy, PR checklist, coding standards, and review process.
- `docs/module-usage-guide.md` — practical examples showing how to consume each module from an environment root configuration.
- `docs/module-development.md` — standards and patterns for authoring new modules (variable conventions, output contracts, test requirements).
- `docs/ci-cd-guide.md` — end-to-end walkthrough of the Azure DevOps pipeline stages, workload identity setup, and approval gates.
- `docs/security-guide.md` — security posture documentation covering RBAC, Key Vault access, private endpoints, CMK, and policy guardrails.
- `docs/network-architecture.md` — reference network topology diagram and explanation of VNet, subnet, NSG, and private endpoint design.
- `docs/cost-management.md` — guidance on using Infracost, tagging strategy for cost allocation, and budget alert configuration.
- `docs/troubleshooting.md` — common error messages, root causes, and remediation steps for Terraform, Azure CLI, and pipeline failures.
- `docs/migration-guide.md` — detailed instructions for migrating existing Bicep deployments to the Terraform modules in this repository.
- `docs/runbooks/aks-scaling.md` — operational runbook for scaling AKS node pools up and down, including drain/cordon procedures.
- `docs/runbooks/state-recovery.md` — runbook for recovering from corrupted or lost Terraform remote state, including `terraform import` workflows.
- `docs/runbooks/drift-remediation.md` — runbook for investigating and resolving configuration drift detected by the scheduled drift pipeline.
- `docs/runbooks/secret-rotation.md` — runbook for rotating Key Vault secrets and service principal credentials with zero downtime.
- `docs/runbooks/disaster-recovery.md` — runbook covering region failover, state file restoration, and full environment re-provisioning.
- `tests/README.md` — test strategy document explaining the Terraform native test framework, plan-only vs apply tests, file location conventions, and `make test` / `make test-module` usage.
- `CHANGELOG.md` — this file.

### Changed
- `README.md` — updated all 13 previously "Planned" module statuses to "Available"; added Documentation section linking all 15 docs and runbooks.

---

## Phase 7 — Microsoft Fabric, Azure Policy, and Migration Tooling

### Added
- `modules/fabric-capacity/` — Microsoft Fabric capacity module supporting SKU selection, admin list configuration, and lifecycle management.
- `modules/azure-policy/` — Azure Policy module for defining custom policy definitions, initiative definitions, and scope-targeted assignments with compliance reporting.
- `policies/` — built-in policy assignment examples for tagging enforcement, allowed locations, and required diagnostic settings.
- `migration/` — Bicep-to-Terraform migration artifacts including an inventory script (`scripts/bicep_inventory.sh`), state import helper (`scripts/import_existing.sh`), and ADR-005 documenting the migration strategy.
- `docs/adr/005-migration-strategy.md` — Architecture Decision Record for the phased Bicep-to-Terraform migration approach.
- Environment support for `fabric-capacity` and `azure-policy` module calls in all three environment roots.

### Changed
- `ARCHITECTURE.md` — updated to reflect Governance and Analytics layers.
- `Makefile` — added `make import` target wrapping the import helper script.

---

## Phase 6 — AKS Cluster Module and Reference Implementation

### Added
- `modules/aks-cluster/` — production-grade AKS module with managed identity authentication, CNI Overlay networking, autoscaling node pools, Azure Monitor integration, and workload identity federation support.
- `modules/aks-cluster/tests/` — plan-only and apply test suites covering node pool configuration, identity assignment, and network plugin validation.
- `environments/dev/aks.tf` — reference AKS deployment wiring the cluster module to the VNet, managed identity, Key Vault, and Log Analytics modules.
- `docs/adr/004-aks-identity.md` — ADR documenting the decision to use managed identity over service principal for AKS.
- Drift detection pipeline support for AKS resources.

### Changed
- `modules/managed-identity/` — added federated identity credential outputs to support AKS workload identity.
- `modules/rbac-assignment/` — extended to support AKS-specific built-in roles (e.g. AcrPull, Monitoring Metrics Publisher).

---

## Phase 5 — Storage Account Module and Private Endpoint Integration

### Added
- `modules/storage-account/` — enterprise storage module with hierarchical namespace (ADLS Gen2) option, private endpoint attachment, lifecycle management policies, customer-managed key (CMK) encryption, and diagnostic settings.
- `modules/storage-account/tests/` — plan-only tests for naming validation, lifecycle rule generation, and CMK configuration logic.
- `modules/private-endpoint/` — generic private endpoint module supporting any Azure service sub-resource, DNS zone group integration, and custom NIC name overrides.
- `environments/*/storage.tf` — storage account and private endpoint deployments per environment.

### Changed
- `modules/key-vault/` — added private endpoint output to enable downstream private endpoint module consumption.
- `modules/virtual-network/` — exposed subnet IDs map output required by private endpoint module.

---

## Phase 4 — Identity and RBAC Modules

### Added
- `modules/managed-identity/` — user-assigned managed identity module with outputs for principal ID, client ID, and resource ID for downstream RBAC and workload identity use.
- `modules/rbac-assignment/` — role assignment module supporting built-in and custom role definitions, multiple principal types (user, group, service principal, managed identity), and condition-based assignments.
- `environments/*/identity.tf` — managed identity and RBAC assignment resources per environment.
- `scripts/validate_rbac.sh` — helper script to audit role assignments and detect over-privileged principals.

### Changed
- `modules/key-vault/` — replaced access policies with RBAC mode (`enable_rbac_authorization = true`) as established in ADR-004.
- `modules/aks-cluster/` (stub) — added `identity` block referencing user-assigned managed identity output.

---

## Phase 3 — Core Networking Modules

### Added
- `modules/virtual-network/` — VNet module with configurable address space, DNS server override, DDoS protection plan attachment, and diagnostic settings.
- `modules/subnet/` — subnet module supporting service endpoint lists, delegation blocks (e.g. for AKS, App Service), and network policy flags for private endpoints.
- `modules/network-security-group/` — NSG module with dynamic inbound/outbound rule blocks, association to subnets, and flow log configuration.
- `modules/virtual-network/tests/` and `modules/subnet/tests/` and `modules/network-security-group/tests/` — plan-only test suites.
- `docs/network-architecture.md` (draft) — initial network topology diagram and address space planning table.

### Changed
- `modules/naming/` — extended to generate names for VNet, subnet, and NSG resource types.
- `environments/dev/network.tf` — wired up VNet, subnets, and NSGs using the new modules.

---

## Phase 2 — Key Vault, Log Analytics, and Resource Group Modules

### Added
- `modules/resource-group/` — resource group module enforcing the standard tag schema (environment, owner, cost-centre, managed-by) via variable validation.
- `modules/key-vault/` — Key Vault module with soft-delete, purge protection, RBAC authorisation mode, diagnostic settings forwarded to Log Analytics, and optional private endpoint output.
- `modules/log-analytics/` — Log Analytics workspace module with configurable retention, solutions list, and workspace-level data export.
- `modules/key-vault/tests/` and `modules/log-analytics/tests/` — plan-only test suites.
- `docs/adr/003-state-management.md` — ADR for per-environment remote state with Azure Blob Storage backend and state locking.
- `docs/adr/004-naming-convention.md` — ADR for the Azure CAF-aligned naming convention implemented in the `naming` module.
- `scripts/bootstrap.sh` — one-time script to create the Terraform state storage account and container.
- `environments/dev/`, `environments/staging/`, `environments/prod/` — initial environment root configurations with backend config and provider blocks.

### Changed
- `Makefile` — added `bootstrap`, `init`, `plan`, `apply`, `destroy`, `drift`, `docs`, and `cost` targets.
- `README.md` — updated quick-start section with `make bootstrap` step.

---

## Phase 1 — Repository Bootstrap and Naming Module

### Added
- Repository scaffold: `modules/`, `environments/`, `tests/`, `policies/`, `pipelines/`, `scripts/`, `migration/`, `docs/` directory structure.
- `modules/naming/` — first module: generates Azure-compliant, CAF-aligned resource names from environment, location, and workload inputs. Supports all resource types used across the platform.
- `modules/naming/tests/unit.tftest.hcl` — plan-only tests validating name format, length constraints, and special character handling.
- `README.md` — project overview, architecture table, quick start, module table, and make targets.
- `ARCHITECTURE.md` — layered architecture diagram and design principles.
- `Makefile` — initial `fmt`, `lint`, `validate`, and `test` targets.
- `.gitignore` — standard Terraform gitignore (`.terraform/`, `*.tfstate`, `*.tfplan`, `override.tf`).
- `.tflint.hcl` — TFLint configuration enabling the AzureRM ruleset.
- `docs/adr/001-provider-version.md` — ADR for pinning AzureRM provider to 4.x.
- `docs/adr/002-repo-structure.md` — ADR for monorepo layout with per-environment roots.
- `pipelines/module-ci.yml` — Azure DevOps pipeline for module validation on PRs (fmt, validate, lint, test).
- `pipelines/environment-cd.yml` — Azure DevOps pipeline for environment deployments with plan/approval/apply stages.
- `pipelines/drift-detection.yml` — scheduled daily drift detection pipeline.

---

[Unreleased]: https://github.com/your-org/terraform_azure_project/compare/HEAD...HEAD
