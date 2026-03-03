// aks-cluster.bicep
// Bicep template for Azure Kubernetes Service (AKS) cluster
// This is the source template being migrated to Terraform (see modules/aks-cluster/)

@description('The name of the AKS cluster')
param clusterName string

@description('Azure region')
param location string = resourceGroup().location

@description('DNS prefix for the cluster')
param dnsPrefix string

@description('Kubernetes version')
param kubernetesVersion string = '1.29'

@description('AKS SKU tier')
@allowed([
  'Free'
  'Standard'
  'Premium'
])
param skuTier string = 'Standard'

@description('Enable RBAC')
param enableRbac bool = true

@description('Enable OIDC issuer')
param enableOidcIssuer bool = true

@description('Enable workload identity')
param enableWorkloadIdentity bool = true

@description('Enable Azure Policy add-on')
param enableAzurePolicy bool = true

@description('Identity type for the cluster')
@allowed([
  'SystemAssigned'
  'UserAssigned'
])
param identityType string = 'UserAssigned'

@description('User-assigned identity resource ID (required when identityType is UserAssigned)')
param userAssignedIdentityId string = ''

@description('Default node pool configuration')
param defaultNodePool object = {
  name: 'system'
  vmSize: 'Standard_D4s_v5'
  minCount: 2
  maxCount: 5
  osDiskSizeGB: 128
  osSku: 'AzureLinux'
  zones: [ '1', '2', '3' ]
  maxPods: 50
  onlyCriticalAddonsEnabled: true
  vnetSubnetId: ''
}

@description('Additional node pool configurations')
param additionalNodePools array = [
  {
    name: 'workload'
    vmSize: 'Standard_D8s_v5'
    minCount: 1
    maxCount: 10
    osDiskSizeGB: 128
    osSku: 'AzureLinux'
    zones: [ '1', '2', '3' ]
    maxPods: 50
    mode: 'User'
    nodeLabels: {
      workload: 'general'
    }
    nodeTaints: []
    vnetSubnetId: ''
  }
]

@description('Network plugin')
@allowed([
  'azure'
  'kubenet'
  'none'
])
param networkPlugin string = 'azure'

@description('Network plugin mode')
param networkPluginMode string = 'overlay'

@description('Network policy')
@allowed([
  'azure'
  'calico'
  'cilium'
])
param networkPolicy string = 'cilium'

@description('Service CIDR')
param serviceCidr string = '172.16.0.0/16'

@description('DNS service IP')
param dnsServiceIP string = '172.16.0.10'

@description('AAD admin group object IDs')
param adminGroupObjectIds array = []

@description('Enable Azure RBAC for Kubernetes authorization')
param enableAzureRbac bool = true

@description('Maintenance window configuration')
param maintenanceWindow object = {
  allowed: [
    {
      day: 'Saturday'
      hours: [ 0, 1, 2, 3, 4 ]
    }
    {
      day: 'Sunday'
      hours: [ 0, 1, 2, 3, 4 ]
    }
  ]
}

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string = ''

@description('Resource tags')
param tags object = {}

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: clusterName
  location: location
  sku: {
    name: 'Base'
    tier: skuTier
  }
  identity: identityType == 'UserAssigned' ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    enableRBAC: enableRbac
    oidcIssuerProfile: {
      enabled: enableOidcIssuer
    }
    securityProfile: {
      workloadIdentity: {
        enabled: enableWorkloadIdentity
      }
    }
    azurePolicyEnabled: enableAzurePolicy
    agentPoolProfiles: [
      {
        name: defaultNodePool.name
        mode: 'System'
        vmSize: defaultNodePool.vmSize
        enableAutoScaling: true
        minCount: defaultNodePool.minCount
        maxCount: defaultNodePool.maxCount
        osDiskSizeGB: defaultNodePool.osDiskSizeGB
        osSKU: defaultNodePool.osSku
        availabilityZones: defaultNodePool.zones
        maxPods: defaultNodePool.maxPods
        onlyCriticalAddonsEnabled: defaultNodePool.onlyCriticalAddonsEnabled
        vnetSubnetID: !empty(defaultNodePool.vnetSubnetId) ? defaultNodePool.vnetSubnetId : null
        type: 'VirtualMachineScaleSets'
      }
    ]
    networkProfile: {
      networkPlugin: networkPlugin
      networkPluginMode: networkPluginMode
      networkPolicy: networkPolicy
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: enableAzureRbac
      adminGroupObjectIDs: adminGroupObjectIds
    }
    addonProfiles: !empty(logAnalyticsWorkspaceId) ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    } : {}
    maintenanceWindow: maintenanceWindow
  }
  tags: tags
}

// Additional Node Pools
resource nodePools 'Microsoft.ContainerService/managedClusters/agentPools@2024-01-01' = [
  for pool in additionalNodePools: {
    parent: aksCluster
    name: pool.name
    properties: {
      mode: pool.mode
      vmSize: pool.vmSize
      enableAutoScaling: true
      minCount: pool.minCount
      maxCount: pool.maxCount
      osDiskSizeGB: pool.osDiskSizeGB
      osSKU: pool.osSku
      availabilityZones: pool.zones
      maxPods: pool.maxPods
      nodeLabels: contains(pool, 'nodeLabels') ? pool.nodeLabels : {}
      nodeTaints: contains(pool, 'nodeTaints') ? pool.nodeTaints : []
      vnetSubnetID: !empty(pool.vnetSubnetId) ? pool.vnetSubnetId : null
      type: 'VirtualMachineScaleSets'
    }
  }
]

// Diagnostic settings
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${clusterName}-diag'
  scope: aksCluster
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
      }
      {
        category: 'kube-audit-admin'
        enabled: true
      }
      {
        category: 'guard'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Outputs
output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output clusterFqdn string = aksCluster.properties.fqdn
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup
