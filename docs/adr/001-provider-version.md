# ADR-001: Use AzureRM Provider 4.x

## Status

Accepted

## Date

2026-03-03

## Context

The project requires a Terraform provider for managing Azure resources. Two major versions are available: AzureRM 3.x (stable, widely deployed in enterprise) and AzureRM 4.x (latest, with breaking changes from 3.x but forward-looking improvements).

## Decision

Use AzureRM Provider `~> 4.0` with Terraform `>= 1.6.0`.

## Options Considered

### Option A: AzureRM 3.x (Stable)

- **Pros**: Widely deployed, extensive community examples, proven in production, no migration needed for existing 3.x users
- **Cons**: Approaching end-of-life, inconsistent naming conventions (`enable_*` mixed patterns), missing newer Azure service support

### Option B: AzureRM 4.x (Forward-Looking)

- **Pros**: Consistent naming (`*_enabled`), latest Azure service support, active development, required for new Fabric/AKS features
- **Cons**: Breaking changes from 3.x, fewer community examples, may encounter provider bugs in newer resources

## Consequences

### Positive

- Access to latest Azure services and features
- Consistent resource argument naming convention
- Aligns with Azure provider roadmap
- Demonstrates current expertise to reviewers

### Negative

- Fewer community examples to reference
- Must consult the 3.x to 4.x upgrade guide for each resource
- Some third-party modules may not yet support 4.x

## Follow-ups

- Monitor AzureRM 4.x changelog for breaking changes in minor releases
- Pin minor version (`~> 4.0`) to prevent unexpected breaking changes
- Document any 4.x-specific workarounds in module READMEs
