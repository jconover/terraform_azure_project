# Contributing Guide

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Development Environment Setup](#development-environment-setup)
3. [Branch Naming Conventions](#branch-naming-conventions)
4. [Adding a New Module](#adding-a-new-module)
5. [Module Quality Checklist](#module-quality-checklist)
6. [Variable Validation Requirements](#variable-validation-requirements)
7. [Testing Requirements](#testing-requirements)
8. [Documentation Requirements](#documentation-requirements)
9. [Pull Request Process](#pull-request-process)
10. [ADR Process](#adr-process)
11. [Commit Message Conventions](#commit-message-conventions)
12. [Release Process](#release-process)

---

## Code of Conduct

This project follows a standard contributor code of conduct. All contributors are expected to:

- Use welcoming and inclusive language.
- Respect differing viewpoints and experiences.
- Accept constructive criticism gracefully.
- Focus on what is best for the project and the team.
- Show empathy toward other contributors.

Unacceptable behavior should be reported to the project maintainers. Maintainers have the right and responsibility to remove, edit, or reject contributions that do not align with this guide.

---

## Development Environment Setup

### Prerequisites

Install the following tools before contributing:

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.6.0 | Infrastructure provisioning |
| AzureRM Provider | ~> 4.0 | Azure resource management |
| tflint | latest | Linting with AzureRM rules |
| terraform-docs | >= 0.18.0 | Auto-generate module documentation |
| pre-commit | latest | Enforce checks before commit |
| Azure CLI | latest | Local Azure authentication |
| Make | any | Project task runner |

### Installation Steps

**1. Install Terraform**

Download Terraform >= 1.6.0 from [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads) and ensure it is on your `PATH`.

```bash
terraform version
# Terraform v1.6.x or higher
```

**2. Install tflint and the AzureRM plugin**

```bash
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
tflint --init   # installs plugins defined in .tflint.hcl
tflint --version
```

The project's `.tflint.hcl` loads the AzureRM plugin (v0.27.0) and enforces:
- `terraform_naming_convention` (snake_case)
- `terraform_documented_variables`
- `terraform_documented_outputs`
- `terraform_typed_variables`

**3. Install terraform-docs**

```bash
curl -sSLo terraform-docs.tar.gz \
  https://terraform-docs.io/dl/v0.18.0/terraform-docs-v0.18.0-linux-amd64.tar.gz
tar -xzf terraform-docs.tar.gz terraform-docs
chmod +x terraform-docs
sudo mv terraform-docs /usr/local/bin/
```

**4. Install pre-commit hooks**

```bash
pip install pre-commit
pre-commit install
```

The hooks configured in `.pre-commit-config.yaml` run automatically on `git commit`:

| Hook | Purpose |
|------|---------|
| `terraform_fmt` | Enforce canonical formatting |
| `terraform_validate` | Validate HCL syntax and schema |
| `terraform_tflint` | Run tflint against changed modules |
| `terraform_docs` | Regenerate README.md on change |
| `trailing-whitespace` | Remove trailing whitespace |
| `end-of-file-fixer` | Ensure files end with a newline |
| `check-merge-conflict` | Block accidental conflict markers |
| `detect-private-key` | Block accidental credential commits |

**5. Authenticate with Azure (for local testing)**

```bash
az login
az account set --subscription "<your-subscription-id>"
```

**6. Verify the setup**

```bash
make all   # runs fmt, lint, validate, test
```

---

## Branch Naming Conventions

All branches must follow this naming scheme:

| Prefix | Use for | Example |
|--------|---------|---------|
| `feature/` | New modules or functionality | `feature/storage-account-module` |
| `bugfix/` | Fixes to existing modules | `bugfix/key-vault-access-policy` |
| `docs/` | Documentation-only changes | `docs/update-contributing-guide` |
| `refactor/` | Internal restructuring, no behavior change | `refactor/naming-module-locals` |
| `ci/` | Pipeline or tooling changes | `ci/add-infracost-step` |
| `adr/` | Architectural decision records | `adr/004-state-locking-strategy` |

Use kebab-case (hyphens, lowercase) in the slug portion. Keep it concise and descriptive.

Do not commit directly to `main`. All changes must arrive via a reviewed pull request.

---

## Adding a New Module

Follow these steps exactly when contributing a new module. The CI pipeline validates every module in `modules/` on every PR targeting `main`.

### Step 1: Create the directory structure

```
modules/<module-name>/
  versions.tf
  variables.tf
  main.tf
  outputs.tf
  examples/
    basic/
      main.tf
  README.md
```

Replace `<module-name>` with a lowercase, hyphenated name that matches the primary Azure resource it wraps (e.g., `storage-account`, `virtual-network`, `private-endpoint`).

### Step 2: Populate versions.tf

Pin Terraform and the AzureRM provider versions consistently across all modules:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
```

### Step 3: Define variables in variables.tf

Every variable must have:
- A `description` (required by tflint's `terraform_documented_variables` rule)
- An explicit `type` (required by tflint's `terraform_typed_variables` rule)
- A `validation` block for any string that has a bounded valid set or format constraint
- A `default` only when the variable is genuinely optional

```hcl
variable "name" {
  description = "Name of the resource. Must meet Azure naming constraints."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.name))
    error_message = "Name must be 1-90 characters: alphanumerics, underscores, parentheses, hyphens, periods."
  }
}

variable "location" {
  description = "Azure region for this resource."
  type        = string

  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3",
      "centralus", "northcentralus", "southcentralus",
      "northeurope", "westeurope", "uksouth", "ukwest",
      "southeastasia", "eastasia", "australiaeast", "australiasoutheast",
      "japaneast", "japanwest", "koreacentral", "canadacentral",
      "brazilsouth", "francecentral", "germanywestcentral",
      "norwayeast", "switzerlandnorth", "swedencentral",
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "tags" {
  description = "Map of tags to assign to all resources."
  type        = map(string)
  default     = {}
}
```

### Step 4: Write main.tf

Use the resource label `this` when the module manages a single primary resource. Use descriptive labels when managing multiple resources of the same type.

All resource identifiers must use snake_case (enforced by tflint).

```hcl
resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = var.tags
}
```

### Step 5: Define outputs in outputs.tf

Every output must have a `description` (required by the `terraform_documented_outputs` rule). Expose the `id` and `name` of the primary resource at minimum. Expose additional attributes that callers are likely to reference.

```hcl
output "id" {
  description = "The resource ID of the resource group."
  value       = azurerm_resource_group.this.id
}

output "name" {
  description = "The name of the resource group."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "The Azure region of the resource group."
  value       = azurerm_resource_group.this.location
}
```

### Step 6: Write the basic example

Create `examples/basic/main.tf` with a minimal, runnable call to the module using realistic but non-sensitive values:

```hcl
module "resource_group" {
  source = "../../"

  name     = "rg-platform-dev-eus2"
  location = "eastus2"

  tags = {
    environment = "dev"
    project     = "platform"
    managed_by  = "terraform"
  }
}

output "resource_group" {
  value = {
    id       = module.resource_group.id
    name     = module.resource_group.name
    location = module.resource_group.location
  }
}
```

### Step 7: Generate the README

Run terraform-docs to populate the README with auto-generated input/output tables:

```bash
make docs
# or for a single module:
terraform-docs markdown table --output-file README.md --output-mode inject modules/<module-name>/
```

The CI pipeline compares the checked-in README against a fresh terraform-docs run and fails if they differ. Always regenerate and commit the README before opening a PR.

### Step 8: Write tests

See [Testing Requirements](#testing-requirements) for the full spec. At minimum, provide one `.tftest.hcl` file that validates the module can be planned successfully.

### Step 9: Format and validate locally

```bash
make fmt       # terraform fmt -recursive
make validate  # terraform validate in ENV=dev
make lint      # tflint --recursive
make test      # terraform test -test-directory=tests
```

All four must pass before opening a PR. The CI pipeline enforces the same steps.

---

## Module Quality Checklist

Before marking a PR as ready for review, confirm every item:

**Structure**
- [ ] `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf` all present
- [ ] `examples/basic/main.tf` present and functional
- [ ] `README.md` generated and up to date via terraform-docs

**Variables**
- [ ] Every variable has a `description`
- [ ] Every variable has an explicit `type`
- [ ] All string variables with constrained values have a `validation` block
- [ ] No variable uses `any` as its type without documented justification
- [ ] Sensitive variables are marked with `sensitive = true`

**Outputs**
- [ ] Every output has a `description`
- [ ] `id` and `name` of the primary resource are exposed
- [ ] No sensitive data is exposed in outputs unless marked `sensitive = true`

**Code style**
- [ ] `terraform fmt` produces no diff
- [ ] `tflint` reports zero issues
- [ ] Resource labels use snake_case
- [ ] Primary single-resource modules use the label `this`

**Testing**
- [ ] At least one `.tftest.hcl` file is present in the module directory
- [ ] `terraform test` passes locally

**Documentation**
- [ ] README.md is generated and committed
- [ ] Each non-obvious design choice is explained with a comment in the HCL
- [ ] Any workarounds for AzureRM 4.x behaviors are documented inline

**Security**
- [ ] No hardcoded credentials, subscription IDs, tenant IDs, or secrets
- [ ] `detect-private-key` pre-commit hook passes
- [ ] Sensitive inputs use `sensitive = true`

---

## Variable Validation Requirements

Validation blocks are required for the following categories of variables. Use the patterns established in existing modules as the canonical reference.

### Location

All modules that accept a location must validate against the project-approved region list. Copy the validation block from `modules/resource-group/variables.tf` exactly. Adding new regions requires a PR updating all modules and, if the addition reflects a policy change, an ADR.

### Resource names

Validate names against the Azure naming rules for the specific resource type. The condition must check:
- Minimum and maximum length
- Allowed characters (via regex)

Include the Azure constraint details in the `error_message` so the caller knows exactly what is required without consulting external documentation.

```hcl
validation {
  condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.name))
  error_message = "Name must be 1-90 characters: alphanumerics, underscores, parentheses, hyphens, periods."
}
```

### Boolean flags

Boolean variables do not need validation blocks. They are self-documenting. Provide a clear `description` that explains the effect of `true` vs `false`.

### Numeric values

Validate that numeric inputs are within the range supported by the Azure resource. For example, a SKU capacity should be validated against its allowed values rather than left unbounded.

### Maps and lists

Validate that maps or lists are non-empty when the module requires at least one entry. Use `length(var.x) > 0` in the condition.

### Sensitive variables

Mark variables that carry credentials, keys, or connection strings with `sensitive = true`. Do not add validation conditions that would print the sensitive value in an error message.

---

## Testing Requirements

All modules must include at least one test file. Tests use native Terraform test syntax (`.tftest.hcl`) introduced in Terraform 1.6.0.

### File placement

Place test files directly inside the module directory:

```
modules/<module-name>/
  <module-name>.tftest.hcl
```

### Minimum test coverage

Every module must have tests that cover:

1. **Plan-only validation** - confirm the module produces a valid plan with representative inputs. Use `command = plan` to avoid requiring live Azure credentials in CI.
2. **Output assertions** - assert that outputs have the expected structure and values using `assert` blocks.

```hcl
run "valid_inputs_produce_plan" {
  command = plan

  variables {
    name     = "rg-test-dev-eus2"
    location = "eastus2"
    tags = {
      environment = "test"
    }
  }

  assert {
    condition     = output.name == "rg-test-dev-eus2"
    error_message = "Expected output.name to equal the input name."
  }
}
```

3. **Validation rejection** - confirm that invalid inputs are rejected by the module's `validation` blocks. Use `expect_failures` to assert that an invalid input triggers the expected error.

```hcl
run "invalid_location_is_rejected" {
  command = plan

  variables {
    name     = "rg-test-dev-eus2"
    location = "invalidregion"
  }

  expect_failures = [var.location]
}
```

### Running tests locally

```bash
# Run all tests across all modules
make test

# Run tests for a single module
make test-module MODULE=resource-group

# Run directly with Terraform
cd modules/resource-group && terraform test
```

### CI behavior

The CI pipeline (`pipelines/module-ci.yml`) runs `terraform test` for every module that contains at least one `.tftest.hcl` file. Modules without test files are skipped with a warning. This exemption is temporary; all new modules must include tests.

---

## Documentation Requirements

Module documentation is generated automatically by terraform-docs and must be kept up to date. The CI pipeline (`DocsCheck` stage) will fail any PR where the checked-in README does not match the current terraform-docs output.

### README.md structure

The README for each module must contain terraform-docs injection markers:

```markdown
<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
```

terraform-docs injects the inputs and outputs tables between these markers. Do not edit the content between the markers manually; it will be overwritten.

Content outside the markers (module description, usage examples, notes) is preserved and should be written by the contributor.

### Minimum README content

Each module README must contain:

1. A one-paragraph description of what the module manages and its intended use.
2. A usage example (can reference `examples/basic/main.tf`).
3. The terraform-docs-generated inputs and outputs tables.
4. Any known limitations, AzureRM 4.x workarounds, or non-obvious behavior.

### Regenerating docs

```bash
# Regenerate all module READMEs
make docs

# Regenerate for a single module
terraform-docs markdown table \
  --output-file README.md \
  --output-mode inject \
  modules/<module-name>/
```

Always run `make docs` and commit the result before opening a PR. The pre-commit hook `terraform_docs` will also regenerate the README automatically when you commit changes to a module.

### Inline comments

Use HCL comments (`#`) to explain non-obvious logic, lifecycle rules, or workarounds. Comments should explain *why*, not restate what the code already says.

---

## Pull Request Process

### Before opening a PR

1. Run `make all` locally and confirm it exits 0.
2. Confirm all pre-commit hooks pass: `pre-commit run --all-files`.
3. Ensure the module README is up to date: `make docs`.
4. Write a clear PR description (see below).

### PR description format

```
## Summary
Brief description of what this PR does and why.

## Changes
- List of specific changes made.

## Testing
- How the changes were tested locally.
- Any limitations (e.g., plan-only, no live Azure credentials).

## Checklist
- [ ] `make all` passes
- [ ] pre-commit hooks pass
- [ ] terraform-docs README is up to date
- [ ] Tests added or updated
- [ ] ADR created if an architectural decision was made
```

### CI pipeline

Every PR targeting `main` that touches `modules/**` triggers the Module CI pipeline (`pipelines/module-ci.yml`). It runs three stages in sequence:

1. **Validate** - `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`, and `tflint` for every module.
2. **Test** - `terraform test` for every module that has `.tftest.hcl` files.
3. **DocsCheck** - verifies that all module READMEs match the current terraform-docs output.

All three stages must pass before a PR can be merged.

### Review expectations

PRs require at least one approval from a maintainer. Reviewers will check:

- Correctness of the Terraform logic and Azure resource configuration.
- Completeness of variable validation.
- Adequacy of test coverage.
- Clarity and accuracy of documentation.
- Adherence to the module quality checklist.

Reviewers will not approve a PR that:
- Has failing CI checks.
- Contains hardcoded credentials or subscription IDs.
- Introduces a new module without tests.
- Has a stale README.

Respond to review comments within two business days. If a PR is abandoned for two weeks without response, a maintainer may close it.

### Merging

Squash and merge is the default merge strategy for `main`. The squash commit message must follow the [commit message conventions](#commit-message-conventions).

---

## ADR Process

Architectural Decision Records (ADRs) document significant decisions that affect the structure, tooling, or conventions of this project. They live in `docs/adr/` and are numbered sequentially.

### When to write an ADR

Write an ADR when:
- Choosing between two or more viable implementation approaches.
- Introducing or removing a tool or dependency.
- Changing a cross-cutting convention (naming, tagging, state management, CI strategy).
- Making a decision that future contributors may need to understand to avoid re-litigating.

You do not need an ADR for:
- Bug fixes.
- Adding a new module that follows existing patterns.
- Documentation updates.
- Routine dependency updates.

### ADR file naming

```
docs/adr/<NNN>-<short-description>.md
```

Where `<NNN>` is the next available three-digit number (zero-padded). Check the existing files in `docs/adr/` and increment from the highest number.

### ADR template

```markdown
# ADR-<NNN>: <Title>

## Status

Proposed | Accepted | Deprecated | Superseded by ADR-<NNN>

## Date

YYYY-MM-DD

## Context

Describe the situation that necessitates a decision. What forces or constraints are at play?

## Decision

State the decision clearly and concisely.

## Options Considered

### Option A: <Name>
- **Pros**: ...
- **Cons**: ...

### Option B: <Name>
- **Pros**: ...
- **Cons**: ...

## Consequences

### Positive
- ...

### Negative
- ...

## Follow-ups

- List any actions required as a result of this decision.
```

### ADR workflow

1. Create a branch prefixed `adr/`: `adr/008-module-versioning-strategy`.
2. Write the ADR file in `docs/adr/`.
3. Set status to `Proposed`.
4. Open a PR. Reviewers discuss and request changes.
5. When the team reaches consensus, set status to `Accepted` and merge.
6. If a future decision supersedes this ADR, update the status to `Superseded by ADR-<NNN>` rather than deleting the file.

---

## Commit Message Conventions

This project uses a subset of [Conventional Commits](https://www.conventionalcommits.org/).

### Format

```
<type>(<scope>): <short summary>

[optional body]

[optional footer]
```

### Types

| Type | When to use |
|------|-------------|
| `feat` | New module or new feature in an existing module |
| `fix` | Bug fix in module logic or configuration |
| `docs` | Documentation-only change |
| `refactor` | Code change that neither adds a feature nor fixes a bug |
| `test` | Adding or modifying tests |
| `ci` | Changes to pipeline files or tooling configuration |
| `chore` | Housekeeping: dependency updates, pre-commit config changes |

### Scope

Use the module name or area of the repo as the scope:

```
feat(storage-account): add private endpoint support
fix(key-vault): correct access policy merge behavior
docs(contributing): add ADR process section
ci(module-ci): add infracost estimate step
```

### Short summary rules

- Use the imperative mood: "add", "fix", "update", not "added", "fixed", "updated".
- Do not capitalize the first letter.
- Do not end with a period.
- Keep it under 72 characters.

### Body and footer

Use the body to explain *why* the change was made, not *what* was changed (the diff shows what). Reference issue numbers or ADRs in the footer:

```
feat(virtual-network): add support for DDoS protection plan

Azure recommends attaching a DDoS protection plan to hub VNets in
production environments. This change adds an optional input variable
to enable the association when a plan ID is provided.

Refs: ADR-005
```

---

## Release Process

Releases mark stable snapshots of the platform modules and are performed by maintainers.

### Versioning

This project uses [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`):

| Increment | When |
|-----------|------|
| `PATCH` | Backward-compatible bug fixes or documentation updates |
| `MINOR` | New modules or backward-compatible feature additions |
| `MAJOR` | Breaking changes to existing module interfaces (variable removals, type changes, renamed outputs) |

### Release checklist

Before creating a release:

1. Confirm `main` is green: all CI checks pass.
2. Run `make all` from a clean checkout.
3. Review the commit log since the last release and determine the appropriate version bump.
4. Update the changelog (if maintained) with a summary of changes.
5. Create a git tag following the format `v<MAJOR>.<MINOR>.<PATCH>`:

```bash
git tag -a v1.2.0 -m "Release v1.2.0 - add storage-account and private-endpoint modules"
git push origin v1.2.0
```

### Breaking changes

Before merging any breaking change to `main`:
- Document the breaking change in the PR description under a `## Breaking Changes` section.
- Write or update an ADR if the change reflects an architectural decision.
- Include a migration note in the relevant module's README explaining what callers must change.

Breaking changes to a module's public interface (variable names, types, output names) require a major version bump.
