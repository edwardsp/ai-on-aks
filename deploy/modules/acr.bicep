param location string
param acrName string
param subnetId string
param acrPrivateDNSZoneName string

var acrPleBlobName = '${acrName}-pe'

resource acrPrivateDNSZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: acrPrivateDNSZoneName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    dataEndpointEnabled: false
    networkRuleSet: {
      defaultAction: 'Deny'
    }
    publicNetworkAccess: 'Disabled'
  }
}

resource acrPrivateEndpointBlob 'Microsoft.Network/privateEndpoints@2022-01-01' = {
  name: acrPleBlobName
  location: location
  properties: {
    privateLinkServiceConnections: [
      { 
        name: acrPleBlobName
        properties: {
          groupIds: [
            'registry'
          ]
          privateLinkServiceId: acr.id
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-01-01' = {
  name: '${acrPrivateEndpointBlob.name}/registry-PrivateDnsZoneGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: acrPrivateDNSZoneName
        properties:{
          privateDnsZoneId: acrPrivateDNSZone.id
        }
      }
    ]
  }
}
