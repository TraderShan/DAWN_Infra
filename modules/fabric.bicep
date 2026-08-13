// Microsoft Fabric capacity.

param location string
param tags object
param name string
param skuName string
param adminMembers array

resource fabric 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: adminMembers
    }
  }
}

output id string = fabric.id
output name string = fabric.name
