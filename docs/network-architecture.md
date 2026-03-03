# Network Architecture

## Table of Contents

1. [Network Topology Overview](#1-network-topology-overview)
2. [VNet and Subnet Design Rationale](#2-vnet-and-subnet-design-rationale)
3. [IP Address Planning and CIDR Allocation](#3-ip-address-planning-and-cidr-allocation)
4. [NSG Rules and Traffic Flow](#4-nsg-rules-and-traffic-flow)
5. [Private Endpoint Architecture](#5-private-endpoint-architecture)
6. [DNS Resolution for Private Endpoints](#6-dns-resolution-for-private-endpoints)
7. [AKS Networking: CNI Overlay](#7-aks-networking-cni-overlay)
8. [Hub-Spoke Considerations for Future Growth](#8-hub-spoke-considerations-for-future-growth)
9. [Network Monitoring and Diagnostics](#9-network-monitoring-and-diagnostics)
10. [Peering and Connectivity Patterns](#10-peering-and-connectivity-patterns)
11. [Firewall and NVA Considerations](#11-firewall-and-nva-considerations)
12. [Network Security Best Practices](#12-network-security-best-practices)

---

## 1. Network Topology Overview

The network is built around a single Azure Virtual Network (VNet) with four purpose-isolated subnets. Each subnet hosts a distinct workload tier, enabling precise NSG enforcement and a clear security boundary per layer.

```
Internet
    |
    | (public ingress)
    v
+---+--------------------------------------------------+
|                 Azure Virtual Network                |
|                    10.0.0.0/16                       |
|                                                      |
|  +------------------+    +------------------------+  |
|  |   App Gateway    |    |      AKS Subnet        |  |
|  |  10.0.6.0/24     |    |    10.0.0.0/22         |  |
|  |  (public-facing) +--->|  (node NICs + overlay) |  |
|  +------------------+    +------------------------+  |
|                                    |                 |
|                                    v                 |
|  +------------------+    +------------------------+  |
|  |  Private EP      |    |    Services Subnet     |  |
|  |  10.0.5.0/24     |<---+    10.0.4.0/24         |  |
|  |  (PaaS backends) |    |  (internal services)   |  |
|  +------------------+    +------------------------+  |
|          |                                           |
|          v                                           |
|   Azure PaaS (Key Vault, Storage, ACR, etc.)         |
|   via Private Link / private IP                      |
+------------------------------------------------------+
```

Traffic flows:

- External clients reach the application through Application Gateway (10.0.6.0/24), which terminates TLS, applies WAF rules, and routes to AKS ingress.
- AKS nodes (10.0.0.0/22) host pods via CNI Overlay. Pods use a separate address space that does not consume VNet IPs.
- Workloads in the services subnet (10.0.4.0/24) host ancillary services or internal microservices not directly exposed to the ingress path.
- All PaaS dependency access (Key Vault, Storage, ACR) routes through private endpoints in 10.0.5.0/24, eliminating public internet traversal.

---

## 2. VNet and Subnet Design Rationale

### VNet Address Space: 10.0.0.0/16

A /16 provides 65,536 addresses, giving ample room for current subnets while accommodating future expansion (additional node pools, new service tiers, peered spokes) without requiring a disruptive readdressing exercise.

### Subnet Segmentation Principles

Each subnet maps to a single responsibility:

| Subnet | Purpose | Rationale |
|--------|---------|-----------|
| AKS (10.0.0.0/22) | Kubernetes node NICs | Large allocation for node scale-out; CNI Overlay decouples pod IPs |
| Services (10.0.4.0/24) | Internal service VMs or PaaS delegations | Isolated blast radius from AKS churn |
| Private Endpoints (10.0.5.0/24) | Private Link NIC placement | Dedicated subnet simplifies NSG rules for PaaS egress |
| App Gateway (10.0.6.0/24) | Application Gateway v2 instances | Azure requirement: App Gateway needs a dedicated subnet |

### Subnet Module Capabilities

The `subnet` module (`modules/subnet/`) exposes first-class support for:

- **Service endpoints**: Opt-in per subnet via `service_endpoints` variable; conditionally omitted when empty to avoid accidental policy side-effects.
- **Subnet delegation**: Structured `delegation` object for Azure-managed service injection (e.g., Azure Container Instances, API Management). Null by default.
- **Private endpoint network policies**: Controlled via `private_endpoint_network_policies`; defaults to `"Enabled"`, which must be set to `"Disabled"` on subnets hosting private endpoint NICs to allow NSG enforcement on those endpoints.
- **NSG association**: Optional `network_security_group_id` wires the NSG at subnet creation time rather than as a separate lifecycle step.

---

## 3. IP Address Planning and CIDR Allocation

### Current Allocation

```
VNet: 10.0.0.0/16   (65,534 usable host addresses)
|
+-- 10.0.0.0/22     AKS nodes          (1,022 usable addresses)
|   10.0.0.0  - 10.0.3.255
|
+-- 10.0.4.0/24     Services           (254 usable addresses)
|   10.0.4.0  - 10.0.4.255
|
+-- 10.0.5.0/24     Private Endpoints  (254 usable addresses)
|   10.0.5.0  - 10.0.5.255
|
+-- 10.0.6.0/24     App Gateway        (254 usable addresses)
|   10.0.6.0  - 10.0.6.255
|
+-- 10.0.7.0/24  ]
    ...            ]  Reserved for future subnets
    10.0.255.0/24 ]
```

### AKS Subnet Sizing (/22 = 1,022 node IPs)

With CNI Overlay, the /22 node subnet only needs to hold node NICs, not individual pod IPs. The default node pool configures `max_pods = 30`. At 1,022 available node addresses (minus Azure's 5 reserved per subnet), this subnet supports up to approximately 200 nodes before exhaustion, well beyond typical cluster sizes. Additional node pools also reference `vnet_subnet_id`, so all pools share this address space; factor in the sum of all pool node counts when projecting usage.

### Private Endpoint Subnet Sizing (/24 = 254 addresses)

Each private endpoint consumes one IP address in the private endpoint subnet. A /24 accommodates up to 249 endpoints (after reserving Azure's 5 addresses), which is sufficient for all foreseeable PaaS services. Current planned endpoints:

| Service | Subresource | Approximate IP |
|---------|------------|----------------|
| Azure Key Vault | `vault` | 10.0.5.4 |
| Azure Storage (blob) | `blob` | 10.0.5.5 |
| Azure Storage (file) | `file` | 10.0.5.6 |
| Azure Container Registry | `registry` | 10.0.5.7 |

Actual IPs are assigned dynamically by Azure; the above are illustrative.

### AKS Overlay and Service CIDRs

Pod and service IPs are drawn from ranges outside the VNet entirely:

| Range | Purpose |
|-------|---------|
| 10.0.0.0/22 | Node NICs (VNet-routable) |
| 172.16.0.0/16 | Kubernetes service ClusterIPs (non-VNet, cluster-internal) |
| 172.16.0.10 | CoreDNS / kube-dns ClusterIP |

These overlay ranges must not overlap with the VNet address space, any on-premises ranges reachable over ExpressRoute or VPN, or any peered VNet address spaces.

### Reserved Address Blocks

The following ranges within 10.0.0.0/16 are unallocated and reserved for future use:

- `10.0.7.0/24` through `10.0.255.0/24` - Future subnets, peered spoke allocations, or additional AKS node pools.

---

## 4. NSG Rules and Traffic Flow

### NSG Module Behaviour

The `network-security-group` module (`modules/network-security-group/`) implements a default-deny posture: when no `security_rules` are supplied, a single catch-all deny rule is inserted automatically at priority 4096:

```hcl
# modules/network-security-group/main.tf (local.default_deny_rule)
{
  name                       = "DenyAllInbound"
  priority                   = 4096
  direction                  = "Inbound"
  access                     = "Deny"
  protocol                   = "*"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
}
```

This ensures subnets with no explicit rules are not implicitly open. All deliberate traffic is allow-listed at lower priority numbers.

### Rule Priority Convention

| Priority Range | Use |
|---------------|-----|
| 100 - 999 | Critical platform rules (Azure infrastructure, health probes) |
| 1000 - 2999 | Application-specific allow rules |
| 3000 - 3999 | Cross-subnet allow rules |
| 4000 - 4095 | Explicit deny rules (before the catch-all) |
| 4096 | Default deny-all (auto-inserted by module) |

### Per-Subnet Traffic Intent

#### App Gateway Subnet (10.0.6.0/24)

```
Inbound:
  Allow  TCP 80, 443     from Internet              (client traffic)
  Allow  TCP 65200-65535 from GatewayManager        (Azure health probes - REQUIRED)
  Allow  *               from AzureLoadBalancer      (internal probe traffic)
  Deny   *               from *                      (default deny)

Outbound:
  Allow  TCP 80, 443     to AKS Subnet 10.0.0.0/22  (backend pool)
  Allow  *               to Internet                 (OCSP, CRL checks for TLS)
```

The GatewayManager inbound rule on ports 65200-65535 is mandatory for Application Gateway v2 health; omitting it causes the gateway to report degraded status.

#### AKS Subnet (10.0.0.0/22)

```
Inbound:
  Allow  TCP 80, 443     from App Gateway 10.0.6.0/24   (ingress traffic)
  Allow  TCP 10250       from AKS control plane          (kubelet API)
  Allow  *               from AKS Subnet 10.0.0.0/22    (node-to-node, pod overlay)
  Allow  *               from AzureLoadBalancer          (health probes)
  Deny   *               from *                          (default deny)

Outbound:
  Allow  TCP 443         to AzureCloud                   (API server, ACR pull)
  Allow  TCP 443, 1443   to Private EP 10.0.5.0/24       (Key Vault, Storage via PE)
  Allow  *               to AKS Subnet 10.0.0.0/22       (cluster-internal)
  Allow  UDP 123         to *                             (NTP)
  Allow  TCP 53, UDP 53  to *                             (DNS)
```

#### Services Subnet (10.0.4.0/24)

```
Inbound:
  Allow  TCP (app ports) from AKS Subnet 10.0.0.0/22    (workload calls)
  Allow  *               from AzureLoadBalancer           (health probes)
  Deny   *               from *                           (default deny)

Outbound:
  Allow  TCP 443, 1443   to Private EP 10.0.5.0/24       (PaaS backends via PE)
  Allow  *               to AKS Subnet 10.0.0.0/22       (callbacks to cluster)
```

#### Private Endpoint Subnet (10.0.5.0/24)

```
Inbound:
  Allow  TCP 443, 1443   from AKS Subnet 10.0.0.0/22    (cluster -> PaaS)
  Allow  TCP 443, 1443   from Services 10.0.4.0/24       (services -> PaaS)
  Deny   *               from *                           (default deny)

Outbound:
  (Private endpoints only send responses; no initiated outbound rules needed)
```

Note: `private_endpoint_network_policies` must be set to `"Disabled"` on the private endpoint subnet for NSG rules to be evaluated against private endpoint NICs. The subnet module variable defaults to `"Enabled"` and must be explicitly overridden for this subnet.

### NSG Diagnostic Logging

Both `NetworkSecurityGroupEvent` and `NetworkSecurityGroupRuleCounter` log categories are shipped to Log Analytics when `log_analytics_workspace_id` is provided. The event log captures allow/deny decisions; the rule counter log tracks hit counts per rule, useful for identifying dead rules or unexpected traffic patterns.

---

## 5. Private Endpoint Architecture

### Design

Private endpoints replace public PaaS service endpoints with a private NIC inside the VNet. Traffic from AKS pods or services reaches Azure PaaS (Key Vault, Storage, ACR) entirely over the Azure backbone, never leaving the private address space.

```
AKS Pod
  |
  | (overlay -> node NIC -> VNet routing)
  v
Node NIC (10.0.0.x)
  |
  | (routed to private endpoint subnet)
  v
Private Endpoint NIC (10.0.5.x)  <-- azurerm_private_endpoint
  |
  | (Private Link service connection)
  v
Azure PaaS (Key Vault / Storage / ACR)
  (public endpoint disabled on the resource)
```

### Module Structure

The `private-endpoint` module (`modules/private-endpoint/`) manages three resources as a unit:

1. **`azurerm_private_endpoint`** - The NIC placed in the private endpoint subnet.
2. **`private_service_connection`** block - Named `${var.name}-psc`; carries the target resource ID and subresource name (e.g., `vault`, `blob`, `registry`).
3. **`private_dns_zone_group`** (conditional) - Created when `private_dns_zone_ids` is non-empty; links the endpoint to the appropriate Private DNS Zone so that DNS A records are auto-registered.

### Subresource Names by Service

| Azure Service | Subresource Name | Private DNS Zone |
|--------------|-----------------|-----------------|
| Key Vault | `vault` | `privatelink.vaultcore.azure.net` |
| Storage (Blob) | `blob` | `privatelink.blob.core.windows.net` |
| Storage (File) | `file` | `privatelink.file.core.windows.net` |
| Storage (Queue) | `queue` | `privatelink.queue.core.windows.net` |
| Azure Container Registry | `registry` | `privatelink.azurecr.io` |
| Azure SQL | `sqlServer` | `privatelink.database.windows.net` |
| Event Hub | `namespace` | `privatelink.servicebus.windows.net` |

### Manual vs. Auto-Approval

The `is_manual_connection` variable (default `false`) controls whether the private endpoint connection is auto-approved by the target resource's owner. Auto-approval is standard for resources within the same subscription. Cross-subscription or cross-tenant connections require manual approval and will remain in `Pending` state until an owner of the target resource approves the connection in the Azure portal or via CLI.

### Disabling Public Access

Private endpoints are only effective when the public endpoint of the target PaaS service is explicitly disabled or restricted. Azure Policy should enforce this:

```
Policy: "Azure Key Vault should disable public network access"
Policy: "Storage accounts should restrict network access"
```

Without this enforcement, an attacker with network access to the public endpoint bypasses the private endpoint entirely.

---

## 6. DNS Resolution for Private Endpoints

### Resolution Chain

For private endpoints to work correctly, DNS queries for PaaS FQDNs must resolve to the private IP (10.0.5.x) rather than the public IP. Azure provides Private DNS Zones for this purpose.

```
Pod (CoreDNS) --> Azure DNS 168.63.129.16
                        |
                        | (conditional: FQDN in privatelink.* zone?)
                        v
                 Private DNS Zone
                 (e.g., privatelink.vaultcore.azure.net)
                        |
                        v
                 A record: myvault.vault.azure.net -> 10.0.5.4
```

### Private DNS Zone Group

When `private_dns_zone_ids` is supplied to the private endpoint module, Azure automatically manages A records in the linked Private DNS Zone. The record is created when the endpoint is provisioned and removed when it is destroyed. No manual DNS management is required.

The Private DNS Zone must be linked to the VNet (VNet link resource: `azurerm_private_dns_zone_virtual_network_link`) for resolution to function. This link enables the VNet's DNS resolver to consult the private zone.

### CoreDNS in AKS

AKS CoreDNS forwards non-cluster DNS queries to the node's DNS resolver (the Azure DNS address 168.63.129.16 via the VNet DNS configuration). When the VNet's DNS servers list (`dns_servers` variable on the VNet module) is empty (the default), Azure's platform DNS is used automatically and private zone lookups work without additional configuration.

### Custom DNS Server Considerations

If `dns_servers` is set on the VNet to point at a custom DNS server (e.g., an on-premises forwarder or Azure Firewall DNS proxy):

1. The custom DNS server must forward `*.privatelink.*` queries to Azure DNS (168.63.129.16).
2. AKS CoreDNS must be able to reach the custom DNS server.
3. Azure Firewall DNS Proxy mode is the recommended intermediary when custom DNS is required alongside private endpoints.

### DNS Validation

Verify private endpoint DNS resolution from within a pod:

```bash
# Exec into a pod
kubectl exec -it <pod> -- /bin/sh

# Confirm resolution returns a private IP (10.0.5.x), not a public IP
nslookup myvault.vault.azure.net
# Expected: Address: 10.0.5.4
```

---

## 7. AKS Networking: CNI Overlay

### Plugin Configuration

The AKS cluster uses Azure CNI in Overlay mode:

```hcl
# modules/aks-cluster/variables.tf defaults
network_plugin      = "azure"
network_plugin_mode = "overlay"
network_policy      = "azure"
service_cidr        = "172.16.0.0/16"
dns_service_ip      = "172.16.0.10"
```

### CNI Overlay vs. Standard Azure CNI

| Characteristic | Azure CNI (standard) | Azure CNI Overlay |
|---------------|---------------------|------------------|
| Pod IP source | VNet subnet (each pod = 1 VNet IP) | Separate overlay CIDR (not VNet IPs) |
| Node subnet size needed | Nodes x max_pods | Nodes only |
| VNet IP consumption | Very high | Low (node NICs only) |
| Pod-to-pod routing | Native VNet routing | VXLAN encapsulation within node |
| External pod reachability | Direct | Requires DNAT at node |
| Supported network policies | Azure NPM, Calico, Cilium | Azure NPM, Calico, Cilium |

With Overlay, a /22 node subnet (1,022 addresses) supports far more pods than the equivalent standard CNI configuration would, since pod IPs are drawn from the overlay space (172.16.0.0/16 is used for services; pods get an additional internal range managed by Azure CNI internally).

### Node Pool Subnet Assignment

Both the default node pool and all additional node pools reference `vnet_subnet_id`:

```hcl
# modules/aks-cluster/main.tf
default_node_pool {
  vnet_subnet_id = var.default_node_pool.vnet_subnet_id
}

resource "azurerm_kubernetes_cluster_node_pool" "this" {
  for_each       = var.additional_node_pools
  vnet_subnet_id = each.value.vnet_subnet_id
}
```

All node pools should reference the AKS subnet (10.0.0.0/22). User pools dedicated to GPU or memory-optimized workloads may be placed in a separate subnet if workload isolation is required, but that subnet must be added to the AKS NSG association and its CIDR reserved in the VNet address space.

### Network Policy: Azure NPM

The default `network_policy = "azure"` enables Azure Network Policy Manager (NPM). NPM enforces Kubernetes `NetworkPolicy` objects using iptables rules on each node. This provides pod-level traffic segmentation within the cluster without installing a third-party CNI plugin.

Alternative options available via the module:

- `calico`: eBPF-based; better observability and performance at scale, but requires Calico components running in cluster.
- `cilium`: Full eBPF dataplane; enables Hubble observability and higher throughput; requires compatible Kubernetes version.

### Pod and Service CIDR Isolation Requirements

The following ranges must not overlap with each other or with any VNet / peered network address space:

```
Node subnet:     10.0.0.0/22    (VNet-routable, must not overlap with other subnets)
Service CIDR:    172.16.0.0/16  (cluster-internal only, never routed outside AKS)
DNS Service IP:  172.16.0.10    (must fall within service_cidr)
```

The service CIDR is never advertised outside the cluster. Pods reach cluster services via kube-proxy rules on the node; external traffic to services uses NodePort or LoadBalancer, not the ClusterIP directly.

### AKS Cluster Diagnostics

The module ships three log categories to Log Analytics:

| Log Category | Description |
|-------------|-------------|
| `kube-apiserver` | API server request logs; useful for auditing kubectl and controller activity |
| `kube-audit-admin` | Admin-level audit events; covers privileged operations |
| `guard` | Azure AD authentication events for the cluster |

All metrics (`AllMetrics`) are also collected, covering node CPU, memory, disk, and network utilisation.

---

## 8. Hub-Spoke Considerations for Future Growth

### Current: Single-VNet (Flat) Model

The current topology uses a single VNet with all subnets co-located. This is appropriate for environments where:

- All workloads share the same trust boundary.
- Centralized egress control is not yet required.
- The team size and blast radius are limited to one workload family.

### When to Introduce a Hub-Spoke Model

Adopt hub-spoke when any of the following conditions arise:

| Trigger | Recommendation |
|---------|---------------|
| On-premises connectivity (ExpressRoute / VPN) | Move shared gateway resources into a hub |
| Shared services (DNS, NVA, jump host) used by multiple product teams | Centralize in hub; spoke VNets consume via peering |
| Compliance requirement for centralized egress inspection | Place Azure Firewall in hub; route all spoke egress through it |
| Multiple isolated product teams sharing Azure subscription | One spoke per team; hub owns connectivity |
| Azure Virtual WAN adoption | WAN hub replaces manual peering with automated branch connectivity |

### Target Hub-Spoke Architecture

```
                    +-------------------+
                    |     Hub VNet      |
                    |   10.100.0.0/16   |
                    |                   |
                    | Azure Firewall    |
                    | VPN / ER Gateway  |
                    | Shared DNS        |
                    | Bastion           |
                    +---+----+----+-----+
                        |    |    |
              +---------+    |    +-----------+
              |              |                |
   +----------+----+   +-----+--------+   +---+----------+
   |   Spoke: Prod |   | Spoke: Stage |   | Spoke: Dev   |
   | 10.0.0.0/16   |   | 10.1.0.0/16  |   | 10.2.0.0/16  |
   | (current VNet)|   |              |   |              |
   +---------------+   +--------------+   +--------------+
```

### Migration Path

1. Create hub VNet in a dedicated connectivity resource group.
2. Peer current (spoke) VNet to hub with `allow_gateway_transit = true` on hub side and `use_remote_gateways = true` on spoke side (when gateway exists).
3. Route spoke egress to hub firewall via User Defined Routes (UDRs) on each spoke subnet.
4. Migrate shared DNS to hub; update spoke VNet `dns_servers` to point at hub DNS forwarder.
5. Remove direct internet egress from spoke NSGs once hub firewall is validated.

### UDR Planning

For hub-spoke with centralized egress, each spoke subnet requires a route table:

```
Destination: 0.0.0.0/0
Next hop:    VirtualAppliance
Next hop IP: <Azure Firewall private IP in hub>
```

The AKS subnet has additional UDR constraints: the API server IP range must not be redirected through a firewall unless the firewall allows the required ports. Consult AKS egress requirements documentation before applying 0.0.0.0/0 UDRs to the AKS subnet.

---

## 9. Network Monitoring and Diagnostics

### Diagnostic Coverage

All network resources in this project emit diagnostics to Log Analytics when `log_analytics_workspace_id` is configured:

| Resource | Log Categories | Metrics |
|---------|---------------|---------|
| Virtual Network | allLogs | AllMetrics |
| Network Security Group | NetworkSecurityGroupEvent, NetworkSecurityGroupRuleCounter | - |
| AKS Cluster | kube-apiserver, kube-audit-admin, guard | AllMetrics |

### NSG Flow Logs

NSG flow logs (not yet in the module) capture per-connection 5-tuple data (source IP, destination IP, source port, destination port, protocol) along with allow/deny outcome and byte counts. They feed into Network Watcher Traffic Analytics for topology visualisation and anomaly detection.

To enable flow logs for an NSG:

```hcl
resource "azurerm_network_watcher_flow_log" "nsg" {
  network_watcher_name      = azurerm_network_watcher.this.name
  resource_group_name       = var.resource_group_name
  network_security_group_id = module.nsg.id
  storage_account_id        = module.storage.id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = 30
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = module.log_analytics.workspace_id
    workspace_region      = var.location
    workspace_resource_id = module.log_analytics.id
    interval_in_minutes   = 10
  }
}
```

### Key Log Analytics Queries

**Top denied inbound connections (NSG):**
```kusto
AzureDiagnostics
| where Category == "NetworkSecurityGroupEvent"
| where type_s == "event"
| where conditions_ruleName_s !contains "Allow"
| summarize count() by primaryIPv4Address_s, conditions_destinationPortRange_s
| order by count_ desc
| take 20
```

**AKS API server error rate:**
```kusto
AzureDiagnostics
| where Category == "kube-apiserver"
| where log_s contains "\"code\":5"
| summarize ErrorCount = count() by bin(TimeGenerated, 5m)
| render timechart
```

**Private endpoint connection state:**
```kusto
AzureDiagnostics
| where Category == "allLogs"
| where ResourceType == "MICROSOFT.NETWORK/PRIVATEENDPOINTS"
| project TimeGenerated, OperationName, resultType, ResourceId
```

### Network Watcher Tools

Azure Network Watcher provides the following diagnostic capabilities relevant to this topology:

| Tool | Use Case |
|------|---------|
| IP Flow Verify | Test whether a specific packet would be allowed or denied by NSG rules at a given NIC |
| Next Hop | Determine the effective next hop for a given source/destination pair (validates UDR effectiveness) |
| VPN/Connection Troubleshoot | Diagnose VPN gateway or peering connectivity issues |
| Packet Capture | On-demand pcap collection from a VM NIC for deep traffic analysis |
| Connection Monitor | Continuous end-to-end connectivity checks between endpoints (e.g., AKS pod -> Key Vault PE) |

Connection Monitor is particularly useful for tracking private endpoint reachability over time and alerting when latency or packet loss thresholds are exceeded.

---

## 10. Peering and Connectivity Patterns

### VNet Peering Fundamentals

Azure VNet peering creates a low-latency, high-bandwidth link between two VNets using the Azure backbone. Traffic does not traverse the internet. Key properties:

- Peering is non-transitive: VNet A peered to B and B peered to C does not allow A-to-C traffic without explicit A-C peering or a hub NVA.
- Peering is bidirectional but must be created in both directions (`azurerm_virtual_network_peering` resource per direction).
- Global peering (cross-region) is supported but incurs egress bandwidth charges.

### Peering Configuration Template

```hcl
# Spoke -> Hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = var.spoke_resource_group
  virtual_network_name         = module.spoke_vnet.name
  remote_virtual_network_id    = module.hub_vnet.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.hub_has_gateway  # true when ER/VPN gateway exists in hub
}

# Hub -> Spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke-prod"
  resource_group_name          = var.hub_resource_group
  virtual_network_name         = module.hub_vnet.name
  remote_virtual_network_id    = module.spoke_vnet.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true   # hub owns the gateway
  use_remote_gateways          = false
}
```

### Connectivity to On-Premises

Two options for connecting on-premises networks:

**ExpressRoute (recommended for production):**
- Private, dedicated circuit from on-premises to Azure edge.
- Consistent latency and guaranteed bandwidth (SLA-backed).
- Place the ExpressRoute Gateway in the hub VNet.
- On-premises routes are propagated via BGP to the hub and transitively to spokes via peering.

**VPN Gateway (acceptable for dev/staging or backup path):**
- IPsec tunnels over the public internet.
- Lower cost; higher latency; no bandwidth SLA.
- Can be configured as an active-active pair for redundancy.
- Point-to-Site VPN enables developer access from corporate laptops without a full site-to-site tunnel.

### Private Endpoint Peering Considerations

Private endpoints in a spoke VNet are accessible from peered VNets without additional configuration, as long as the Private DNS Zone VNet link is established for each consuming VNet. In hub-spoke, it is common to host all private endpoints in the hub and share them across spokes, which reduces the number of endpoints and DNS zone links required.

---

## 11. Firewall and NVA Considerations

### Current State: No Centralized Egress Inspection

In the current single-VNet flat model, there is no Azure Firewall or NVA. Outbound traffic from AKS nodes and services egresses directly to the internet via Azure's default internet gateway. NSGs provide inbound and lateral-movement control but not stateful Layer 7 outbound inspection.

### Azure Firewall (Recommended Path)

Azure Firewall is a stateful, managed firewall-as-a-service deployed in its own dedicated subnet (`AzureFirewallSubnet`, minimum /26). In a hub-spoke model it occupies the hub.

Capabilities relevant to this architecture:

| Feature | Value |
|---------|-------|
| FQDN-based outbound rules | Allow AKS nodes to reach specific FQDNs (e.g., `*.azurecr.io`, `mcr.microsoft.com`) rather than all of `0.0.0.0/0` |
| Threat intelligence | Block known malicious IPs and FQDNs based on Microsoft feed |
| DNS Proxy | Intercepts DNS queries; required for private endpoint DNS with custom DNS |
| TLS Inspection | Decrypt and inspect HTTPS outbound (Premium SKU) |
| Azure Monitor integration | Logs all flows to Log Analytics via diagnostic settings |

### AKS Egress with Azure Firewall

AKS has documented egress requirements that must be permitted through the firewall. Required allow rules include:

```
# Network rules
Allow UDP 1194   to AzureCloud.<region>    (tunneled API server - optional with private cluster)
Allow TCP 9000   to AzureCloud.<region>    (tunneled API server)
Allow UDP 123    to *                       (NTP)
Allow TCP 443    to AzureCloud.<region>    (management plane)

# Application rules (FQDN)
Allow HTTPS *.hcp.<region>.azmk8s.io      (AKS managed API server FQDN)
Allow HTTPS mcr.microsoft.com             (Microsoft Container Registry)
Allow HTTPS *.data.mcr.microsoft.com      (MCR CDN)
Allow HTTPS management.azure.com          (Azure management API)
Allow HTTPS login.microsoftonline.com     (Azure AD authentication)
Allow HTTPS packages.microsoft.com        (Linux package updates)
Allow HTTPS acs-mirror.azureedge.net      (AKS binaries mirror)
```

These must be codified as Terraform `azurerm_firewall_policy_rule_collection_group` resources and referenced from a `azurerm_firewall_policy` attached to the firewall instance.

### NVA Alternative

Third-party NVAs (Palo Alto, Fortinet, Check Point) can substitute for Azure Firewall when specific features are required (e.g., vendor-specific IDS/IPS signatures, existing enterprise licensing). NVAs are deployed as VM scale sets in the hub for active-active high availability. UDRs on all spoke subnets redirect traffic to the NVA's internal load balancer IP.

NVA deployment complexity is significantly higher than Azure Firewall and is only warranted when native Azure Firewall capabilities are insufficient.

---

## 12. Network Security Best Practices

### Principle: Deny by Default

The NSG module enforces deny-all inbound when no rules are supplied. This must be the baseline for every subnet. All traffic must be explicitly permitted, not implicitly allowed.

### Principle: Least-Privilege Subnet Isolation

Each subnet communicates only with the subnets and services it requires. Lateral movement between unrelated subnets (e.g., App Gateway subnet directly to Private Endpoint subnet) should have no allow rules.

### Principle: Private-Only PaaS Access

All PaaS services (Key Vault, Storage, ACR) must have:
1. A private endpoint in 10.0.5.0/24.
2. Public network access disabled on the resource itself.
3. An Azure Policy assignment preventing re-enablement of public access.

This ensures that even if an NSG rule is misconfigured, PaaS data cannot be accessed over the internet.

### Principle: No Persistent Administrative Access

No SSH or RDP ports should be open in any NSG. Administrative access to AKS nodes uses:
- Azure Bastion (when needed) - requires its own dedicated `AzureBastionSubnet` (/26 minimum).
- `kubectl debug` with ephemeral containers for node-level troubleshooting.
- AKS Run Command for one-off control plane interactions without direct SSH.

### Principle: Immutable NSG Rules

NSG rules are managed exclusively through Terraform. No portal or CLI edits. The CI/CD pipeline enforces this via `azurerm_subscription_policy_assignment` with the `Deny` effect for manual NSG rule modifications, or via drift detection in the Terraform plan step.

### Principle: Encryption in Transit

All traffic between AKS workloads and PaaS backends traverses private endpoints but must still use TLS:
- Key Vault SDK enforces TLS by default.
- Storage SDK uses HTTPS endpoints (`https://*.blob.core.windows.net`).
- ACR image pulls use HTTPS/TLS.
- Enforce `"Secure transfer required"` on storage accounts and `"HTTPS Only"` on App Service / Function Apps via Azure Policy.

### Principle: JIT for Elevated Network Access

For temporary network access requirements (e.g., one-time database migration requiring SQL port access), use Microsoft Defender for Cloud Just-In-Time (JIT) VM access or time-bounded NSG rule automation via Logic Apps. Never permanently open administrative ports.

### Network Security Checklist

| Control | Implementation |
|---------|---------------|
| Default deny on all NSGs | NSG module auto-inserts priority 4096 deny rule |
| PaaS public access disabled | Azure Policy enforcement + private endpoints |
| No internet-exposed management ports | NSG rules; no SSH/RDP inbound |
| VNet flow logs enabled | `azurerm_network_watcher_flow_log` (add to roadmap) |
| Private endpoint DNS auto-registration | DNS zone groups in private-endpoint module |
| AKS API server not publicly accessible | Configure `api_server_access_profile` with `authorized_ip_ranges` or private cluster mode |
| TLS enforced on all PaaS endpoints | Azure Policy; SDK defaults |
| NSG diagnostic logs to Log Analytics | NSG module `log_analytics_workspace_id` variable |
| No use of service tags as trust boundaries alone | Combine service tags with IP prefix restrictions where possible |
| Kubernetes NetworkPolicy enforced | `network_policy = "azure"` enables Azure NPM |

---

## Appendix: Module Reference

| Module | Path | Network Resources Created |
|--------|------|--------------------------|
| `virtual-network` | `modules/virtual-network/` | `azurerm_virtual_network`, diagnostic setting |
| `subnet` | `modules/subnet/` | `azurerm_subnet`, optional NSG association |
| `network-security-group` | `modules/network-security-group/` | `azurerm_network_security_group`, diagnostic setting |
| `private-endpoint` | `modules/private-endpoint/` | `azurerm_private_endpoint`, private service connection, optional DNS zone group |
| `aks-cluster` | `modules/aks-cluster/` | `azurerm_kubernetes_cluster`, additional node pools, diagnostic setting |

## Appendix: Key CIDR Reference

| Block | Subnet | Size | Notes |
|-------|--------|------|-------|
| 10.0.0.0/16 | VNet | 65,534 IPs | Parent address space |
| 10.0.0.0/22 | AKS nodes | 1,022 IPs | CNI Overlay; node NICs only |
| 10.0.4.0/24 | Services | 254 IPs | Internal services |
| 10.0.5.0/24 | Private Endpoints | 254 IPs | PaaS private NICs |
| 10.0.6.0/24 | App Gateway | 254 IPs | Dedicated; required by Azure |
| 10.0.7.0/24+ | Reserved | - | Future subnets |
| 172.16.0.0/16 | Kubernetes services | 65,534 ClusterIPs | Non-VNet; cluster-internal |
| 172.16.0.10 | CoreDNS ClusterIP | Single IP | Must be within service_cidr |
