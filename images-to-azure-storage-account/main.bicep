// Azure Bicep template deploying the required resources to send images from an
// Axis camera to an Azure storage account.
//
// The template can be deployed from a command-line interface using the
// following command.
//
//   az deployment group create -g <resource group> -f main.bicep --parameters \
//     publisherEmail=<e-mail address>

@description('Email address to receive system notifications sent from API Management.')
param publisherEmail string

@description('The location to deploy all resources in.')
param location string = resourceGroup().location

var commonName = 'image-upload-${uniqueString(resourceGroup().id)}'

// -----------------------------------------------------------------------------
// Azure storage account receiving the images from the Axis camera.
// -----------------------------------------------------------------------------

// storage-blob-data-contributor built-in role
// https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'image${uniqueString(resourceGroup().id)}'
  location: location
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

// -----------------------------------------------------------------------------
// Azure API Management authorizing and forwarding incomming requests to the
// Azure storage account.
// -----------------------------------------------------------------------------

resource apiService 'Microsoft.ApiManagement/service@2021-01-01-preview' = {
  name: commonName
  location: location
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
          value: '''
            <policies>
              <inbound>
                <base />
              </inbound>
              <backend>
                <base />
              </backend>
              <outbound>
                <base />
                <mock-response status-code="200" content-type="application/json" />
              </outbound>
              <on-error>
                <base />
              </on-error>
            </policies>
          '''
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
          value: '''
            <policies>
              <inbound>
                <check-header name="Content-Type" failed-check-httpcode="400" failed-check-error-message="Unsupported Content-Type header, use image/jpeg">
                  <value>image/jpeg</value>
                </check-header>
                <check-header name="content-disposition" failed-check-httpcode="400" failed-check-error-message="Missing header content-disposition" />
                <set-variable name="BlobName" value="@{
                  string contentDisposition = context.Request.Headers.GetValueOrDefault("content-disposition");
                  var regex = new Regex("filename=\"(?<filename>.*)\"");
                  var match = regex.Match(contentDisposition);
                  var filename = match.Groups["filename"].Value;
                  return filename;
                }" />
                <choose>
                  <when condition="@(context.Variables.GetValueOrDefault("BlobName") == "")">
                    <return-response>
                      <set-status code="400" reason="Bad request" />
                      <set-body>@(new JObject(new JProperty("statusCode", 400), new JProperty("message", "Incorrect format provided in content-disposition header")).ToString())</set-body>
                    </return-response>
                  </when>
                </choose>
                <base />
                <set-variable name="BlobEndpoint" value="{{BlobEndpoint}}" />
                <set-variable name="ContainerName" value="{{ContainerName}}" />
                <set-method>PUT</set-method>
                <set-header name="x-ms-version" exists-action="override">
                  <value>2020-06-12</value>
                </set-header>
                <set-header name="x-ms-blob-type" exists-action="override">
                  <value>BlockBlob</value>
                </set-header>
                <set-backend-service base-url="@{
                  string blobEndpoint = context.Variables.GetValueOrDefault<string>("BlobEndpoint");
                  string containerName = context.Variables.GetValueOrDefault<string>("ContainerName");
                  string blobName = context.Variables.GetValueOrDefault<string>("BlobName");
                  return String.Format("{0}{1}/{2}", blobEndpoint, containerName, blobName);
                }" />
                <authentication-managed-identity resource="https://storage.azure.com/" />
              </inbound>
              <backend>
                <base />
              </backend>
              <outbound>
                <base />
              </outbound>
              <on-error>
                <base />
              </on-error>
            </policies>
          '''
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

// The HTTPS endpoint the camera should send images to
output endpoint string = '${apiService.properties.gatewayUrl}?accessToken=${apiService::subscription.properties.primaryKey}'
