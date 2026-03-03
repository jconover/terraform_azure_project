# ADR-004: Structured Resource Naming Convention

## Status

Accepted

## Date

2026-03-03

## Context

Azure resources need consistent, predictable names for identification, cost tracking, and operational clarity. Some resources have global uniqueness requirements (Storage Accounts, Key Vaults) with character and length restrictions.

## Decision

Pattern: `{project}-{environment}-{location_short}-{resource_abbreviation}[-{suffix}]`

Special handling:
- **Storage Accounts**: No hyphens, max 24 chars, lowercase alphanumeric, hash suffix for uniqueness
- **Key Vaults**: Max 24 chars, alphanumeric and hyphens

A dedicated naming module (`modules/naming/`) generates compliant names for all resource types.

## Options Considered

### Option A: Free-Form Naming

- **Pros**: Maximum flexibility, no module dependency
- **Cons**: Inconsistent names, naming collisions, difficult cost attribution, no enforcement

### Option B: Azure CAF Naming Module (terraform-azurerm-naming)

- **Pros**: Community-maintained, covers many resource types, well-tested
- **Cons**: External dependency, may not match organizational conventions, less control over abbreviations

### Option C: Custom Naming Module (Chosen)

- **Pros**: Full control over pattern and abbreviations, no external dependency, tailored to project conventions, enforces constraints via variable validation
- **Cons**: Must maintain abbreviation maps, additional module to develop

## Consequences

### Positive

- Predictable names across all environments and resource types
- Names encode environment, location, and purpose — aids debugging and cost tracking
- Variable validation prevents invalid names at plan time
- Central module makes convention changes easy to propagate

### Negative

- Must update abbreviation maps when adding new resource types
- Custom module requires maintenance (vs. community module)
- Naming collisions still possible if same project/env/location combination is reused

## Follow-ups

- Add abbreviations for new resource types as modules are created
- Consider integrating Azure CAF naming provider as a validation cross-check
- Document naming convention in onboarding guide
