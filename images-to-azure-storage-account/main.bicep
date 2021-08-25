@description('E-mail address to receive system notifications sent from API Management.')
param publisherEmail string

var commonName = 'image-upload-${uniqueString(resourceGroup().id)}'

// storage-blob-data-contributor built-in role
// https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource storage 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: 'image${uniqueString(resourceGroup().id)}'
  location: resourceGroup().location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'

  resource blobService 'blobServices' = {
    name: 'default'

    resource container 'containers' = {
      name: 'images'
    }
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid(resourceGroup().id)
  scope: storage::blobService::container
  properties: {
    principalId: apiService.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
  }
}

resource apiService 'Microsoft.ApiManagement/service@2021-01-01-preview' = {
  name: commonName
  location: resourceGroup().location
  sku: {
    capacity: 0
    name: 'Consumption'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: commonName
  }

  resource subscription 'subscriptions' = {
    name: 'AxisDeviceSubscription'
    properties: {
      scope: apiService::api.id
      displayName: 'Axis Device Subscription'
    }
  }

  resource blobEndpoint 'namedValues' = {
    name: 'BlobEndpoint'
    properties: {
      displayName: 'BlobEndpoint'
      value: storage.properties.primaryEndpoints.blob
    }
  }

  resource containerName 'namedValues' = {
    name: 'ContainerName'
    properties: {
      displayName: 'ContainerName'
      value: storage::blobService::container.name
    }
  }

  resource api 'apis' = {
    name: 'azurestorage'
    properties: {
      displayName: 'AzureStorage'
      subscriptionRequired: true
      subscriptionKeyParameterNames: {
        query: 'accessToken'
      }
      serviceUrl: storage.properties.primaryEndpoints.blob
      protocols: [
        'https'
      ]
      path: '/'
    }

    resource getOperation 'operations' = {
      name: 'get'
      properties: {
        displayName: 'Test recipient'
        urlTemplate: '/'
        method: 'GET'
      }

      resource policy 'policies' = {
        name: 'policy'
        properties: {
          format: 'rawxml'
          value: loadTextContent('./policy-get.xml')
        }
      }
    }

    resource postOperation 'operations' = {
      name: 'post'
      properties: {
        displayName: 'Send image'
        urlTemplate: '/'
        method: 'POST'
      }

      resource policy 'policies' = {
        name: 'policy'
        properties: {
          format: 'rawxml'
          value: loadTextContent('./policy-post.xml')
        }
      }
    }
  }
}

output endpoint string = '${apiService.properties.gatewayUrl}?accessToken=${apiService::subscription.properties.primaryKey}'
