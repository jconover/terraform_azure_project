# ADR-005: Fabric Automation Scope Limitations

## Status

Accepted

## Date

2026-03-03

## Context

Microsoft Fabric is a unified analytics platform combining data engineering, data warehousing, real-time analytics, and business intelligence. Terraform support for Fabric is limited to capacity provisioning via the `azurerm_fabric_capacity` resource in the AzureRM provider. Fabric workspace items (lakehouses, warehouses, pipelines, dataflows, notebooks, semantic models) cannot be managed through Terraform as they are not ARM resources — they exist within the Fabric control plane.

## Decision

Scope Fabric automation to capacity provisioning and RBAC setup only. Document provider gaps and REST API alternatives for teams that need workspace-level management.

## Options Considered

### Option A: Terraform Only for Provider-Supported Resources (Chosen)

- **Pros**: Stable, maintainable, follows provider best practices, no custom code to maintain
- **Cons**: Limited automation scope — workspace items require separate tooling

### Option B: Custom Terraform Provider for Fabric

- **Pros**: Full Terraform-native management of all Fabric resources
- **Cons**: High development and maintenance burden, must track Fabric API changes, risk of breaking changes, no community support

### Option C: Hybrid Terraform + Scripts

- **Pros**: Broader automation coverage using Terraform provisioners or `terraform_data` with scripts
- **Cons**: Mixed tooling, harder to maintain, provisioner anti-patterns, scripts lack plan/apply lifecycle

## Consequences

### Positive

- Infrastructure-as-code for capacity management is stable and follows AzureRM provider conventions
- RBAC assignments for service principals are fully managed in Terraform
- Clear documentation of what is and is not in scope prevents unrealistic expectations
- Teams have documented alternatives (REST API, PowerShell) for workspace management

### Negative

- Teams needing Fabric workspace item management must use REST API or PowerShell outside Terraform
- No single tool manages the full Fabric stack — operational complexity for teams spanning capacity and workspace concerns
- Must monitor AzureRM provider releases for expanded Fabric support and update scope accordingly

## Follow-ups

- Monitor AzureRM provider for new Fabric resource types and expand module scope when available
- Evaluate community Fabric providers if they emerge
- Consider a companion PowerShell/CLI automation module for workspace management if demand warrants it
