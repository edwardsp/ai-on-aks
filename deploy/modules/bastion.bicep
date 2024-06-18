param location string
param subnetId string

resource bastionPIP 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'bastionPIP'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: 'bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: bastionPIP.id
          }
        }
      }
    ]
  }
}

output name string = bastionHost.name
