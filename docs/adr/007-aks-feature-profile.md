# ADR-007: AKS Feature Profile

## Status

Accepted

## Date

2026-03-03

## Context

Azure Kubernetes Service (AKS) has 100+ configurable parameters spanning networking, identity, scaling, security, monitoring, and add-ons. Defining a clear feature profile for the Terraform module prevents scope creep while ensuring production readiness.

## Decision

Define an explicit in-scope and out-of-scope feature set for the AKS module. In-scope features cover the production baseline. Out-of-scope features are documented as extension points.

### In-Scope Features

- **Identity**: Managed identity (system-assigned), workload identity with OIDC issuer
- **Networking**: Azure CNI Overlay, network policy (Azure or Calico)
- **Scaling**: Cluster autoscaler with configurable min/max node counts
- **Security**: Entra ID RBAC integration, Azure Policy for Kubernetes, pod security admission
- **Operations**: Maintenance windows, automatic node OS upgrades
- **Observability**: Diagnostic settings for log and metric export, Container Insights integration

### Out-of-Scope Features

- **Service Mesh**: Istio-based service mesh add-on — managed separately by platform teams
- **GitOps**: Flux or Argo CD extensions — deployed post-provisioning by application teams
- **Custom Node Images**: Custom VHDs for node pools — requires separate image pipeline
- **GPU Node Pools**: GPU-enabled node pools — added as needed via module extension

## Options Considered

### Option A: Minimal Module (Compute Only)

- **Pros**: Simple, fast to build, low maintenance
- **Cons**: Teams must configure security, networking, and observability separately — error-prone and inconsistent

### Option B: Production Baseline Profile (Chosen)

- **Pros**: Covers 90% of production use cases, enforces security and operational best practices by default, clear extension points for advanced needs
- **Cons**: More parameters to maintain, module complexity is higher than a minimal approach

### Option C: Comprehensive Module (All Features)

- **Pros**: Single module for all AKS configurations
- **Cons**: Extremely complex, high maintenance burden, slow iteration, many features unused by most teams

## Consequences

### Positive

- Module covers the production baseline without scope creep
- Security and operational best practices are enforced by default
- Out-of-scope features are documented with clear extension guidance
- Teams needing advanced features can extend the module without forking

### Negative

- Teams requiring GPU node pools, service mesh, or GitOps must add resources outside the module
- Feature profile must be reviewed periodically as AKS evolves and new features reach GA
- Boundary between in-scope and out-of-scope may need re-evaluation as adoption grows

## Follow-ups

- Review AKS feature profile quarterly against Azure AKS release notes
- Document extension patterns for adding out-of-scope features alongside the module
- Collect feedback from teams on missing in-scope features after initial rollout
