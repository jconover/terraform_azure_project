# ADR-006: CI/CD Authentication Method

## Status

Accepted

## Date

2026-03-03

## Context

CI/CD pipelines require Azure credentials to execute Terraform operations (plan, apply, destroy). The authentication method must balance security, operational overhead, and compatibility with Azure DevOps.

## Decision

Use Workload Identity Federation (OIDC) via Azure DevOps service connections for all CI/CD pipeline authentication to Azure.

## Options Considered

### Option A: Service Principal with Client Secret

- **Pros**: Simple setup, widely documented, works with all CI/CD platforms
- **Cons**: Secrets must be stored and rotated, risk of secret exposure in logs or configuration, rotation causes downtime if not automated

### Option B: Managed Identity

- **Pros**: No credentials to manage, Azure-native, automatic rotation
- **Cons**: Requires self-hosted agents running on Azure VMs, not compatible with Microsoft-hosted agents, limits agent pool flexibility

### Option C: Workload Identity Federation (OIDC) (Chosen)

- **Pros**: No stored secrets, no secret rotation, Azure best practice, natively supported by Azure DevOps service connections, short-lived tokens reduce blast radius
- **Cons**: Requires federated credential setup in Entra ID, slightly more complex initial configuration

## Consequences

### Positive

- Zero stored secrets in Azure DevOps — eliminates secret sprawl and rotation overhead
- Short-lived OIDC tokens reduce the blast radius of credential compromise
- Follows Microsoft's recommended best practice for Azure DevOps to Azure authentication
- Compatible with Microsoft-hosted and self-hosted agents
- Terraform AzureRM provider supports OIDC natively via `ARM_USE_OIDC=true`

### Negative

- Initial setup requires configuring federated credentials in Entra ID for each service connection
- Teams unfamiliar with OIDC may need onboarding documentation
- Debugging token exchange failures can be less intuitive than client secret issues

## Follow-ups

- Document federated credential setup steps for each environment (dev, staging, prod)
- Configure service connections in Azure DevOps with workload identity federation
- Add troubleshooting guide for common OIDC token exchange errors
