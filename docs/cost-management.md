# Cost Management Guide

This guide covers cost visibility, optimization, governance, and review processes for the Azure infrastructure platform. The project deploys AKS, Storage Account, Key Vault, Virtual Network, Log Analytics workspace, and Fabric Capacity resources across dev, staging, and production environments.

---

## Table of Contents

1. [Cost Overview by Resource Type](#1-cost-overview-by-resource-type)
2. [Tagging Strategy for Cost Attribution](#2-tagging-strategy-for-cost-attribution)
3. [Using Infracost for Pre-Deployment Estimates](#3-using-infracost-for-pre-deployment-estimates)
4. [Azure Cost Management Setup and Dashboards](#4-azure-cost-management-setup-and-dashboards)
5. [Cost Optimization Strategies per Service](#5-cost-optimization-strategies-per-service)
6. [Dev/Test vs Production Cost Differences](#6-devtest-vs-production-cost-differences)
7. [Budget Alerts and Automation](#7-budget-alerts-and-automation)
8. [Reserved Instances and Savings Plans](#8-reserved-instances-and-savings-plans)
9. [Cost Governance with Azure Policy](#9-cost-governance-with-azure-policy)
10. [Monthly Cost Review Process](#10-monthly-cost-review-process)
11. [Decommissioning Unused Resources](#11-decommissioning-unused-resources)

---

## 1. Cost Overview by Resource Type

### Estimated Monthly Costs (Dev Environment)

| Resource | SKU / Config | Estimated Cost |
|---|---|---|
| AKS Cluster | Standard tier, Standard_B2s nodes (1-3) | $60-120 |
| Storage Account | Standard LRS, StorageV2 | $5-15 |
| Key Vault | Standard SKU | $1-5 |
| Virtual Network | Inbound/outbound data transfer | $5-20 |
| Log Analytics | PerGB2018, 30-day retention | $10-40 |
| Fabric Capacity | F2-F8 SKU (when running) | $50-150 |
| Private Endpoints | Per endpoint + data processed | $10-20 |
| **Total (dev)** | | **~$150-300/month** |

### Cost Drivers by Percentage

- AKS compute (node VMs) accounts for roughly 40-50% of total spend
- Fabric Capacity is the most variable line item; pausing it when idle eliminates most of its cost
- Log Analytics costs scale directly with data ingestion volume
- Storage and Key Vault costs are relatively fixed and minor at dev scale

### AKS Pricing Components

AKS billing has several distinct components:

- **Control plane**: Free tier has no SLA; Standard tier costs ~$73/month per cluster and provides a 99.5% uptime SLA; Premium tier adds ~$146/month with 99.95% SLA and longer support windows
- **Node VMs**: Billed at standard VM rates; `Standard_B2s` (2 vCPU, 4 GiB) costs approximately $30-35/month per node
- **OS disk**: 30 GiB managed disk per node at ~$2.40/month per node
- **Load balancer**: Standard Load Balancer at ~$18/month plus data processing fees
- **Outbound data transfer**: First 100 GiB/month free, then $0.087/GiB

---

## 2. Tagging Strategy for Cost Attribution

All resources in this project are tagged consistently via the `common_tags` local in each environment's `main.tf`. Tags flow through every module's `tags` variable.

### Standard Tags

```hcl
# environments/dev/main.tf
locals {
  common_tags = merge(
    {
      environment = var.environment   # "dev", "staging", "prod"
      project     = var.project       # "platform"
      managed_by  = "terraform"
      owner       = var.owner         # "platform-team"
      cost_center = var.cost_center   # "infrastructure"
    },
    var.tags
  )
}
```

### Tag Definitions

| Tag | Purpose | Example Values |
|---|---|---|
| `project` | Groups all resources belonging to this platform | `platform` |
| `environment` | Separates dev/staging/prod cost buckets | `dev`, `staging`, `prod` |
| `owner` | Identifies the team accountable for costs | `platform-team` |
| `cost_center` | Maps to finance/billing department code | `infrastructure` |
| `managed_by` | Distinguishes Terraform-managed from manual resources | `terraform` |

### Cost Attribution in Azure Cost Management

With tags applied, use the following filters in Azure Cost Management to slice costs:

- **By environment**: Filter on `environment` tag to compare dev vs prod spend
- **By team**: Filter on `owner` tag to attribute costs to the platform team
- **By cost center**: Filter on `cost_center` to roll up into finance reports
- **Untagged resources**: Create a query for resources missing required tags; untagged resources cannot be attributed and should be treated as a governance violation

### Enforcing Tags with Policy

The `azure-policy` module can enforce required tags. See [Section 9](#9-cost-governance-with-azure-policy) for policy configuration details.

---

## 3. Using Infracost for Pre-Deployment Estimates

Infracost integrates directly into the Terraform workflow via the `make cost` target, providing cost estimates before any resources are created or changed.

### Running a Cost Estimate

```bash
# Estimate costs for the dev environment
make cost ENV=dev

# Estimate costs for staging
make cost ENV=staging

# Estimate costs for production
make cost ENV=prod
```

The `make cost` target runs:

```makefile
cost:
    infracost breakdown --path=$(ENV_DIR)
```

This reads the Terraform configuration in `environments/$(ENV)` and produces a detailed breakdown of monthly costs per resource.

### Infracost Setup

```bash
# Install Infracost
curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh

# Authenticate (free API key)
infracost auth login

# Verify installation
infracost --version
```

### Infracost Configuration File

Create `infracost.yml` at the project root to configure additional options:

```yaml
version: 0.1

projects:
  - path: environments/dev
    name: platform-dev
    terraform_var_files:
      - dev.tfvars

  - path: environments/staging
    name: platform-staging
    terraform_var_files:
      - staging.tfvars

  - path: environments/prod
    name: platform-prod
    terraform_var_files:
      - prod.tfvars
```

### Comparing Environments

```bash
# Generate JSON output for comparison
infracost breakdown --path=environments/dev --format=json --out-file=/tmp/dev.json
infracost breakdown --path=environments/prod --format=json --out-file=/tmp/prod.json

# Diff between environments
infracost diff --path=environments/dev --compare-to=/tmp/dev.json
```

### CI/CD Integration

Add an Infracost step to your pipeline to comment cost estimates on pull requests:

```yaml
# pipelines/cost-estimate.yml (Azure DevOps example)
- task: Bash@3
  displayName: Infracost estimate
  inputs:
    targetType: inline
    script: |
      infracost breakdown \
        --path=environments/$(ENV) \
        --format=json \
        --out-file=infracost-$(ENV).json
      infracost output \
        --path=infracost-$(ENV).json \
        --format=table
```

### Reading the Output

Key fields in Infracost output:

- **Monthly cost**: Projected spend based on current configuration
- **Diff**: Change in cost versus the current deployed state (when using `infracost diff`)
- **Resource breakdown**: Per-resource line items matching your Terraform modules

Any resource showing a cost spike of more than 20% vs the previous estimate should be reviewed before applying.

---

## 4. Azure Cost Management Setup and Dashboards

### Enabling Cost Management

Cost Management is enabled by default for all Azure subscriptions. Navigate to:

**Azure Portal > Cost Management + Billing > Cost Management**

Scope your view to the subscription or a specific resource group (e.g., `rg-platform-dev-eastus2`).

### Recommended Dashboard Views

#### Environment Cost Breakdown

1. Go to **Cost Management > Cost analysis**
2. Set scope to the subscription
3. Group by: `Tag: environment`
4. Time range: Current month
5. Save as a shared view named "Cost by Environment"

#### Resource Type Breakdown

1. Group by: `Resource type`
2. Filter: `Tag: project = platform`
3. This shows which Azure service categories (Microsoft.ContainerService, Microsoft.Storage, etc.) consume the most budget

#### Daily Spend Trend

1. Select **Accumulated cost** view
2. Group by: `Tag: environment`
3. Set granularity to **Daily**
4. This highlights unexpected spikes in daily spend

### Cost Allocation Rules

Configure cost allocation to distribute shared resource costs (VNet, Log Analytics) across teams:

1. Navigate to **Cost Management > Cost allocation rules**
2. Create a rule to split shared resource group costs by `cost_center` tag
3. Set distribution basis to **Equally** or **Proportional to direct costs**

### Exporting Cost Data

For custom reporting or finance integration:

1. Go to **Cost Management > Exports**
2. Create a scheduled export:
   - Export type: **Monthly cost**
   - Storage account: your platform storage account
   - Container: `cost-exports`
   - Format: CSV
3. Export files land in the storage account and can be queried with Azure Data Explorer or imported into Power BI

---

## 5. Cost Optimization Strategies per Service

### AKS: Right-Sizing, Autoscaler, and Spot Instances

#### Control Plane SKU Selection

The project defaults to `sku_tier = "Standard"`. In dev, consider `"Free"` to eliminate the ~$73/month control plane charge:

```hcl
# modules/aks-cluster/variables.tf
# dev: use "Free"; staging/prod: use "Standard" or "Premium"
variable "sku_tier" {
  default = "Standard"
}
```

**Decision guide:**
- `Free`: Dev/test workloads, no SLA required, saves ~$73/month
- `Standard`: Staging and production, 99.5% uptime SLA
- `Premium`: Production with long-term support (LTS) Kubernetes versions and 99.95% SLA

#### Right-Sizing Nodes

The default node VM size is `Standard_B2s` (2 vCPU, 4 GiB RAM). Review actual workload resource requests and limits before sizing:

```bash
# Check current node utilization
kubectl top nodes

# Check pod resource usage
kubectl top pods --all-namespaces
```

Common size progression:
- `Standard_B2s`: 2 vCPU / 4 GiB — dev baseline, ~$30/month/node
- `Standard_B4ms`: 4 vCPU / 16 GiB — medium workloads, ~$62/month/node
- `Standard_D4s_v5`: 4 vCPU / 16 GiB — production general purpose, ~$140/month/node

#### Cluster Autoscaler

The module supports `min_count` and `max_count` per node pool. Set narrow bounds in dev to avoid idle over-provisioning:

```hcl
default_node_pool = {
  min_count = 1   # dev: keep at 1; prod: set to match baseline load
  max_count = 3   # dev: cap low; prod: set to handle peak
  vm_size   = "Standard_B2s"
}
```

Review autoscaler logs weekly in dev to detect nodes that never scale down, which indicates workloads are not correctly specifying resource requests.

#### Spot Instances for User Node Pools

For stateless or batch workloads in the `additional_node_pools`, use Azure Spot VMs to reduce compute cost by 60-80%:

```hcl
additional_node_pools = {
  spot-workers = {
    vm_size    = "Standard_D4s_v5"
    min_count  = 0
    max_count  = 10
    node_labels = {
      "kubernetes.azure.com/scalesetpriority" = "spot"
    }
    node_taints = [
      "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
    ]
  }
}
```

Spot nodes can be evicted with 30 seconds notice. Only deploy workloads with `tolerations` for the spot taint and that handle graceful shutdown.

#### Shutting Down AKS in Dev After Hours

Scale the node pool to zero outside business hours using Azure Automation or a scheduled pipeline:

```bash
# Scale down (evening)
az aks nodepool scale \
  --resource-group rg-platform-dev-eastus2 \
  --cluster-name aks-platform-dev \
  --name system \
  --node-count 0

# Scale up (morning)
az aks nodepool scale \
  --resource-group rg-platform-dev-eastus2 \
  --cluster-name aks-platform-dev \
  --name system \
  --node-count 1
```

Note: The system node pool `min_count` must be set to 0 in the Terraform config and the cluster must have the autoscaler disabled for manual scaling.

---

### Storage: Lifecycle Policies, Access Tiers, Reserved Capacity

#### Access Tiers

The module uses `Standard` tier with `StorageV2` kind, which supports hot, cool, cold, and archive blob access tiers. Set appropriate tiers for data age:

| Tier | Use Case | Storage Cost | Access Cost |
|---|---|---|---|
| Hot | Frequently accessed data | ~$0.018/GiB | Low |
| Cool | Infrequently accessed, 30-day minimum | ~$0.01/GiB | Higher |
| Cold | Rarely accessed, 90-day minimum | ~$0.0045/GiB | Higher |
| Archive | Long-term retention, 180-day minimum | ~$0.00099/GiB | Highest, rehydration hours |

#### Lifecycle Management Rules

The module exposes `lifecycle_rules` to automate tier transitions. Configure these in your environment module call:

```hcl
module "storage" {
  source = "../../modules/storage-account"

  lifecycle_rules = [
    {
      name                       = "tier-old-blobs"
      enabled                    = true
      prefix_match               = ["logs/", "backups/"]
      tier_to_cool_after_days    = 30
      tier_to_archive_after_days = 90
      delete_after_days          = 365
    },
    {
      name              = "delete-temp-uploads"
      enabled           = true
      prefix_match      = ["tmp/"]
      delete_after_days = 7
    }
  ]
}
```

#### Soft Delete Retention Cost Impact

The module defaults to 30-day soft delete retention for blobs and containers. Soft-deleted blobs still incur storage charges at the blob's current tier. For dev environments where data changes frequently, reduce retention:

```hcl
blob_soft_delete_retention_days      = 7   # dev
container_soft_delete_retention_days = 7   # dev
```

For production, keep 30 days or longer to meet recovery objectives.

#### Replication Type

The module defaults to `LRS` (Locally Redundant Storage). Evaluate replication needs per environment:

- `LRS`: Single datacenter, lowest cost — suitable for dev and non-critical data
- `ZRS`: Zone redundant, ~25% premium over LRS — suitable for staging
- `GRS`/`RAGRS`: Geo-redundant, ~100% premium over LRS — required for business-critical production data

#### Reserved Capacity

For predictable storage volumes exceeding 100 TiB, consider Azure Storage Reserved Capacity for up to 38% savings on blob storage costs. Commitments are available for 1-year and 3-year terms.

---

### Key Vault: Transaction-Based Pricing Considerations

Key Vault uses a transaction-based pricing model. Understanding what generates transactions helps avoid unexpected costs at scale.

#### Pricing Structure

| SKU | Vault operations | Certificate operations | Advanced operations |
|---|---|---|---|
| Standard | $0.03 per 10,000 transactions | $3/month per certificate | N/A |
| Premium | $0.03 per 10,000 transactions | $3/month + HSM operations | HSM-protected keys available |

The module defaults to `sku_name = "standard"`. Only use `premium` if HSM-protected keys are required.

#### Transaction Sources

Each of the following generates billable transactions:

- Secret `GET` operations (retrieving a secret value)
- Key `WRAP`/`UNWRAP` operations (customer-managed key encryption)
- Certificate renewal and rotation
- Diagnostic log reads

#### Reducing Transaction Volume

- **Cache secrets in application memory**: Do not call Key Vault on every request; load secrets at startup and refresh on a timer (e.g., every 30 minutes)
- **Use the Key Vault references feature**: Azure App Service and Azure Functions support Key Vault references, which cache values automatically
- **Batch secret reads**: Load all required secrets in a single initialization pass rather than individual calls per secret
- **Limit diagnostic logging verbosity**: Sending every audit event to Log Analytics generates additional read transactions

#### Customer-Managed Key (CMK) Cost Impact

The module supports CMK for Storage Account encryption (`cmk_key_vault_key_id`). CMK generates a `WRAP`/`UNWRAP` key operation on every blob upload and download. At high data throughput, these transactions can add meaningfully to Key Vault costs. Monitor transaction volume in Key Vault metrics after enabling CMK.

---

### Log Analytics: Retention and Daily Cap Settings

Log Analytics costs scale with data ingestion volume and retention period. This is the service most likely to produce surprise costs when verbose logging is enabled.

#### Pricing Model

The module uses `sku = "PerGB2018"` (pay-per-GB), which costs approximately $2.30/GiB ingested in East US 2. Ingested data is retained free for 31 days; extended retention beyond 31 days costs $0.10/GiB/month up to 730 days.

#### Setting a Daily Quota

The module exposes `daily_quota_gb`. Set this in dev to cap runaway ingestion costs:

```hcl
module "log_analytics" {
  source = "../../modules/log-analytics"

  retention_in_days = 30    # minimum; keep low in dev
  daily_quota_gb    = 1     # dev: 1 GiB/day cap (~$70/month max on ingestion)
                            # staging: 5
                            # prod: -1 (unlimited, rely on budget alerts instead)
}
```

When the daily quota is reached, ingestion stops for the remainder of the day and resumes the next day at midnight UTC. Set a budget alert (see Section 7) to notify before the cap is hit.

#### Retention Configuration

```hcl
# dev: minimum retention, lowest cost
retention_in_days = 30

# staging: moderate retention for debugging
retention_in_days = 60

# prod: extended retention for audit and compliance
retention_in_days = 90   # or up to 730 for compliance requirements
```

#### Identifying High-Volume Log Sources

Use the following KQL query in Log Analytics to find which tables consume the most ingested data:

```kusto
Usage
| where TimeGenerated > ago(7d)
| summarize IngestedGB = sum(Quantity) / 1024 by DataType
| order by IngestedGB desc
| take 20
```

Common high-volume sources to tune:

- **AKS container logs**: Limit verbose application logging at the container level; use `ContainerLogV2` schema which is more efficient than the legacy `ContainerLog`
- **Azure Activity Logs**: These are free to send to Log Analytics from the Diagnostics settings but count toward ingestion if forwarded to a workspace
- **Key Vault audit logs**: Each transaction generates an audit log entry; reduce diagnostic verbosity if not required

#### Commitment Tier Pricing

If ingestion consistently exceeds 100 GiB/day, switch from `PerGB2018` to a `CapacityReservation` SKU for discounts of 15-30%:

| Commitment Tier | Daily Volume | Effective Price per GiB |
|---|---|---|
| PerGB2018 | Any | ~$2.30 |
| 100 GiB/day | ~3 TiB/month | ~$1.96 |
| 200 GiB/day | ~6 TiB/month | ~$1.84 |
| 500 GiB/day | ~15 TiB/month | ~$1.61 |

---

### Fabric Capacity: SKU Selection and Pause/Resume

Microsoft Fabric Capacity is charged per hour based on the selected SKU. It is the highest-impact resource to manage actively.

#### SKU Pricing (East US 2, approximate)

| SKU | Compute Units | Approx. Hourly | Approx. Monthly (24x7) |
|---|---|---|---|
| F2 | 2 CU | $0.36 | ~$265 |
| F4 | 4 CU | $0.72 | ~$525 |
| F8 | 8 CU | $1.44 | ~$1,050 |
| F16 | 16 CU | $2.88 | ~$2,100 |
| F32 | 32 CU | $5.76 | ~$4,200 |

The module supports `F2` through `F2048`. Start with the smallest SKU that handles workload throughput, then scale up as needed.

#### Pause/Resume Strategy

Fabric Capacity can be paused when not in use and billing stops immediately. Implement a schedule:

```bash
# Pause Fabric capacity (run at end of business day)
az fabric capacity suspend \
  --resource-group rg-platform-dev-eastus2 \
  --capacity-name fabric-platform-dev

# Resume Fabric capacity (run at start of business day)
az fabric capacity resume \
  --resource-group rg-platform-dev-eastus2 \
  --capacity-name fabric-platform-dev
```

**Pause/resume savings estimate (F2 SKU):**
- Always on: ~$265/month
- 10 hours/day, 5 days/week: ~$75/month (72% savings)
- On-demand only: Near zero when paused

#### SKU Scaling

Scale up for batch processing windows and down afterward:

```bash
# Scale up for heavy workload
az fabric capacity update \
  --resource-group rg-platform-dev-eastus2 \
  --capacity-name fabric-platform-dev \
  --sku-name F16

# Scale back down after workload completes
az fabric capacity update \
  --resource-group rg-platform-dev-eastus2 \
  --capacity-name fabric-platform-dev \
  --sku-name F2
```

Terraform manages the SKU via the `sku` variable. For dynamic scaling, use the Azure CLI or Azure Automation outside of Terraform state to avoid drift.

---

## 6. Dev/Test vs Production Cost Differences

### Configuration Comparison

| Setting | Dev | Staging | Production |
|---|---|---|---|
| AKS SKU tier | `Free` | `Standard` | `Standard` or `Premium` |
| AKS node VM size | `Standard_B2s` | `Standard_B4ms` | `Standard_D4s_v5` or larger |
| AKS node count | 1 min, 3 max | 2 min, 5 max | 3 min, 10+ max |
| AKS availability zones | Optional (1 zone) | 2 zones | 3 zones |
| Storage replication | `LRS` | `ZRS` | `GRS` or `RAGRS` |
| Storage soft delete retention | 7 days | 14 days | 30 days |
| Key Vault SKU | `standard` | `standard` | `standard` or `premium` |
| Log Analytics retention | 30 days | 60 days | 90-365 days |
| Log Analytics daily cap | 1 GiB | 5 GiB | Unlimited (alert-based) |
| Fabric Capacity SKU | `F2` (paused when idle) | `F4` | `F8`+ |
| Private Endpoints | Optional | Required | Required |
| Estimated monthly cost | $150-300 | $400-700 | $1,000-2,500+ |

### Dev-Specific Cost Controls

- Enable the AKS `Free` control plane SKU to save $73/month
- Scale AKS node pools to zero during non-working hours
- Pause Fabric Capacity outside of active development sessions
- Use `LRS` storage with minimum retention settings
- Set a Log Analytics daily cap of 1-2 GiB
- Avoid deploying private endpoints unless testing private connectivity specifically

### Staging-Specific Considerations

Staging should mirror production architecture to catch environment-specific issues, but can use smaller SKUs. The primary cost differences from production:

- Smaller AKS node VM sizes and lower node counts
- ZRS instead of GRS/RAGRS for storage
- Shorter Log Analytics retention
- Lower Fabric Capacity SKU

### Production Cost Baseline

Production costs are driven by:

- Uptime requirements (no scale-to-zero, minimum node floors)
- Data redundancy requirements (ZRS/GRS storage, multi-zone AKS)
- Longer retention periods for audit and compliance
- Premium tiers for SLA commitments (AKS Standard/Premium control plane)
- Larger VM sizes to handle production traffic volumes

---

## 7. Budget Alerts and Automation

### Creating Budgets in Azure Cost Management

Navigate to **Cost Management > Budgets > Add**.

#### Dev Environment Budget

```
Name: platform-dev-monthly
Scope: Resource Group - rg-platform-dev-eastus2
Budget amount: $350
Reset period: Monthly
Expiration: Set to end of fiscal year

Alert conditions:
  - 80% of budget ($280) -> Email platform-team
  - 100% of budget ($350) -> Email platform-team + manager
  - 110% of forecasted spend -> Email platform-team
```

#### Production Environment Budget

```
Name: platform-prod-monthly
Scope: Resource Group - rg-platform-prod-eastus2
Budget amount: $2,500
Reset period: Monthly

Alert conditions:
  - 70% of budget ($1,750) -> Email platform-team
  - 90% of budget ($2,250) -> Email platform-team + manager + finance
  - 100% of budget ($2,500) -> PagerDuty or Teams webhook
```

### Automating Budget Responses

Create an Azure Action Group to trigger automation when budget thresholds are hit:

1. Go to **Monitor > Action Groups > Create**
2. Add actions:
   - **Email**: Notify platform-team distribution list
   - **Webhook**: Call an Azure Function or Logic App for automated response
   - **Azure Automation Runbook**: Trigger a runbook to scale down dev resources

#### Example: Auto-Scale-Down Runbook

When the dev budget hits 100%, trigger an Azure Automation runbook:

```powershell
# Runbook: Scale-Down-Dev-Environment.ps1
Connect-AzAccount -Identity

# Scale AKS to minimum
$aksCluster = Get-AzAksCluster -ResourceGroupName "rg-platform-dev-eastus2" -Name "aks-platform-dev"
Set-AzAksCluster -ResourceGroupName "rg-platform-dev-eastus2" -Name "aks-platform-dev" -NodeCount 1

# Suspend Fabric Capacity
az fabric capacity suspend `
  --resource-group rg-platform-dev-eastus2 `
  --capacity-name fabric-platform-dev

Write-Output "Dev environment scaled down due to budget threshold."
```

### Infracost Budget Policy in CI

Fail CI pipelines when a change would increase costs beyond a threshold:

```bash
# In CI pipeline
infracost breakdown \
  --path=environments/prod \
  --format=json \
  --out-file=infracost-current.json

# Fail if monthly cost increase exceeds $200
infracost comment github \
  --path=infracost-current.json \
  --github-token=$GITHUB_TOKEN \
  --pull-request=$PR_NUMBER \
  --behavior=update \
  --policy-path=infracost-policy.rego
```

`infracost-policy.rego`:

```rego
package infracost

deny[msg] {
  diff := input.projects[_].diff.totalMonthlyCost
  to_number(diff) > 200
  msg := sprintf("Cost increase of $%v/month exceeds $200 threshold", [diff])
}
```

---

## 8. Reserved Instances and Savings Plans

### Azure Savings Plans for Compute

Azure Savings Plans commit to a fixed hourly spend on compute in exchange for up to 65% discount versus pay-as-you-go pricing. Savings Plans apply automatically to eligible compute usage including AKS node VMs.

**Eligibility assessment:**
- Evaluate after running in production for 3+ months to establish a stable baseline
- Use the Azure Advisor recommendations tab for automated savings plan suggestions
- Savings Plans are flexible across VM series and regions, unlike Reserved Instances

**Commitment tiers (example for $100/hour compute baseline):**
- 1-year Savings Plan: ~35% savings → ~$35/hour effective rate
- 3-year Savings Plan: ~65% savings → ~$35/hour effective rate

### Reserved Instances for AKS Nodes

If node VM sizes are stable and predictable, Reserved VM Instances provide deeper discounts than Savings Plans for specific VM sizes:

| VM Size | Pay-as-you-go | 1-Year RI | 3-Year RI |
|---|---|---|---|
| Standard_B2s | ~$0.042/hour | ~$0.025/hour (-40%) | ~$0.018/hour (-57%) |
| Standard_D4s_v5 | ~$0.192/hour | ~$0.115/hour (-40%) | ~$0.082/hour (-57%) |

**When to use Reserved Instances vs Savings Plans:**
- Use Reserved Instances when VM size, region, and OS are fixed for 1-3 years
- Use Savings Plans when workloads may shift VM families or regions

### Reserved Capacity for Storage

For storage accounts with consistent data volumes exceeding 100 TiB:

- 1-year reserved capacity: ~18% discount on blob storage
- 3-year reserved capacity: ~38% discount on blob storage

Purchase through **Azure Portal > Reservations > Add > Azure Blob Storage Reserved Capacity**.

### Reserved Capacity for Log Analytics

Log Analytics Commitment Tiers are a form of reservation. If ingestion consistently exceeds 100 GiB/day, switch the workspace SKU from `PerGB2018` to `CapacityReservation` and select the appropriate tier in the `log-analytics` module:

```hcl
module "log_analytics" {
  source = "../../modules/log-analytics"

  sku               = "CapacityReservation"
  # reservation_capacity_in_gb_per_day = 100  # set via azurerm provider
  retention_in_days = 90
}
```

### Governance: Reservation Purchasing Policy

- Only the platform team lead or finance representative should purchase reservations
- All reservations should be scoped to the subscription or a management group, not individual resource groups, to allow flexibility
- Review reservation utilization quarterly; unused reservations should be exchanged or cancelled

---

## 9. Cost Governance with Azure Policy

The `azure-policy` module in this project deploys Azure Policy definitions and assignments. Policies serve as the automated enforcement layer for cost governance.

### Recommended Cost Policies

#### 1. Require Cost Tags on All Resources

Enforce that all resources have the required cost tags (`environment`, `project`, `owner`, `cost_center`):

```hcl
module "policy_require_tags" {
  source = "../../modules/azure-policy"

  # Use built-in policy: "Require a tag on resources"
  # Policy definition ID: /providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99
  name         = "require-cost-tags"
  display_name = "Require cost attribution tags on all resources"
  scope        = "/subscriptions/${var.subscription_id}"

  parameters = {
    tagName = { value = "cost_center" }
  }
}
```

Repeat this policy assignment for each required tag key.

#### 2. Restrict Allowed VM Sizes

Prevent deployment of expensive VM sizes in dev and staging:

```hcl
# Built-in policy: "Allowed virtual machine size SKUs"
# Policy definition ID: /providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3

parameters = {
  listOfAllowedSKUs = {
    value = [
      "Standard_B2s",
      "Standard_B4ms",
      "Standard_D2s_v5",
      "Standard_D4s_v5"
    ]
  }
}
```

#### 3. Restrict Allowed Locations

Constrain all resources to the project's designated region to avoid accidental cross-region data transfer costs:

```hcl
# Built-in policy: "Allowed locations"
# Policy definition ID: /providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c

parameters = {
  listOfAllowedLocations = {
    value = ["eastus2", "eastus"]
  }
}
```

#### 4. Deny Public IP on Non-Gateway Resources

Prevent creation of public IPs on resources that should not be publicly accessible, reducing egress and load balancer costs:

```hcl
# Custom policy to deny public IPs except on designated gateway resources
```

#### 5. Auto-Tag with Environment

Use a `DeployIfNotExists` or `Modify` policy to automatically add the `managed_by = terraform` tag to any resource missing it, ensuring unmanaged resources are visible:

```hcl
# Built-in policy: "Add or replace a tag on resources"
# Use for managed_by tag to identify non-Terraform-managed resources
```

### Policy Assignment Scopes

| Policy | Dev Scope | Staging Scope | Prod Scope |
|---|---|---|---|
| Require cost tags | Audit | Deny | Deny |
| Allowed VM sizes | Deny | Deny | Audit |
| Allowed locations | Deny | Deny | Deny |
| Deny public IPs | Audit | Deny | Deny |

Use `Audit` in dev to surface violations without blocking work. Use `Deny` in production to enforce hard guardrails.

### Reviewing Policy Compliance

```bash
# Check compliance state for the subscription
az policy state summarize \
  --subscription $SUBSCRIPTION_ID \
  --query "results.nonCompliantResources"

# List non-compliant resources for a specific policy
az policy state list \
  --filter "complianceState eq 'NonCompliant'" \
  --query "[].{Resource:resourceId, Policy:policyDefinitionName}"
```

---

## 10. Monthly Cost Review Process

### Review Cadence

Conduct a cost review on the first Tuesday of each month, covering the previous month's spend.

### Review Checklist

#### Pre-Meeting Preparation (Day Before)

- [ ] Export the previous month's cost data from Azure Cost Management (grouped by resource type and environment)
- [ ] Run `make cost ENV=dev`, `make cost ENV=staging`, `make cost ENV=prod` to compare current infrastructure cost estimates against last month's actuals
- [ ] Pull reservation utilization report from **Azure Portal > Reservations > Utilization**
- [ ] Check Azure Advisor for new cost recommendations
- [ ] Review Log Analytics ingestion volume trends using the KQL query in Section 5

#### During Review

**1. Compare actuals vs budget**

| Environment | Budget | Actual | Variance |
|---|---|---|---|
| dev | $350 | $X | $Y |
| staging | $700 | $X | $Y |
| prod | $2,500 | $X | $Y |

**2. Identify top cost movers**
- Which resource types increased month-over-month?
- Are there untagged resources that cannot be attributed?
- Did any Log Analytics daily caps trigger?

**3. Validate reservation utilization**
- Any Reserved Instances below 70% utilization should be flagged for exchange or cancellation
- Review Savings Plan coverage ratio (target: >80% of compute covered by reservations or savings plans in production)

**4. Review new resources**
- Query for resources created this month:

```bash
az resource list \
  --query "[?createdTime >= '$(date -d '1 month ago' +%Y-%m-%d)'].{Name:name, Type:type, RG:resourceGroup, Created:createdTime}" \
  --output table
```

- Confirm all new resources have required tags
- Confirm all new resources were created by Terraform (check `managed_by` tag)

**5. Review Infracost estimates for pending changes**
- Pull open PRs and review Infracost comments for any pending cost changes

#### Actions to Assign

- Tag any untagged resources or raise a policy violation ticket
- Scale down any over-provisioned resources identified through utilization data
- Pause or decommission unused resources (see Section 11)
- Update budgets if baseline costs have shifted
- Purchase or exchange reservations if utilization data supports it

### Review Artifacts

Store monthly review outputs in the project's docs directory:

```
docs/
  cost-reviews/
    2026-03-cost-review.md
    2026-02-cost-review.md
```

Each review document should capture: actuals vs budget, top 5 cost items, actions taken, and next month's forecast.

---

## 11. Decommissioning Unused Resources

### Identifying Candidates

#### Resources with No Recent Activity

Use Azure Monitor metrics to identify resources with zero or near-zero utilization:

```bash
# AKS: clusters with no deployments running
kubectl get deployments --all-namespaces --context=aks-platform-dev

# Storage: accounts with no reads/writes in 30 days
az monitor metrics list \
  --resource /subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$SA \
  --metric "Transactions" \
  --start-time $(date -d '30 days ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --query "value[].timeseries[].data[].total | sum(@)"

# Log Analytics: workspaces with no ingestion in 14 days
# KQL:
# Usage | where TimeGenerated > ago(14d) | summarize count()
```

#### Untagged or Orphaned Resources

```bash
# Find resources missing the managed_by=terraform tag
az resource list \
  --query "[?tags.managed_by != 'terraform'].{Name:name, Type:type, RG:resourceGroup}" \
  --output table

# Find resource groups with no resources
az group list \
  --query "[?properties.provisioningState == 'Succeeded']" \
  | jq '.[] | select(.name) | .name' \
  | xargs -I {} az resource list --resource-group {} --query "length(@)"
```

#### Disk and Snapshot Orphans

```bash
# Find unattached managed disks
az disk list \
  --query "[?diskState == 'Unattached'].{Name:name, RG:resourceGroup, SizeGiB:diskSizeGb}" \
  --output table

# Find snapshots older than 90 days
az snapshot list \
  --query "[?timeCreated < '$(date -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)'].{Name:name, RG:resourceGroup}" \
  --output table
```

### Decommissioning Process

Follow this process for any resource identified as unused:

1. **Confirm with owner**: Check the `owner` tag and contact the team before destroying anything
2. **Apply a deprecation tag**: Add `status = "pending-deletion"` and `deletion-date = "YYYY-MM-DD"` to give a 14-day grace period
3. **Remove from Terraform**: Remove the module block or resource from the relevant environment's `main.tf`, run `terraform plan` to confirm only the target resource is affected, then apply
4. **Verify deletion**: Confirm the resource no longer appears in `az resource list` and that no dependent resources were affected
5. **Document**: Record the decommission in the monthly cost review

```bash
# Step 3: Safe Terraform destroy of a single resource
cd environments/dev
terraform plan -destroy -target=module.old_storage -var-file=dev.tfvars
terraform apply -destroy -target=module.old_storage -var-file=dev.tfvars
```

### Dev Environment Teardown

When a dev environment is no longer needed (e.g., after a sprint or feature branch), tear down the entire environment:

```bash
make destroy ENV=dev
```

This runs `terraform destroy -var-file=dev.tfvars` and removes all resources in the dev environment. Confirm the state file is clean afterward:

```bash
cd environments/dev && terraform show
```

### Preventing Resource Sprawl

- All resources must be created through Terraform; manual portal deployments are prohibited (enforced by the `managed_by` tag policy)
- Use the `drift` make target weekly to detect any resources created outside Terraform:

```bash
make drift ENV=dev
make drift ENV=prod
```

- Any drift (resources existing in Azure but not in Terraform state, or vice versa) must be reconciled within one sprint
