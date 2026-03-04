# Test Strategy

This directory houses automated tests for the Terraform Azure Infrastructure Platform.

## Test Framework

Tests are written using **Terraform's native test framework** (`.tftest.hcl`), available since Terraform 1.6.0. No external test runner (e.g. Terratest) is required.

## Test File Location Convention

Each module's tests live alongside the module itself:

```
modules/
└── <module-name>/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── tests/
        ├── unit.tftest.hcl       # Plan-only tests (no Azure credentials needed)
        └── integration.tftest.hcl # Apply tests (requires Azure subscription)
```

The `tests/` directory at the repository root is reserved for cross-module and end-to-end test suites that exercise multiple modules together.

## Plan-Only vs Apply Tests

### Plan-Only Tests (`command = plan`)

Plan-only tests validate configuration logic, variable defaults, output expressions, and local computations without creating any real Azure resources. They run quickly and require no Azure credentials, making them suitable for every PR check.

```hcl
run "validate_naming_output" {
  command = plan

  variables {
    environment = "dev"
    location    = "eastus"
  }

  assert {
    condition     = output.resource_group_name == "rg-dev-eastus-001"
    error_message = "Resource group name does not match expected format."
  }
}
```

### Apply Tests (`command = apply`)

Apply tests provision real Azure resources, verify their properties, and then destroy them automatically at the end of the test run. They require a valid Azure subscription and appropriate credentials. Use these to validate provider behaviour, dependency chains, and outputs that are only known after apply.

```hcl
run "creates_resource_group" {
  command = apply

  variables {
    name     = "rg-test-eastus-001"
    location = "eastus"
    tags     = { environment = "test" }
  }

  assert {
    condition     = azurerm_resource_group.this.location == "eastus"
    error_message = "Resource group was not created in the expected location."
  }
}
```

## Running Tests

### Run all module tests

```bash
make test
```

This target iterates over every module that contains a `tests/` directory and executes `terraform test` inside it.

### Run tests for a specific module

```bash
make test-module MODULE=naming
make test-module MODULE=aks-cluster
make test-module MODULE=storage-account
```

### Run tests directly with Terraform

```bash
cd modules/naming
terraform init
terraform test

# Verbose output
terraform test -verbose

# Target a single test file
terraform test -filter=tests/unit.tftest.hcl
```

### Environment variables for apply tests

Apply tests require credentials. The recommended approach is workload identity federation in CI and `az login` locally:

```bash
export ARM_SUBSCRIPTION_ID="<subscription-id>"
export ARM_TENANT_ID="<tenant-id>"
# OIDC (CI) — set ARM_USE_OIDC=true and ARM_CLIENT_ID
# Service principal — set ARM_CLIENT_ID and ARM_CLIENT_SECRET
```

## Test Categories

| Category | Command | Credentials Required | Speed |
|----------|---------|----------------------|-------|
| Unit / plan-only | `plan` | No | Fast (~seconds) |
| Integration / apply | `apply` | Yes | Slow (~minutes) |
| End-to-end (root `tests/`) | `apply` | Yes | Slow (~minutes) |

## CI Integration

The **Module CI** pipeline (`.pipelines/module-ci.yml`) runs plan-only tests on every pull request and full apply tests on merges to `main`. Apply tests are skipped automatically when Azure credentials are not available (e.g. community forks without secret access).

## Adding Tests for a New Module

1. Create `modules/<name>/tests/` directory.
2. Add `unit.tftest.hcl` with `command = plan` runs covering variable defaults, validation rules, and output expressions.
3. Optionally add `integration.tftest.hcl` with `command = apply` runs for provider-level assertions.
4. The `make test` target picks up the new tests automatically — no Makefile changes needed.
