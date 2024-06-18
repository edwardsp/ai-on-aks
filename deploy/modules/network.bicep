param location string
param config object

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: config.name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        config.ipRange
      ]
    }
    subnets: [for sub in config.subnets: {
        name: sub.name
        properties: {
          addressPrefix: sub.ipRange
          delegations: sub.delegations
        }
    }]
  }
}

output vnetId string = virtualNetwork.id
output vnetName string = virtualNetwork.name
output subnetIds object = reduce(
  map(
    config.subnets,
    subnet => {
      '${subnet.name}': filter(
        virtualNetwork.properties.subnets, (s) => s.name == subnet.name
      )[0].id
    }
  ),
  {},
  (cur, next) => union(cur, next)
)
