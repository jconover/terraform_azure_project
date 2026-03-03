# ADR-002: Monorepo Structure

## Status

Accepted

## Date

2026-03-03

## Context

The project needs a repository strategy for organizing reusable Terraform modules, environment-specific root configurations, CI/CD pipelines, tests, and documentation. The choice affects CI/CD triggering, module consumption, versioning, and developer experience.

## Decision

Use a monorepo with clear directory separation: `modules/`, `environments/`, `tests/`, `pipelines/`, `scripts/`, `docs/`, `migration/`, `policies/`.

## Options Considered

### Option A: Monorepo

- **Pros**: Atomic changes across modules and environments, single CI/CD configuration, easier code review, simpler onboarding, immediate module consumption via relative paths
- **Cons**: Requires path-based CI/CD triggers, module versioning via git tags (not registry), larger repo size over time

### Option B: Multi-Repo

- **Pros**: Independent module versioning, separate CI/CD per repo, cleaner git history per component, closer to enterprise module registry pattern
- **Cons**: Cross-repo changes require coordinated PRs, higher CI/CD complexity, harder onboarding, module consumption requires git refs or registry publishing

## Consequences

### Positive

- Single PR for changes spanning modules and environments
- Path-based pipeline triggers (`modules/**` for CI, `environments/**` for CD)
- New team members clone one repo to see everything
- Module examples can reference modules via `../../` relative paths

### Negative

- Cannot version modules independently without git tag conventions
- Must enforce path-based CI/CD triggers to avoid unnecessary pipeline runs
- Repository grows larger as modules and environments accumulate

## Follow-ups

- Implement path-based triggers in Azure DevOps pipelines
- Establish git tag convention for module versioning (e.g., `modules/aks-cluster/v1.0.0`)
- Consider migrating to a private Terraform registry if the module library exceeds 20+ modules
