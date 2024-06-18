param location string
param subnetId string
param username string
@secure()
param publicKey string


resource loginNodeNSG 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'loginNodeNSG'
  location: location
}

resource loginNodeNIC 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'loginNodeNIC'
  location: location
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: loginNodeNSG.id
    }
  }
}

resource loginNode 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: 'login'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D8s_v5'
    }
    storageProfile: {
      osDisk: {
        name: 'loginNodeOSDisk'
        createOption: 'fromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 512
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: loginNodeNIC.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    osProfile: {
      computerName: 'loginNode'
      adminUsername: username
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${username}/.ssh/authorized_keys'
              keyData: publicKey
            }
          ]
        }
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}


output name string = loginNode.name
output id string = loginNode.id
output adminUser string = loginNode.properties.osProfile.adminUsername
output privateIp string = loginNodeNIC.properties.ipConfigurations[0].properties.privateIPAddress
