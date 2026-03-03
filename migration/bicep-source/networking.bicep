// networking.bicep
// Bicep template for Virtual Network + Subnets + Network Security Group
// This is the source template being migrated to Terraform (see modules/virtual-network/, modules/subnet/, modules/network-security-group/)

@description('Name of the virtual network')
param vnetName string

@description('Azure region')
param location string = resourceGroup().location

@description('Address space for the virtual network')
param addressPrefixes array = [
  '10.0.0.0/16'
]

@description('Custom DNS servers (empty for Azure default)')
param dnsServers array = []

@description('Subnet configurations')
param subnets array = [
  {
    name: 'snet-aks'
    addressPrefix: '10.0.0.0/22'
    serviceEndpoints: [ 'Microsoft.Storage', 'Microsoft.KeyVault' ]
    privateEndpointNetworkPolicies: 'Disabled'
    nsgName: 'nsg-aks'
  }
  {
    name: 'snet-app'
    addressPrefix: '10.0.4.0/24'
    serviceEndpoints: [ 'Microsoft.Storage', 'Microsoft.Sql' ]
    privateEndpointNetworkPolicies: 'Disabled'
    nsgName: 'nsg-app'
  }
  {
    name: 'snet-data'
    addressPrefix: '10.0.5.0/24'
    serviceEndpoints: [ 'Microsoft.Storage' ]
    privateEndpointNetworkPolicies: 'Disabled'
    nsgName: 'nsg-data'
  }
  {
    name: 'snet-pep'
    addressPrefix: '10.0.6.0/24'
    serviceEndpoints: []
    privateEndpointNetworkPolicies: 'Disabled'
    nsgName: ''
  }
]

@description('NSG configurations with security rules')
param nsgConfigs array = [
  {
    name: 'nsg-aks'
    rules: [
      {
        name: 'AllowHTTPS'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: 'Internet'
        destinationAddressPrefix: 'VirtualNetwork'
        sourcePortRange: '*'
        destinationPortRange: '443'
      }
      {
        name: 'AllowKubelet'
        priority: 110
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: 'VirtualNetwork'
        destinationAddressPrefix: 'VirtualNetwork'
        sourcePortRange: '*'
        destinationPortRange: '10250'
      }
    ]
  }
  {
    name: 'nsg-app'
    rules: [
      {
        name: 'AllowAppPort'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.0.0.0/22'
        destinationAddressPrefix: '10.0.4.0/24'
        sourcePortRange: '*'
        destinationPortRange: '8080'
      }
    ]
  }
  {
    name: 'nsg-data'
    rules: [
      {
        name: 'AllowSqlFromApp'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourceAddressPrefix: '10.0.4.0/24'
        destinationAddressPrefix: '10.0.5.0/24'
        sourcePortRange: '*'
        destinationPortRange: '1433'
      }
      {
        name: 'DenyAllInbound'
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
        sourcePortRange: '*'
        destinationPortRange: '*'
      }
    ]
  }
]

@description('Log Analytics workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

@description('Resource tags')
param tags object = {}

// Network Security Groups
resource nsgs 'Microsoft.Network/networkSecurityGroups@2023-11-01' = [
  for nsg in nsgConfigs: {
    name: nsg.name
    location: location
    properties: {
      securityRules: [
        for rule in nsg.rules: {
          name: rule.name
          properties: {
            priority: rule.priority
            direction: rule.direction
            access: rule.access
            protocol: rule.protocol
            sourceAddressPrefix: rule.sourceAddressPrefix
            destinationAddressPrefix: rule.destinationAddressPrefix
            sourcePortRange: rule.sourcePortRange
            destinationPortRange: rule.destinationPortRange
          }
        }
      ]
    }
    tags: tags
  }
]

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    dhcpOptions: !empty(dnsServers) ? {
      dnsServers: dnsServers
    } : null
    subnets: [
      for subnet in subnets: {
        name: subnet.name
        properties: {
          addressPrefix: subnet.addressPrefix
          serviceEndpoints: [
            for se in subnet.serviceEndpoints: {
              service: se
            }
          ]
          privateEndpointNetworkPolicies: subnet.privateEndpointNetworkPolicies
          networkSecurityGroup: !empty(subnet.nsgName) ? {
            id: resourceId('Microsoft.Network/networkSecurityGroups', subnet.nsgName)
          } : null
        }
      }
    ]
  }
  tags: tags
  dependsOn: [
    nsgs
  ]
}

// VNet diagnostic settings
resource vnetDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${vnetName}-diag'
  scope: vnet
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
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

// NSG diagnostic settings
resource nsgDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [
  for (nsg, i) in nsgConfigs: if (!empty(logAnalyticsWorkspaceId)) {
    name: '${nsg.name}-diag'
    scope: nsgs[i]
    properties: {
      workspaceId: logAnalyticsWorkspaceId
      logs: [
        {
          categoryGroup: 'allLogs'
          enabled: true
        }
      ]
    }
  }
]

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output subnetIds array = [for (subnet, i) in subnets: vnet.properties.subnets[i].id]
output subnetNames array = [for subnet in subnets: subnet.name]
output nsgIds array = [for (nsg, i) in nsgConfigs: nsgs[i].id]
