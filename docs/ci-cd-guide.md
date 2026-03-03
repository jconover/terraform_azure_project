# CI/CD Pipeline Guide

This guide covers the complete CI/CD pipeline setup for this Terraform Azure project. All pipelines run on Azure DevOps using Microsoft-hosted Ubuntu agents and authenticate to Azure through Workload Identity Federation (OIDC) — no stored secrets are used anywhere in the pipeline configuration.

---

## Table of Contents

1. [Pipeline Architecture Overview](#1-pipeline-architecture-overview)
2. [Module CI Pipeline](#2-module-ci-pipeline)
3. [Environment CD Pipeline](#3-environment-cd-pipeline)
4. [Drift Detection Pipeline](#4-drift-detection-pipeline)
5. [Pipeline Templates Explained](#5-pipeline-templates-explained)
6. [OIDC Authentication Setup](#6-oidc-authentication-setup)
7. [Environment Approval Gates Configuration](#7-environment-approval-gates-configuration)
8. [Variable Groups and Secrets Management](#8-variable-groups-and-secrets-management)
9. [Pipeline Customization Guide](#9-pipeline-customization-guide)
10. [Adding a New Environment to CD](#10-adding-a-new-environment-to-cd)
11. [Debugging Pipeline Failures](#11-debugging-pipeline-failures)
12. [Pipeline Security Considerations](#12-pipeline-security-considerations)

---

## 1. Pipeline Architecture Overview

Three pipelines cover the full lifecycle of Terraform changes in this project.

```
┌─────────────────────────────────────────────────────────────────┐
│  Pull Request (modules/**)                                      │
│                                                                 │
│  module-ci.yml                                                  │
│  ├── Stage: Validate  (fmt, init, validate, tflint)             │
│  ├── Stage: Test      (terraform test — parallel with DocsCheck)│
│  └── Stage: DocsCheck (terraform-docs freshness check)          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Push to main (environments/**, modules/**)                     │
│                                                                 │
│  environment-cd.yml                                             │
│  ├── Stage: Dev     → Plan → Apply (auto-approval)              │
│  ├── Stage: Staging → Plan → Apply (manual approval gate)       │
│  └── Stage: Prod    → Plan → Apply (2-approver gate)            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Schedule: daily 6:00 AM UTC                                    │
│                                                                 │
│  drift-check.yml                                                │
│  ├── Stage: DevDriftCheck     (parallel)                        │
│  ├── Stage: StagingDriftCheck (parallel)                        │
│  └── Stage: ProdDriftCheck    (parallel)                        │
└─────────────────────────────────────────────────────────────────┘
```

**Pipeline files:**

| File | Trigger | Purpose |
|---|---|---|
| `pipelines/module-ci.yml` | PR targeting `main` where `modules/**` changed | Validates all Terraform modules |
| `pipelines/environment-cd.yml` | Push to `main` where `environments/**` or `modules/**` changed | Deploys to dev, staging, prod sequentially |
| `pipelines/drift-check.yml` | Cron: daily 6 AM UTC | Detects out-of-band infrastructure changes |

**Shared templates** (reusable steps referenced by the pipelines above):

| Template | Purpose |
|---|---|
| `pipelines/templates/terraform-init.yml` | Authenticated `terraform init` with backend config and `.terraform` caching |
| `pipelines/templates/terraform-validate.yml` | `fmt -check`, `validate`, tflint, `terraform test` |
| `pipelines/templates/terraform-plan.yml` | Authenticated `terraform plan`, plan artifact publishing, optional PR comment |
| `pipelines/templates/terraform-apply.yml` | Authenticated `terraform apply` using a previously published plan artifact |
| `pipelines/templates/drift-detection.yml` | Authenticated `terraform plan -detailed-exitcode` with drift output reporting |

All Azure authentication across every template and pipeline uses `useWorkloadIdentityFederation: true` on the `AzureCLI@2` task, with `ARM_USE_OIDC=true` exported into the Terraform environment. See [Section 6](#6-oidc-authentication-setup) for setup details.

---

## 2. Module CI Pipeline

**File:** `pipelines/module-ci.yml`

### Trigger

The pipeline has no push trigger (`trigger: none`). It runs only on pull requests targeting `main` where at least one file under `modules/**` has changed.

```yaml
pr:
  branches:
    include:
      - main
  paths:
    include:
      - modules/**
```

This means changes that only touch `environments/**` or documentation do not trigger module CI. Changes to shared modules on a PR always do.

### Stage 1: Validate

Runs all four validation checks against every subdirectory found directly under `modules/` (one level deep, sorted alphabetically). Failures in individual modules are accumulated — the stage does not short-circuit on the first failure. All modules are checked, and a single exit with a summary occurs at the end.

**`terraform fmt -check`**

Checks formatting without modifying files. Reports an error annotation in the Azure DevOps UI using `##vso[task.logissue type=error]`. If formatting is wrong, run `terraform fmt modules/<name>` locally before pushing.

**`terraform init -backend=false`**

Initialises the module without connecting to any remote backend. This downloads providers declared in the module so that `validate` has type information available. If `init` fails, the module is skipped for the remaining checks in that loop iteration (the `continue` statement prevents a cascade of misleading errors).

**`terraform validate`**

Validates configuration correctness: type constraints, required arguments, and reference resolution. This does not contact Azure.

**`tflint`**

Runs if a `.tflint.hcl` configuration file exists at the repository root. Uses `--chdir` to run inside the module directory and `--config` to point back to the root config. If no `.tflint.hcl` exists, tflint is skipped silently.

### Stage 2: Test

Depends on `Validate` succeeding. Iterates every module under `modules/` and looks for files matching `*.tftest.hcl`. Modules with no test files are skipped with a log message — the stage does not fail in this case. If at least one module has test files but those tests fail, the stage fails.

Tests run with `terraform test` inside each module directory after re-running `init -backend=false`. Tests that provision real infrastructure require Azure credentials; add those to the pipeline as a variable group (see [Section 8](#8-variable-groups-and-secrets-management)) if your test files provision resources.

### Stage 3: DocsCheck

Depends on `Validate` succeeding and runs in parallel with `Test`. Installs `terraform-docs` v0.18.0 and checks that each module's `README.md` matches the output of `terraform-docs markdown table <module-dir>`. If a README is missing, a warning is printed but the stage continues. If a README exists but is stale, the stage fails and shows a diff.

To fix a failing DocsCheck, run:

```bash
terraform-docs markdown table modules/<name> > modules/<name>/README.md
```

Or configure `terraform-docs` to update READMEs automatically in your editor or as a pre-commit hook.

---

## 3. Environment CD Pipeline

**File:** `pipelines/environment-cd.yml`

### Trigger

Runs on every push to `main` where `environments/**` or `modules/**` has changed.

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - environments/**
      - modules/**
```

### Pipeline-Level Variables

```yaml
variables:
  terraformVersion: '1.6.0'
  serviceConnection: 'azure-terraform-oidc'
  backendResourceGroup: 'rg-terraform-state'
  backendStorageAccount: 'stterraformstate'
```

`terraformVersion` pins Terraform to 1.6.0 across all CD stages, ensuring consistent plan/apply behaviour. The `serviceConnection` value `azure-terraform-oidc` is the name of the Azure DevOps service connection configured with Workload Identity Federation (see [Section 6](#6-oidc-authentication-setup)).

### Promotion Flow

Stages run sequentially with explicit `dependsOn` relationships:

```
Dev (auto) --> Staging (manual approval) --> Prod (2-approver)
```

Each stage follows an identical pattern:

1. **Plan job** — runs `terraform init` with environment-specific backend key, then `terraform plan -var-file=<env>.tfvars -out=tfplan`. The plan binary is published as a pipeline artifact (`dev-plan`, `staging-plan`, `prod-plan`).
2. **Apply deployment** — downloads the plan artifact, re-runs `terraform init`, then applies the saved plan with `terraform apply`. Uses Azure DevOps `deployment` job type so that environment approval gates are enforced before apply executes.

The plan-then-apply split is important: the plan output is frozen as an artifact before any approval gate. Approvers are reviewing a specific, deterministic set of changes — not a plan that could drift between approval and apply.

### Backend State Keys

Each environment writes to a separate state key in the same storage account:

| Environment | State Key |
|---|---|
| Dev | `dev.tfstate` |
| Staging | `staging.tfstate` |
| Prod | `prod.tfstate` |

Backend container is hardcoded to `tfstate`. The resource group and storage account come from pipeline variables.

### Environment Variable Files

Each environment directory is expected to contain an environment-specific `.tfvars` file:

| Environment | Working Directory | Var File |
|---|---|---|
| Dev | `environments/dev` | `dev.tfvars` |
| Staging | `environments/staging` | `staging.tfvars` |
| Prod | `environments/prod` | `prod.tfvars` |

---

## 4. Drift Detection Pipeline

**File:** `pipelines/drift-check.yml`

### Schedule

```yaml
schedules:
  - cron: '0 6 * * *'
    displayName: 'Daily Drift Detection (6:00 AM UTC)'
    branches:
      include:
        - main
    always: true
```

`always: true` forces the pipeline to run even when no code has changed since the last run. This is essential for drift detection — the purpose is to detect changes made outside of Terraform (in the Azure portal, via CLI, by other automation), so a clean repo is expected.

### Parallelism

All three environment checks run simultaneously (`dependsOn: []` on staging and prod stages). Drift in one environment does not block checks of the others.

### Drift Detection Logic

Each stage uses the `templates/drift-detection.yml` template, which uses `terraform plan -detailed-exitcode` to distinguish three outcomes:

| Exit Code | Meaning | Action |
|---|---|---|
| `0` | No changes — no drift | Sets output variable `driftDetected=false`, logs a section header |
| `2` | Changes present — drift detected | Sets output variable `driftDetected=true`, logs a warning annotation, prints the full plan output |
| Any other | `terraform plan` itself failed | Exits with error, fails the job |

Each environment uses a separate service connection (`azure-dev`, `azure-staging`, `azure-prod`) rather than the shared `azure-terraform-oidc` connection used in CD. This provides least-privilege isolation between environments for the read-only drift check operations.

### Alerts

When drift is detected, Azure DevOps marks the stage with a warning (`##[warning]`). To get notified, configure a pipeline notification rule in Azure DevOps:

**Project Settings > Notifications > New subscription:**
- Event: "Run stage state changed"
- Filter: Stage result = "Partially succeeded" or "Failed"
- Deliver to: your team email or Teams channel webhook

You can also use the `driftDetected` output variable in downstream notification steps if you add a post-processing stage.

---

## 5. Pipeline Templates Explained

Templates live in `pipelines/templates/` and are referenced with the `template:` key. They accept typed parameters and produce reusable, consistent steps.

### `terraform-init.yml`

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workingDirectory` | string | required | Path to the Terraform configuration directory |
| `backendServiceConnection` | string | required | Azure DevOps service connection for backend storage auth |
| `backendResourceGroup` | string | required | Resource group containing the state storage account |
| `backendStorageAccount` | string | required | Name of the Azure Storage account |
| `backendContainer` | string | `tfstate` | Blob container name |
| `backendKey` | string | required | State file name (e.g. `dev.tfstate`) |

**What it does:**

1. Installs Terraform using `TerraformInstaller@1`.
2. Runs `terraform init` via `AzureCLI@2` with OIDC, passing all backend config values as `-backend-config` flags.
3. Caches the `.terraform` directory using `Cache@2`. The cache key is composed of the working directory and backend key, so each environment gets its own cache entry.

The cache step can provide a meaningful speedup on provider-heavy configurations by avoiding repeated provider downloads.

**Example usage:**

```yaml
steps:
  - template: templates/terraform-init.yml
    parameters:
      workingDirectory: '$(System.DefaultWorkingDirectory)/environments/dev'
      backendServiceConnection: 'azure-terraform-oidc'
      backendResourceGroup: 'rg-terraform-state'
      backendStorageAccount: 'stterraformstate'
      backendKey: 'dev.tfstate'
```

### `terraform-validate.yml`

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `workingDirectory` | string | Path to the Terraform configuration directory |

**What it does:**

Runs four checks sequentially, all with `continueOnError: true` so that later checks still run even if an earlier one fails. The calling job is responsible for checking the overall result.

1. `terraform fmt -check -recursive` — format check.
2. `terraform validate` — configuration validity check.
3. tflint — installs and runs tflint with `.tflint.hcl` from the working directory.
4. `terraform test` — only runs if `*.tftest.hcl` or `*_test.tf` files are found; skipped silently otherwise.

**Example usage:**

```yaml
steps:
  - template: templates/terraform-validate.yml
    parameters:
      workingDirectory: '$(System.DefaultWorkingDirectory)/environments/dev'
```

### `terraform-plan.yml`

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workingDirectory` | string | required | Path to the Terraform configuration directory |
| `varFile` | string | required | Path to the `.tfvars` file relative to `workingDirectory` |
| `serviceConnection` | string | required | Azure DevOps service connection for Azure auth |
| `publishPlan` | boolean | `true` | Whether to publish the plan as a pipeline artifact and post a PR comment |

**What it does:**

1. Runs `terraform plan -var-file=<varFile> -out=tfplan` with OIDC authentication.
2. Runs `terraform show -no-color tfplan > tfplan.txt` to produce a human-readable plan summary.
3. If `publishPlan` is true, publishes `tfplan` as a pipeline artifact named `terraform-plan-$(environment)`.
4. If `publishPlan` is true and this is a PR build (`$SYSTEM_PULLREQUEST_PULLREQUESTID` is set), posts the plan summary as a PR comment using `az repos pr comment create`. Requires `System.AccessToken` to be available as the `AZURE_DEVOPS_EXT_PAT` environment variable.

**Example usage:**

```yaml
steps:
  - template: templates/terraform-plan.yml
    parameters:
      workingDirectory: '$(System.DefaultWorkingDirectory)/environments/staging'
      varFile: 'staging.tfvars'
      serviceConnection: 'azure-terraform-oidc'
      publishPlan: true
```

### `terraform-apply.yml`

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `workingDirectory` | string | Path to the Terraform configuration directory |
| `serviceConnection` | string | Azure DevOps service connection for Azure auth |
| `environment` | string | Azure DevOps environment name (controls approval gates) |

**What it does:**

This template defines a `deployment` job (not a `steps` list), which is the key distinction. Using a `deployment` job type causes Azure DevOps to enforce any approval checks configured on the named environment before the job runs.

Steps inside the deployment:

1. Checks out the repository.
2. Installs Terraform.
3. Downloads the plan artifact `terraform-plan-<environment>` into the working directory.
4. Runs `terraform init -input=false` (re-initialises to ensure provider plugins are present on the apply agent).
5. Runs `terraform apply -input=false tfplan`.

**Example usage:**

```yaml
jobs:
  - template: templates/terraform-apply.yml
    parameters:
      workingDirectory: '$(System.DefaultWorkingDirectory)/environments/prod'
      serviceConnection: 'azure-terraform-oidc'
      environment: 'prod'
```

### `drift-detection.yml`

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `workingDirectory` | string | Path to the Terraform configuration directory |
| `varFile` | string | Path to the `.tfvars` file |
| `serviceConnection` | string | Azure DevOps service connection for Azure auth |
| `environment` | string | Environment name used in log messages |

**What it does:**

Runs `terraform plan -detailed-exitcode` and interprets the exit code to determine whether drift exists. Uses `set +e` / `set -e` around the plan command to capture the exit code without causing an immediate script failure. Sets an output variable `driftDetected` (true/false) on the step named `driftCheck` for potential downstream use. Prints the full drift plan output when drift is detected.

---

## 6. OIDC Authentication Setup

All pipelines authenticate to Azure using Workload Identity Federation (OIDC). This eliminates stored client secrets. The decision and rationale are documented in `docs/adr/006-cicd-auth.md`.

### How It Works

Azure DevOps issues a short-lived OIDC token for the pipeline run. That token is exchanged directly with Azure Entra ID for an access token scoped to the service principal's permissions. No secret is ever stored in Azure DevOps or the pipeline YAML.

The `AzureCLI@2` task handles the token exchange when configured with:

```yaml
addSpnToEnvironment: true
useWorkloadIdentityFederation: true
```

This injects `$servicePrincipalId` and `$tenantId` as environment variables inside the script. The pipeline then exports these for the Terraform AzureRM provider:

```bash
export ARM_USE_OIDC=true
export ARM_CLIENT_ID=$servicePrincipalId
export ARM_TENANT_ID=$tenantId
```

The AzureRM provider's OIDC support reads these variables and performs its own token exchange when making Azure API calls.

### Required Service Connections

The following service connections must exist in your Azure DevOps project before the pipelines can run:

| Service Connection Name | Used By | Scope |
|---|---|---|
| `azure-terraform-oidc` | `environment-cd.yml` (all stages) | All three subscriptions or a single subscription with RBAC scoped per environment |
| `azure-dev` | `drift-check.yml` | Dev subscription / resource group |
| `azure-staging` | `drift-check.yml` | Staging subscription / resource group |
| `azure-prod` | `drift-check.yml` | Prod subscription / resource group |

### Creating a Service Connection with Workload Identity Federation

1. In Azure DevOps, go to **Project Settings > Service connections > New service connection**.
2. Select **Azure Resource Manager**.
3. Select **Workload Identity Federation (automatic)** — this is the recommended path. Azure DevOps creates the federated credential in Entra ID automatically.
   - If you need manual control, choose **Workload Identity Federation (manual)** and follow the steps below.
4. Select the subscription and, optionally, a resource group for scoping.
5. Name the connection exactly as listed in the table above (e.g. `azure-terraform-oidc`).
6. Grant access to all pipelines or restrict to specific pipeline files depending on your security posture.

### Manual Federated Credential Setup (if not using automatic)

If you chose the manual option or need to configure this from the Entra ID side:

1. In Azure Portal, navigate to **Entra ID > App registrations > <your app> > Certificates & secrets > Federated credentials**.
2. Add a new federated credential:
   - **Federated credential scenario:** Azure DevOps
   - **Organization:** your Azure DevOps organisation name
   - **Project:** your project name
   - **Entity type:** Environment (for environment-scoped deployments) or Branch
   - **Environment/Branch name:** the environment or branch (e.g. `prod`, `main`)
   - **Name:** a descriptive name (e.g. `ado-prod-deploy`)
3. Assign the service principal the necessary RBAC role. Minimum required:
   - `Contributor` on the subscription or resource group(s) being managed.
   - `Storage Blob Data Contributor` on the state storage account for backend access.

### Verifying the Service Connection

After creating the connection, use the **Verify** button in Azure DevOps to confirm the OIDC token exchange succeeds before running a full pipeline.

---

## 7. Environment Approval Gates Configuration

Azure DevOps environments (not to be confused with Azure environments) are defined under **Pipelines > Environments**. Approval gates are configured per environment in the Azure DevOps UI, not in the YAML.

### Current Gate Configuration

| Azure DevOps Environment | Approval Requirement |
|---|---|
| `dev` | None — deployment proceeds automatically |
| `staging` | Manual approval from any designated approver (1 approver required) |
| `prod` | Manual approval from 2 designated approvers |

These match the `environment:` values used in the `deployment` jobs in `environment-cd.yml`.

### Configuring Approval Gates

1. Navigate to **Pipelines > Environments** in Azure DevOps.
2. Select the environment (e.g. `staging`).
3. Click the three-dot menu > **Approvals and checks**.
4. Click **+** to add a check, then select **Approvals**.
5. Configure:
   - **Approvers:** add individual users or groups.
   - **Allow approvers to approve their own runs:** typically disabled for prod.
   - **Approval timeout:** set a reasonable timeout (e.g. 7 days) so stale runs do not block indefinitely.
   - **Instructions to approvers:** describe what they should verify before approving (e.g. "Review the plan artifact published in this run before approving.").
6. For `prod`, set **Minimum number of approvers required** to 2.

### Recommended Additional Checks

Beyond manual approvals, consider adding these checks on the `prod` environment:

- **Business hours check:** restrict deployments to a time window (e.g. 09:00–17:00 Monday–Friday).
- **Required template check:** ensure only the official CD pipeline YAML can trigger deployments to prod, preventing ad hoc runs.
- **Exclusive lock:** prevents concurrent deployments to the same environment if two runs overlap.

### How Approval Gates Interact with the Plan Artifact

The plan artifact is published during the **Plan job**, which runs before the approval gate is evaluated. When an approver receives the notification, the exact `tfplan` binary that will be applied is already frozen as an artifact. Approvers should download and review `terraform-plan-<env>` before approving. There is no window between approval and apply during which the plan could change.

---

## 8. Variable Groups and Secrets Management

### Pipeline-Level Variables (CD Pipeline)

The CD pipeline declares the following variables directly in YAML:

```yaml
variables:
  terraformVersion: '1.6.0'
  serviceConnection: 'azure-terraform-oidc'
  backendResourceGroup: 'rg-terraform-state'
  backendStorageAccount: 'stterraformstate'
```

These are non-secret configuration values safe to store in version control.

### Variable Groups

For values that should not be in YAML (subscription IDs, tenant IDs, feature flags that differ per environment, notification endpoints), use Azure DevOps Library variable groups.

**Creating a variable group:**

1. Go to **Pipelines > Library > Variable groups > + Variable group**.
2. Name the group (e.g. `terraform-dev`, `terraform-staging`, `terraform-prod`).
3. Add variables. Mark sensitive values (e.g. client IDs, storage keys) as secret using the lock icon.
4. Under **Pipeline permissions**, grant access to the pipelines that need the group.

**Referencing a variable group in YAML:**

```yaml
variables:
  - group: terraform-dev
  - name: terraformVersion
    value: '1.6.0'
```

**Recommended variable group contents per environment:**

| Variable | Secret | Description |
|---|---|---|
| `ARM_SUBSCRIPTION_ID` | No | Azure subscription ID for the environment |
| `TF_VAR_notification_email` | No | Email for alerts provisioned by Terraform |
| `TF_VAR_some_api_key` | Yes | Any secret value passed as a Terraform variable |

### Secrets That Are Never Needed

Because the pipelines use OIDC, the following values are intentionally absent from all variable groups and YAML:

- Client secrets / passwords
- Storage account access keys (backend access goes through Entra ID RBAC)
- SAS tokens

Do not add these to variable groups. If a secret exists, verify whether OIDC can replace it before storing it.

### Passing Terraform Variables as Secrets

If a Terraform variable must be a secret (e.g. an API key provisioned into a resource), the recommended pattern is:

1. Store the value as a secret variable in a variable group.
2. Pass it to Terraform via the `TF_VAR_` prefix convention:

```yaml
- task: AzureCLI@2
  env:
    TF_VAR_my_secret: $(mySecretVariableFromGroup)
  inputs:
    inlineScript: |
      terraform apply -var-file=prod.tfvars -out=tfplan
```

This avoids writing the secret to the command line (where it would appear in logs) and uses the environment variable injection path that Terraform scans automatically.

---

## 9. Pipeline Customization Guide

### Changing the Terraform Version

In `environment-cd.yml`, update the `terraformVersion` variable:

```yaml
variables:
  terraformVersion: '1.9.0'
```

In `module-ci.yml`, the `TerraformInstaller@1` tasks use `terraformVersion: 'latest'`. To pin a version in CI, change each task:

```yaml
- task: TerraformInstaller@1
  inputs:
    terraformVersion: '1.9.0'
```

Consider aligning the version used in CI with the version constraint in your root `terraform` block.

### Changing the Terraform-docs Version

In `module-ci.yml`, the DocsCheck stage downloads terraform-docs v0.18.0 directly. To change the version, update the download URL in the install script:

```yaml
- script: |
    curl -sSLo terraform-docs.tar.gz \
      https://terraform-docs.io/dl/v0.19.0/terraform-docs-v0.19.0-linux-amd64.tar.gz
    tar -xzf terraform-docs.tar.gz terraform-docs
    chmod +x terraform-docs
    sudo mv terraform-docs /usr/local/bin/
    rm -f terraform-docs.tar.gz
  displayName: 'Install terraform-docs'
```

### Adding a New Module Validation Check

To add a check to the Module CI Validate stage, extend the loop in the `Validate All Modules` script step in `module-ci.yml`. For example, to add a `checkov` security scan:

```bash
# checkov scan
echo "--- checkov ---"
if ! checkov -d "$MODULE_DIR" --quiet; then
  echo "##vso[task.logissue type=error]Module '$MODULE_NAME' has checkov findings"
  FAILED=1
fi
```

Alternatively, add a new step to `templates/terraform-validate.yml` if the check should also apply to environment configurations.

### Running Only Specific Environments in CD

To skip an environment (e.g. to deploy only to dev for a hotfix), you can add a pipeline parameter and a condition:

```yaml
parameters:
  - name: deployToStaging
    type: boolean
    default: true

stages:
  - stage: Staging
    condition: and(succeeded(), eq('${{ parameters.deployToStaging }}', 'true'))
```

When manually triggering the pipeline, set the parameter to `false` to bypass the staging stage.

---

## 10. Adding a New Environment to CD

This section walks through adding a `pre-prod` environment between staging and prod as a concrete example.

### Step 1: Create the environment directory

```
environments/
  pre-prod/
    main.tf
    variables.tf
    outputs.tf
    pre-prod.tfvars
    backend.tf        (or rely on -backend-config flags)
```

### Step 2: Create the Azure DevOps environment

In Azure DevOps, go to **Pipelines > Environments > New environment**. Name it `pre-prod`. Configure approval gates as appropriate (see [Section 7](#7-environment-approval-gates-configuration)).

### Step 3: Create or verify the service connection

If `pre-prod` uses the same subscription as staging, the existing `azure-terraform-oidc` connection may be sufficient with appropriate RBAC scoping. If it is a separate subscription, create a new service connection following the steps in [Section 6](#6-oidc-authentication-setup).

### Step 4: Add the stage to `environment-cd.yml`

Insert the new stage between `Staging` and `Prod`. Update `Prod`'s `dependsOn` to reference `PreProd`.

```yaml
  - stage: PreProd
    displayName: 'Deploy to Pre-Prod'
    dependsOn: Staging
    jobs:
      - job: Plan
        displayName: 'Terraform Plan (Pre-Prod)'
        steps:
          - task: TerraformInstaller@1
            displayName: 'Install Terraform'
            inputs:
              terraformVersion: $(terraformVersion)

          - task: AzureCLI@2
            displayName: 'Terraform Init & Plan'
            inputs:
              azureSubscription: $(serviceConnection)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              addSpnToEnvironment: true
              useWorkloadIdentityFederation: true
              workingDirectory: '$(System.DefaultWorkingDirectory)/environments/pre-prod'
              inlineScript: |
                export ARM_USE_OIDC=true
                export ARM_CLIENT_ID=$servicePrincipalId
                export ARM_TENANT_ID=$tenantId

                terraform init \
                  -backend-config="resource_group_name=$(backendResourceGroup)" \
                  -backend-config="storage_account_name=$(backendStorageAccount)" \
                  -backend-config="container_name=tfstate" \
                  -backend-config="key=pre-prod.tfstate" \
                  -input=false

                terraform plan \
                  -var-file=pre-prod.tfvars \
                  -out=tfplan \
                  -input=false

          - task: PublishPipelineArtifact@1
            displayName: 'Publish Plan Artifact'
            inputs:
              targetPath: '$(System.DefaultWorkingDirectory)/environments/pre-prod/tfplan'
              artifactName: 'pre-prod-plan'

      - deployment: Apply
        displayName: 'Terraform Apply (Pre-Prod)'
        dependsOn: Plan
        environment: 'pre-prod'
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: 'pre-prod-plan'
                  displayName: 'Download Plan Artifact'

                - task: TerraformInstaller@1
                  displayName: 'Install Terraform'
                  inputs:
                    terraformVersion: $(terraformVersion)

                - task: AzureCLI@2
                  displayName: 'Terraform Init & Apply'
                  inputs:
                    azureSubscription: $(serviceConnection)
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    addSpnToEnvironment: true
                    useWorkloadIdentityFederation: true
                    workingDirectory: '$(System.DefaultWorkingDirectory)/environments/pre-prod'
                    inlineScript: |
                      export ARM_USE_OIDC=true
                      export ARM_CLIENT_ID=$servicePrincipalId
                      export ARM_TENANT_ID=$tenantId

                      terraform init \
                        -backend-config="resource_group_name=$(backendResourceGroup)" \
                        -backend-config="storage_account_name=$(backendStorageAccount)" \
                        -backend-config="container_name=tfstate" \
                        -backend-config="key=pre-prod.tfstate" \
                        -input=false

                      terraform apply \
                        $(Pipeline.Workspace)/pre-prod-plan/tfplan

  - stage: Prod
    displayName: 'Deploy to Production'
    dependsOn: PreProd       # <-- updated from Staging
```

### Step 5: Add the environment to drift detection

In `drift-check.yml`, add a new stage. Use `dependsOn: []` to keep it parallel with the others:

```yaml
  - stage: PreProdDriftCheck
    displayName: 'Pre-Prod Drift Check'
    dependsOn: []
    jobs:
      - job: DetectDrift
        displayName: 'Detect Drift - Pre-Prod'
        steps:
          - template: templates/drift-detection.yml
            parameters:
              workingDirectory: '$(System.DefaultWorkingDirectory)/environments/pre-prod'
              varFile: 'terraform.tfvars'
              serviceConnection: 'azure-pre-prod'
              environment: 'pre-prod'
```

Create the `azure-pre-prod` service connection in Azure DevOps if the environment uses a separate subscription.

---

## 11. Debugging Pipeline Failures

### Module CI Failures

**`terraform fmt -check` fails**

The log will show which module failed formatting. Fix locally:

```bash
terraform fmt modules/<module-name>
```

Verify: `terraform fmt -check modules/<module-name>` should exit 0.

**`terraform init -backend=false` fails**

Common causes:
- A provider source address is invalid or misspelled in `required_providers`.
- No network access from the agent to the Terraform registry (unlikely with Microsoft-hosted agents).
- A `required_version` constraint in the module conflicts with the installed Terraform version.

Check the init output in the pipeline log for the specific provider that failed.

**`terraform validate` fails**

The error output from `validate` is written directly to the log. Look for the `Error:` line, which includes the file and line number. Common causes: undeclared variables, incorrect argument names, type mismatches.

**tflint fails**

Check whether a `.tflint.hcl` file exists at the repo root and is correctly configured. Run tflint locally:

```bash
tflint --init --config=.tflint.hcl
tflint --chdir=modules/<name> --config=.tflint.hcl
```

**DocsCheck fails**

The pipeline prints a diff between the current README and the expected output. Regenerate the README:

```bash
terraform-docs markdown table modules/<name> > modules/<name>/README.md
```

### CD Pipeline Failures

**`Terraform Init` fails**

- Verify the service connection name matches the `serviceConnection` variable exactly (case-sensitive).
- Verify the storage account and resource group exist.
- Verify the service principal has `Storage Blob Data Contributor` on the storage account.
- Check whether the state key (`dev.tfstate`, etc.) is locked by a previous failed run. Navigate to the storage account in the Azure portal, find the blob, and break the lease if necessary.

**`Terraform Plan` fails**

- Authentication errors: confirm `ARM_USE_OIDC=true`, `ARM_CLIENT_ID`, and `ARM_TENANT_ID` are being set. Expand the `AzureCLI@2` task in the log and look for the environment variable injection section.
- Provider errors: a resource type or argument may not be supported in the pinned provider version. Check the `required_providers` version constraints.
- Variable errors: a variable required by the configuration may not be present in the `.tfvars` file.

**`Terraform Apply` fails**

- Check whether Azure rejected the resource creation (quota limits, policy violations, naming conflicts). The error from the Azure API is surfaced directly in the plan output.
- If the plan artifact was published but apply is re-running with a different init, there may be a provider version mismatch between plan and apply agents. Both stages install the same `terraformVersion`, so this is rare but possible if the cache is stale — delete the cached `.terraform` directory by invalidating the `Cache@2` key.

**Approval gate not appearing**

- Confirm the `deployment` job's `environment:` value exactly matches the environment name in Azure DevOps (case-sensitive).
- Confirm at least one approval check is configured on the environment. If no checks exist, the deployment proceeds without waiting.

**OIDC token exchange failures**

The error typically appears as `AADSTS` error codes in the Azure CLI output. Common causes:

| Error | Cause | Fix |
|---|---|---|
| `AADSTS70021` | No federated credential matched the token | Verify the federated credential's subject claim matches the pipeline's issuer (org/project/entity) |
| `AADSTS700016` | Application not found in tenant | Wrong `ARM_CLIENT_ID` or wrong tenant |
| `AADSTS50005` | Resource not configured for OIDC | Federated credential not yet saved or misconfigured |

To inspect the token being sent, temporarily add `echo $ARM_CLIENT_ID $ARM_TENANT_ID` to the inline script to confirm the injected values are correct.

### Drift Detection Failures

**Pipeline fails with exit code other than 0 or 2**

`terraform plan` itself failed (not drift — a genuine error). Check whether the state file is accessible and whether the service connection has read permissions on all resources in the environment.

**Pipeline succeeds but drift is not being flagged when you expect it**

Confirm `always: true` is set in the schedule definition. Without it, the pipeline skips if no code has changed. Also confirm the `terraform.tfvars` file referenced in the template parameters contains all required variables.

---

## 12. Pipeline Security Considerations

### No Stored Secrets

All pipeline-to-Azure authentication uses OIDC (Workload Identity Federation). Client secrets are not stored anywhere in Azure DevOps, pipeline YAML, or variable groups. If a client secret currently exists for any service principal used by these pipelines, rotate it to expired and remove it.

### Least-Privilege Service Principals

Each service connection should have the minimum RBAC required:

- **CD pipeline (`azure-terraform-oidc`):** `Contributor` on the managed subscriptions or resource groups, plus `Storage Blob Data Contributor` on the state storage account.
- **Drift check connections (`azure-dev`, `azure-staging`, `azure-prod`):** `Reader` on the managed subscriptions (sufficient for `terraform plan` without apply) plus `Storage Blob Data Reader` on the state storage account. If read-only access is used, set `ARM_SKIP_PROVIDER_REGISTRATION=true` to avoid a registration call that requires broader permissions.

Review RBAC assignments periodically. Remove any `Owner` or `User Access Administrator` assignments that are not strictly necessary.

### Branch Protection and Required Pipeline Status

Configure branch policies on `main` in Azure DevOps:

1. **Require a minimum number of reviewers** (at least 1) on PRs.
2. **Require the Module CI pipeline to pass** before merging: Add a build validation policy pointing to `module-ci.yml`. This ensures no module change reaches `main` without passing fmt, validate, lint, test, and docs checks.
3. **Restrict who can push directly** to `main`. All changes must go through a PR.

### Plan Artifact Integrity

The plan artifact is published before the approval gate. This is by design — approvers should be reviewing a fixed, auditable plan. However, this also means:

- Do not allow pipeline runs to be re-triggered after approval without re-planning. A new run always produces a new plan artifact.
- The plan binary is environment-specific and not portable. Attempting to apply a dev plan artifact against the staging environment will fail because the backend key and state do not match.

### Secret Scanning

Ensure that no Terraform variable values containing secrets are written to `.tfvars` files committed to the repository. Use variable groups with secret variables and the `TF_VAR_` injection pattern described in [Section 8](#8-variable-groups-and-secrets-management). Configure Azure DevOps secret scanning or a pre-commit hook (e.g. `detect-secrets` or `gitleaks`) to catch accidental secret commits.

### Pipeline YAML Permissions

The `azure-terraform-oidc` service connection grants significant access to Azure. Restrict which pipelines can use it:

In the service connection settings, under **Security**, set **Pipeline permissions** to allow only the specific pipeline file (`pipelines/environment-cd.yml`) rather than all pipelines in the project. This prevents a malicious or accidentally created pipeline from using the production credentials.

### Audit Log

Azure DevOps records all pipeline runs, approvals, and service connection usage in the **Audit log** under Organisation Settings. Enable audit log streaming to a Log Analytics workspace or SIEM to retain these records beyond the default retention period and to alert on unexpected pipeline runs targeting production environments.
