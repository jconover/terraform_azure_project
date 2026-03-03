# ADR-003: Azure Blob Backend with Per-Environment State

## Status

Accepted

## Date

2026-03-03

## Context

Terraform requires a state backend for tracking resource-to-configuration mappings. The backend must support remote access for CI/CD, state locking to prevent concurrent modifications, and environment isolation.

## Decision

Use Azure Storage Account as the state backend with a separate state file per environment (`dev.terraform.tfstate`, `staging.terraform.tfstate`, `prod.terraform.tfstate`). State locking via Azure Blob lease mechanism.

## Options Considered

### Option A: Single State File

- **Pros**: Simplest setup, one backend configuration
- **Cons**: No environment isolation, risk of dev changes affecting prod state, all environments locked together

### Option B: Per-Environment State Files (Chosen)

- **Pros**: Environment isolation, independent plan/apply cycles, blast radius limited to one environment, separate locking per environment
- **Cons**: Cross-environment data sharing requires data source lookups, backend configuration varies per environment

### Option C: Terraform Cloud / HCP

- **Pros**: Managed state, built-in locking, run history, cost estimation, policy enforcement
- **Cons**: External dependency, additional cost, vendor lock-in, less control over backend

## Consequences

### Positive

- Each environment has independent state lifecycle
- CI/CD can plan/apply dev without blocking staging/prod
- State corruption is isolated to one environment
- Blob lease provides reliable distributed locking

### Negative

- Cross-environment references require `terraform_remote_state` or data source lookups
- Must maintain consistent backend configuration across environments
- State backend storage account is bootstrapped outside of Terraform (chicken-and-egg)

## Follow-ups

- Bootstrap script creates the state storage account (`scripts/bootstrap-state-backend.sh`)
- Apply CanNotDelete lock to prevent accidental state backend destruction
- Enable blob soft delete (30 days) and versioning for state file recovery
- Document state recovery procedures in `docs/runbooks/state-recovery.md`
