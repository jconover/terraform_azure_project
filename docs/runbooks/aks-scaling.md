# AKS Cluster Scaling Operations Runbook

**Version:** 1.0
**Last Updated:** 2026-03-03
**Owner:** Platform / Infrastructure Team
**Applies To:** All AKS clusters provisioned via `modules/aks-cluster`

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Horizontal Scaling — Node Count](#3-horizontal-scaling--node-count)
4. [Vertical Scaling — VM SKU Changes](#4-vertical-scaling--vm-sku-changes)
5. [Autoscaler Configuration](#5-autoscaler-configuration)
6. [Emergency Manual Scaling via Azure CLI](#6-emergency-manual-scaling-via-azure-cli)
7. [Monitoring Scaling Events](#7-monitoring-scaling-events)
8. [Rollback Procedures](#8-rollback-procedures)
9. [Cost Implications](#9-cost-implications)
10. [Decision Matrix: Scale Up vs Scale Out](#10-decision-matrix-scale-up-vs-scale-out)

---

## 1. Overview

### When to Scale

AKS scaling is required when the cluster can no longer meet workload resource demands, when cost efficiency targets are not being met, or when reliability margins fall below acceptable thresholds.

**Scale up (more nodes or larger VMs) when:**
- Cluster autoscaler is consistently at `max_count` and pods remain `Pending`
- Node CPU or memory utilization averages above 70% sustained over 15+ minutes
- Burst traffic events are anticipated (launches, batch jobs, scheduled high-load windows)

**Scale down when:**
- Node utilization is consistently below 30% for more than 24 hours
- Autoscaler scale-down events are repeatedly blocked by non-evictable pods
- Cost optimization reviews flag over-provisioning

### Scope

This runbook covers:
- The **default (system) node pool** managed by `var.default_node_pool`
- **Additional (user) node pools** managed by `var.additional_node_pools`
- The **Cluster Autoscaler** which is always enabled (`auto_scaling_enabled = true`) on all pools in this module

> **Important:** The cluster autoscaler is always enabled for all node pools in this module. Manual node count changes through the Azure portal will be overridden by Terraform on the next apply and by the autoscaler at runtime. Always use Terraform for persistent configuration changes.

---

## 2. Prerequisites

### Required Tools

| Tool | Minimum Version | Installation |
|---|---|---|
| Azure CLI | 2.55.0 | `winget install Microsoft.AzureCLI` / `brew install azure-cli` |
| kubectl | Matching cluster k8s version ±1 minor | `az aks install-cli` |
| Terraform | 1.5.0+ | `https://developer.hashicorp.com/terraform/install` |
| kubelogin | Latest | `az aks install-cli` |

### Required Access

- **Azure RBAC:** `Contributor` or `Azure Kubernetes Service Contributor` on the AKS resource, plus `Reader` on the resource group
- **Terraform state:** Read/write access to the remote backend (storage account + container)
- **kubectl:** Cluster-admin or a role with node and pod read access; obtain credentials with:

```bash
az aks get-credentials \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --overwrite-existing
```

- **AAD group membership:** Your account must belong to one of the `admin_group_object_ids` configured in `var.azure_active_directory_role_based_access_control` for kubectl access (Azure RBAC is enabled by default).

### Pre-Scaling Checks

Before any scaling operation, confirm the cluster and node pools are in a healthy state:

```bash
# Verify cluster is in a Succeeded provisioning state
az aks show \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --query "provisioningState" \
  --output tsv

# Check all nodes are Ready
kubectl get nodes -o wide

# Check for any pending pods that may indicate existing pressure
kubectl get pods --all-namespaces --field-selector=status.phase=Pending

# Check current autoscaler activity
kubectl -n kube-system logs -l app=cluster-autoscaler --tail=50
```

Do not proceed if the cluster `provisioningState` is anything other than `Succeeded`, or if nodes are in `NotReady` state.

---

## 3. Horizontal Scaling — Node Count

Horizontal scaling adjusts the minimum and maximum node counts for a node pool. The cluster autoscaler operates within these bounds at runtime.

### 3.1 Scaling the Default System Node Pool

The default node pool is configured via the `default_node_pool` object variable. The relevant fields are:

| Variable field | Default | Description |
|---|---|---|
| `default_node_pool.min_count` | `1` | Minimum node count (must be >= 1 for system pool) |
| `default_node_pool.max_count` | `3` | Maximum node count |
| `default_node_pool.vm_size` | `Standard_B2s` | VM SKU (see Section 4 for changes) |

**Step 1.** Locate the environment's `.tfvars` file (e.g., `environments/prod/terraform.tfvars`) and update the `default_node_pool` block:

```hcl
default_node_pool = {
  name      = "system"
  vm_size   = "Standard_B2s"
  min_count = 2   # changed from 1
  max_count = 6   # changed from 3
  os_disk_size_gb              = 30
  os_sku                       = "AzureLinux"
  zones                        = ["1", "2", "3"]
  max_pods                     = 30
  only_critical_addons_enabled = true
}
```

**Step 2.** Plan the change and review the diff:

```bash
cd environments/prod
terraform plan -var-file="terraform.tfvars" -out=scaling.tfplan
```

Review that only `min_count` and/or `max_count` are changing. Any additional resource changes (e.g., VM SKU, disk size) during a scaling operation should be investigated before proceeding.

**Step 3.** Apply the change:

```bash
terraform apply scaling.tfplan
```

**Step 4.** Confirm the node pool reflects the new bounds:

```bash
az aks nodepool show \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --nodepool-name system \
  --query "{minCount:minCount, maxCount:maxCount, currentNodeCount:count, provisioningState:provisioningState}" \
  --output table
```

### 3.2 Scaling an Additional (User) Node Pool

Additional node pools are managed via the `additional_node_pools` map variable. Each key in the map is the node pool name.

**Step 1.** Update the relevant node pool entry in the `.tfvars` file:

```hcl
additional_node_pools = {
  workload = {
    vm_size   = "Standard_D4s_v5"
    min_count = 2   # changed from 1
    max_count = 10  # changed from 5
    os_disk_size_gb = 30
    os_sku          = "AzureLinux"
    zones           = ["1", "2", "3"]
    max_pods        = 30
    mode            = "User"
    node_labels     = { workload = "true" }
    node_taints     = []
  }
}
```

**Step 2.** Plan and review:

```bash
terraform plan -var-file="terraform.tfvars" -out=scaling.tfplan
```

**Step 3.** Apply:

```bash
terraform apply scaling.tfplan
```

**Step 4.** Verify:

```bash
az aks nodepool show \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --nodepool-name workload \
  --query "{minCount:minCount, maxCount:maxCount, currentNodeCount:count, provisioningState:provisioningState}" \
  --output table

kubectl get nodes -l agentpool=workload
```

### 3.3 Adding a New Node Pool

To add a new pool entirely, append a new key to `additional_node_pools`:

```hcl
additional_node_pools = {
  # ... existing pools ...

  gpu = {
    vm_size         = "Standard_NC6s_v3"
    min_count       = 0
    max_count       = 4
    os_disk_size_gb = 128
    os_sku          = "AzureLinux"
    zones           = ["1", "2", "3"]
    max_pods        = 30
    mode            = "User"
    node_labels     = { accelerator = "nvidia" }
    node_taints     = ["nvidia.com/gpu=present:NoSchedule"]
    vnet_subnet_id  = "<SUBNET_ID>"
  }
}
```

Then follow the same plan/apply/verify steps as Section 3.2.

---

## 4. Vertical Scaling — VM SKU Changes

Vertical scaling changes the `vm_size` for a node pool. In AKS, this requires node pool replacement: Azure will cordon and drain existing nodes and provision new nodes with the new SKU.

> **Warning:** VM SKU changes on a node pool cause node replacement. All pods on affected nodes will be evicted and rescheduled. Ensure PodDisruptionBudgets (PDBs) are configured for critical workloads before proceeding.

### 4.1 Pre-Change Checks

```bash
# Review existing PodDisruptionBudgets
kubectl get pdb --all-namespaces

# Check for any pods without replicas (single-replica deployments that will experience downtime)
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.replicas==1)]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'

# Check StatefulSets (may have ordering requirements)
kubectl get statefulsets --all-namespaces
```

### 4.2 Maintenance Window

The module defines a maintenance window via `var.maintenance_window`. The default allows operations on Sunday between 00:00–04:00 UTC:

```hcl
# Default maintenance window (variables.tf line 169)
maintenance_window = {
  allowed = [
    { day = "Sunday", hours = [0, 1, 2, 3] }
  ]
}
```

Schedule VM SKU changes to occur within this window. To adjust the window for a one-off operation, update the variable before applying:

```hcl
maintenance_window = {
  allowed = [
    { day = "Saturday", hours = [22, 23] },
    { day = "Sunday",   hours = [0, 1, 2, 3] }
  ]
}
```

### 4.3 Performing the VM SKU Change

**Step 1.** Update `vm_size` in the node pool configuration:

```hcl
# For the default node pool
default_node_pool = {
  vm_size   = "Standard_D4s_v5"   # upgraded from Standard_B2s
  min_count = 2
  max_count = 6
  # ... other fields unchanged
}

# OR for an additional node pool
additional_node_pools = {
  workload = {
    vm_size = "Standard_D8s_v5"   # upgraded from Standard_D4s_v5
    # ... other fields unchanged
  }
}
```

**Step 2.** Plan and review carefully — confirm the plan shows a node pool update (not destroy/create of the cluster):

```bash
terraform plan -var-file="terraform.tfvars" -out=sku-change.tfplan
```

Expected plan output for an additional node pool SKU change:
```
# module.aks_cluster.azurerm_kubernetes_cluster_node_pool.this["workload"] will be updated in-place
```

For the default node pool, AKS may perform a rolling node replacement. Confirm with your Azure support tier whether in-place update or node replacement is expected for the target SKU pair.

**Step 3.** Apply during the maintenance window:

```bash
terraform apply sku-change.tfplan
```

**Step 4.** Monitor node replacement:

```bash
# Watch nodes cycling through NotReady -> Ready
kubectl get nodes -w

# Watch pod rescheduling
kubectl get pods --all-namespaces -w
```

**Step 5.** Confirm all nodes are on the new SKU:

```bash
kubectl get nodes -o custom-columns="NAME:.metadata.name,VM:.metadata.labels.node\.kubernetes\.io/instance-type,STATUS:.status.conditions[-1].type"
```

---

## 5. Autoscaler Configuration

The cluster autoscaler is always enabled in this module (`auto_scaling_enabled = true` on all node pools). The autoscaler behavior is controlled by `min_count` and `max_count` on each pool.

### 5.1 Current Defaults

| Pool | min_count | max_count |
|---|---|---|
| `default_node_pool` (system) | 1 | 3 |
| `additional_node_pools.*` | 1 | 3 |

### 5.2 Updating Autoscaler Bounds

The autoscaler respects `min_count` and `max_count` as hard bounds. To change them, update the Terraform variable and apply as described in Section 3.

### 5.3 Autoscaler Profile Tuning

AKS exposes cluster autoscaler profile settings at the cluster level. These are not currently surfaced as module variables but can be configured by extending the module or using the Azure CLI for immediate tuning.

**View current autoscaler profile:**

```bash
az aks show \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --query "autoScalerProfile" \
  --output json
```

**Key autoscaler profile fields:**

| Field | Default | Description |
|---|---|---|
| `scale-down-delay-after-add` | `10m` | Time to wait after a scale-up before evaluating scale-down |
| `scale-down-unneeded-time` | `10m` | How long a node must be unneeded before being removed |
| `scale-down-utilization-threshold` | `0.5` | Node utilization ratio below which a node is considered for removal |
| `max-graceful-termination-sec` | `600` | Max time to wait for pod eviction before force-terminating |
| `balance-similar-node-groups` | `false` | Attempt to balance node counts across similar pools |
| `expander` | `random` | Which pool to expand when multiple qualify (`random`, `least-waste`, `most-pods`, `priority`) |

**Update scale-down delay via Azure CLI (immediate, not persisted to Terraform):**

```bash
az aks update \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --cluster-autoscaler-profile \
    scale-down-delay-after-add=15m \
    scale-down-unneeded-time=15m \
    scale-down-utilization-threshold=0.4
```

> **Note:** Autoscaler profile changes made via CLI will be overwritten on the next `terraform apply` unless the module is extended to accept and pass `auto_scaler_profile` blocks. If persistent autoscaler profile tuning is needed, add it to the module's `azurerm_kubernetes_cluster` resource.

### 5.4 Verifying Autoscaler Activity

```bash
# Tail autoscaler logs
kubectl -n kube-system logs -l app=cluster-autoscaler -f --tail=100

# Check autoscaler status ConfigMap
kubectl -n kube-system get configmap cluster-autoscaler-status -o yaml

# Look for scale-up/scale-down events
kubectl get events --all-namespaces \
  --field-selector reason=TriggeredScaleUp \
  --sort-by='.lastTimestamp'

kubectl get events --all-namespaces \
  --field-selector reason=ScaleDown \
  --sort-by='.lastTimestamp'
```

---

## 6. Emergency Manual Scaling via Azure CLI

Use this section only when Terraform is unavailable or when an immediate node count change is required to resolve an incident. Manual changes will be overridden by the autoscaler and reconciled by Terraform on the next apply.

> **Important:** After any manual emergency change, create a follow-up task to align the Terraform variable values with the new desired configuration before the next `terraform apply`, or the cluster will be scaled back to the Terraform-defined bounds.

### 6.1 Immediately Scale a Node Pool to a Specific Count

```bash
# Manually set node count (temporarily disables autoscaler on this pool)
az aks nodepool scale \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --name <NODEPOOL_NAME> \
  --node-count 5
```

### 6.2 Temporarily Expand Autoscaler Bounds

This is the preferred emergency method because it keeps the autoscaler active:

```bash
az aks nodepool update \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --name <NODEPOOL_NAME> \
  --min-count 2 \
  --max-count 10 \
  --enable-cluster-autoscaler
```

### 6.3 Force Immediate Node Addition Without Waiting for Autoscaler

```bash
# Cordon + scale: cordon existing nodes to force new ones, then uncordon when ready
kubectl cordon <NODE_NAME>

# Or trigger autoscaler by creating a resource-demanding pod
kubectl run scale-trigger \
  --image=busybox \
  --restart=Never \
  --requests='cpu=1,memory=1Gi' \
  -- sleep 3600
# Delete when done
kubectl delete pod scale-trigger
```

### 6.4 Emergency Scale-Down (Cost Emergency)

```bash
# Cordon a node to prevent new scheduling, then drain it
kubectl cordon <NODE_NAME>
kubectl drain <NODE_NAME> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30

# After confirming workloads relocated, the autoscaler will remove the empty node
# Or manually reduce the pool count
az aks nodepool scale \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --name <NODEPOOL_NAME> \
  --node-count <NEW_COUNT>
```

### 6.5 Verifying Manual Changes Took Effect

```bash
az aks nodepool show \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --nodepool-name <NODEPOOL_NAME> \
  --query "{name:name, count:count, minCount:minCount, maxCount:maxCount, provisioningState:provisioningState}" \
  --output table

kubectl get nodes -l agentpool=<NODEPOOL_NAME>
```

---

## 7. Monitoring Scaling Events

### 7.1 kubectl — Real-Time Cluster State

```bash
# Watch all nodes and their status
kubectl get nodes -w

# Node resource utilization (requires metrics-server)
kubectl top nodes

# Pod distribution across nodes
kubectl get pods --all-namespaces -o wide | awk '{print $8}' | sort | uniq -c | sort -rn

# Describe a specific node to see allocated resources
kubectl describe node <NODE_NAME>

# Recent scaling-related events (cluster-wide)
kubectl get events --all-namespaces \
  --sort-by='.lastTimestamp' | grep -iE 'scale|evict|trigger|drain|cordon'
```

### 7.2 Cluster Autoscaler Logs

```bash
# Stream autoscaler decisions in real time
kubectl -n kube-system logs -l app=cluster-autoscaler -f

# Filter for scale-up decisions
kubectl -n kube-system logs -l app=cluster-autoscaler | grep -i "scale up"

# Filter for scale-down decisions
kubectl -n kube-system logs -l app=cluster-autoscaler | grep -i "scale down"

# Check autoscaler status detail
kubectl -n kube-system describe configmap cluster-autoscaler-status
```

### 7.3 Azure Monitor — Log Analytics Queries

The module enables Azure Monitor diagnostics when `var.log_analytics_workspace_id` is set, logging `kube-apiserver`, `kube-audit-admin`, and `guard` categories, plus `AllMetrics`.

**Node pool scaling events (KQL):**

```kql
AzureActivity
| where ResourceProviderNamespace == "Microsoft.ContainerService"
| where OperationNameValue has_any ("MICROSOFT.CONTAINERSERVICE/MANAGEDCLUSTERS/AGENTPOOLS/WRITE",
                                    "MICROSOFT.CONTAINERSERVICE/MANAGEDCLUSTERS/SCALE")
| project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue, Properties
| order by TimeGenerated desc
```

**Autoscaler decisions from control plane logs:**

```kql
AzureDiagnostics
| where Category == "kube-apiserver"
| where log_s has "cluster-autoscaler"
| project TimeGenerated, log_s
| order by TimeGenerated desc
```

**Node count over time:**

```kql
AzureMetrics
| where ResourceId contains "<CLUSTER_NAME>"
| where MetricName == "kube_node_status_condition"
| summarize avg(Average) by bin(TimeGenerated, 5m), MetricName
| render timechart
```

**Pending pods alert (run as a scheduled query alert):**

```kql
KubePodInventory
| where PodStatus == "Pending"
| where TimeGenerated > ago(15m)
| summarize PendingCount = count() by bin(TimeGenerated, 5m), ClusterName
| where PendingCount > 0
```

### 7.4 Azure CLI Monitoring

```bash
# List recent node pool operations
az aks operation-value list \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME>

# View node pool metrics via Azure Monitor
az monitor metrics list \
  --resource "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>/providers/Microsoft.ContainerService/managedClusters/<CLUSTER_NAME>" \
  --metric "node_cpu_usage_percentage" \
  --interval PT5M \
  --output table
```

---

## 8. Rollback Procedures

### 8.1 Rollback a Terraform-Managed Scaling Change

If a scaling change causes problems, revert by restoring the previous variable values and applying:

**Step 1.** Restore the previous `min_count` / `max_count` (or `vm_size`) values in the `.tfvars` file to their pre-change state.

**Step 2.** Plan to confirm the diff returns to the previous state:

```bash
terraform plan -var-file="terraform.tfvars" -out=rollback.tfplan
```

**Step 3.** Apply the rollback:

```bash
terraform apply rollback.tfplan
```

**Step 4.** Verify nodes return to the expected count and status:

```bash
kubectl get nodes
az aks nodepool show \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --nodepool-name <NODEPOOL_NAME> \
  --query "{count:count, minCount:minCount, maxCount:maxCount, provisioningState:provisioningState}"
```

### 8.2 Rollback a VM SKU Change

VM SKU rollback follows the same Terraform revert process. However, if node pool replacement has already completed, the rollback will trigger another node pool replacement cycle (full cordon/drain/provision sequence).

To minimize disruption during a SKU rollback:

```bash
# 1. Ensure PDBs allow eviction
kubectl get pdb --all-namespaces

# 2. Pre-scale (temporarily raise max_count) if node count will be reduced during rollback
# 3. Apply rollback tfvars and plan, then apply in the maintenance window
```

### 8.3 Rollback a Manual CLI Scaling Change

To undo a manual `az aks nodepool scale` or `az aks nodepool update` command:

```bash
# Re-enable autoscaler with original bounds
az aks nodepool update \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --name <NODEPOOL_NAME> \
  --min-count <ORIGINAL_MIN> \
  --max-count <ORIGINAL_MAX> \
  --enable-cluster-autoscaler
```

Then run `terraform plan` to confirm drift and `terraform apply` to reconcile state.

### 8.4 Recovering from a Failed Apply

If `terraform apply` fails mid-way through a scaling operation:

```bash
# Check Terraform state to understand what was applied
terraform state show 'module.aks_cluster.azurerm_kubernetes_cluster.this'

# Check Azure for actual cluster state
az aks show \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --query "provisioningState"

# If cluster is in a failed state, Azure may require a repair operation
az aks nodepool upgrade \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <CLUSTER_NAME> \
  --name <NODEPOOL_NAME> \
  --kubernetes-version <CURRENT_VERSION>  # same version to force reconcile
```

If the cluster enters a `Failed` provisioning state and Terraform cannot resolve it, engage Azure Support with the cluster resource ID and operation timestamps.

---

## 9. Cost Implications

### 9.1 VM SKU Cost Reference (illustrative; verify current pricing at azure.microsoft.com/pricing)

| SKU (default) | vCPUs | RAM | Approx. hourly (East US) |
|---|---|---|---|
| `Standard_B2s` | 2 | 4 GB | ~$0.046 |
| `Standard_D2s_v5` | 2 | 8 GB | ~$0.096 |
| `Standard_D4s_v5` | 4 | 16 GB | ~$0.192 |
| `Standard_D8s_v5` | 8 | 32 GB | ~$0.384 |
| `Standard_D16s_v5` | 16 | 64 GB | ~$0.768 |
| `Standard_NC6s_v3` (GPU) | 6 | 112 GB | ~$3.06 |

### 9.2 Cost Levers and Tradeoffs

**Autoscaler scale-down delay:** The default `scale-down-delay-after-add=10m` means idle nodes after a burst will be kept for at least 10 minutes. Reducing this saves money but increases scale-up frequency and latency for subsequent bursts.

**`min_count` setting:** Nodes at `min_count` run continuously regardless of utilization. Setting `min_count = 1` for user pools instead of `0` ensures warm nodes but adds baseline cost. Setting `min_count = 0` on user pools allows full scale-to-zero during off-hours.

> **Note:** The system node pool (`default_node_pool`) has a hard constraint of `min_count >= 1` enforced by the module's validation rule. The system pool cannot scale to zero.

**Zone distribution:** All pools default to `zones = ["1", "2", "3"]`. Multi-zone spreads nodes evenly across AZs for HA but may result in 1 node per zone minimum when only 1–2 nodes are needed. For non-HA workloads, reducing to a single zone can improve autoscaler efficiency.

**`max_pods = 30`:** The default `max_pods` per node is 30. With Azure CNI overlay (`network_plugin_mode = "overlay"`), this is not subnet-constrained, but increasing `max_pods` can allow fewer, denser nodes — reducing cost for I/O-bound workloads. Reducing `max_pods` forces more nodes for pod-dense workloads — increasing cost.

**SKU tier cost:**
- `Free`: No SLA, no cost for control plane
- `Standard`: 99.9% (single-zone) / 99.95% (multi-zone) SLA, ~$0.10/cluster/hour
- `Premium`: 99.95% / 99.99% SLA, includes Long Term Support — most expensive

The module defaults to `Standard`. Downgrading to `Free` for non-production clusters is a common cost optimization.

### 9.3 Cost Estimation Before Scaling

```bash
# Estimated monthly cost of a node pool at current max_count
# (VM_HOURLY_COST * max_count * 730 hours)
# Example: Standard_D4s_v5 at max 10 nodes
# $0.192 * 10 * 730 = $1,401.60/month (worst-case, all nodes running)

# Use Azure Cost Management for actuals
az costmanagement query \
  --type ActualCost \
  --timeframe MonthToDate \
  --dataset-filter "{\"and\":[{\"dimensions\":{\"name\":\"ResourceGroupName\",\"operator\":\"In\",\"values\":[\"<RESOURCE_GROUP>\"]}}]}" \
  --output table
```

---

## 10. Decision Matrix: When to Scale Up vs Scale Out

### Definitions

- **Scale Out (horizontal):** Add more nodes of the same VM SKU by increasing `max_count`
- **Scale Up (vertical):** Replace nodes with a larger VM SKU by changing `vm_size`

### Decision Matrix

| Symptom | Root Cause | Recommended Action |
|---|---|---|
| Pods `Pending` with `Insufficient cpu` | CPU exhaustion, autoscaler at `max_count` | Scale out: increase `max_count` |
| Pods `Pending` with `Insufficient memory` | Memory exhaustion, autoscaler at `max_count` | Scale out: increase `max_count` |
| Individual pod needs >50% of node RAM | Workload cannot fit on current SKU | Scale up: increase `vm_size` |
| Many small pods, low per-pod CPU/memory | High pod-count inefficiency | Scale out with higher `max_pods` per node |
| Node CPU >80% but memory <30% | CPU-bound workload | Scale up to CPU-optimized SKU (e.g., `Standard_F` series) |
| Node memory >80% but CPU <30% | Memory-bound workload | Scale up to memory-optimized SKU (e.g., `Standard_E` series) |
| ML/AI workloads not fitting on CPU nodes | GPU requirement | Add new GPU node pool (`Standard_NC` series) with appropriate taints |
| Cluster scales to `max_count` daily but idles at night | Predictable burst pattern | Raise `max_count` and rely on autoscaler; consider scheduled scaling via AKS node pool start/stop |
| Single-node pool is a scaling bottleneck | Diverse workload types | Add specialized user node pools with labels and taints |
| Scale-down is slow / nodes drain too slowly | PDBs too restrictive or `max-graceful-termination-sec` too high | Review PDB `maxUnavailable` settings; tune autoscaler profile |
| System pool running user workloads | Missing user pool or pool labels | Add user node pool; set `only_critical_addons_enabled = true` on system pool (already default in this module) |

### Quick Reference Flow

```
Pods Pending?
  Yes -> Check: kubectl describe pod <pod> | grep -A5 Events
    "Insufficient cpu/memory" + autoscaler at max -> Scale Out (increase max_count)
    "No nodes available matching affinity" -> Add new node pool with matching labels
    "0/N nodes have sufficient memory, pod requests X" where X > node capacity -> Scale Up (larger vm_size)
  No -> Check node utilization: kubectl top nodes
    All nodes <30% utilized for 24h+ -> Scale In (decrease max_count or reduce min_count)
    Mixed utilization -> Review workload distribution; check pod affinity rules
```

### When NOT to Scale

- Do not scale to resolve application-level bugs (e.g., memory leaks, unbounded goroutines). Fix the root cause first.
- Do not increase `max_count` beyond subnet capacity. Check available IPs in `vnet_subnet_id` before scaling: `az network vnet subnet show --query "ipConfigurations | length(@)"` compared against the subnet CIDR.
- Do not perform VM SKU changes during business hours for production workloads without explicit change approval and PDB validation.
- Do not raise `min_count` for the default system pool beyond what is needed for kube-system components — user workloads should be scheduled to user node pools.

---

## Appendix: Variable Reference Summary

The following variables in `modules/aks-cluster/variables.tf` are relevant to scaling operations:

| Variable | Type | Default | Scaling Relevance |
|---|---|---|---|
| `default_node_pool.vm_size` | `string` | `Standard_B2s` | Vertical scale (system pool) |
| `default_node_pool.min_count` | `number` | `1` | Autoscaler lower bound (system pool) |
| `default_node_pool.max_count` | `number` | `3` | Autoscaler upper bound (system pool) |
| `default_node_pool.max_pods` | `number` | `30` | Pod density per node |
| `default_node_pool.zones` | `list(string)` | `["1","2","3"]` | AZ distribution |
| `additional_node_pools.<name>.vm_size` | `string` | `Standard_B2s` | Vertical scale (user pools) |
| `additional_node_pools.<name>.min_count` | `number` | `1` | Autoscaler lower bound (user pools) |
| `additional_node_pools.<name>.max_count` | `number` | `3` | Autoscaler upper bound (user pools) |
| `additional_node_pools.<name>.mode` | `string` | `User` | Pool mode (`System`/`User`) |
| `maintenance_window.allowed` | `list(object)` | Sunday 00–04 UTC | Window for VM SKU changes |
| `sku_tier` | `string` | `Standard` | Control plane SLA tier |
| `log_analytics_workspace_id` | `string` | `""` | Enables Azure Monitor diagnostics |
