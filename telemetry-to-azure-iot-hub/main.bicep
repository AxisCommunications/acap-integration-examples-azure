// Azure Bicep template deploying the required resources to send telemetry from
// an Axis camera to Azure IoT Hub.
//
// The template can be deployed from a command-line interface using the
// following command.
//
//   az deployment group create -g <resource group> -f main.bicep --parameters \
//     objectId=$(az ad signed-in-user show --query id --output tsv) \
//     organizationName=<organization name>

@description('''
  The object ID of your Azure Active Directory user. The object ID can be found
  either by navigating to your user in Azure Active Directory, or by running the
  following command in the Azure Cloud Shell:
  'az ad signed-in-user show --query id --output tsv'.
  ''')
param objectId string

@description('''
  The name of your organization, used when generating the X.509 certificates.
  ''')
param organizationName string

@description('''
  The prefix of the IoT Hub name. A generated hash will be appended to the name,
  guaranteeing its uniqueness on Azure.
  ''')
param iotHubNamePrefix string = 'axis-telemetry'

@description('''
  The name of the IoT device, used for authentication and access control.
  ''')
param deviceIdentity string = 'device01'

@description('The location to deploy all resources in.')
param location string = resourceGroup().location

var tenantId = subscription().tenantId
var hash = uniqueString(resourceGroup().id)

// -----------------------------------------------------------------------------
// Azure IoT Hub receiving telemetry from the Axis camera
// -----------------------------------------------------------------------------

resource iotHub 'Microsoft.Devices/IotHubs@2021-03-31' = {
  name: '${iotHubNamePrefix}-${hash}'
  location: location
  sku: {
    name: 'S1'
    capacity: 1
  }
}

// -----------------------------------------------------------------------------
// User responsible for generating X.509 certificates and uploading them to
// Azure Key Vault
// -----------------------------------------------------------------------------

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'telemetry-to-azure-iot-hub'
  location: location
}

// Contributor built-in role
// https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#contributor
var contributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid(resourceGroup().id, 'contributor')
  scope: resourceGroup()
  properties: {
    principalId: identity.properties.principalId
    roleDefinitionId: contributorRoleId
    principalType: 'ServicePrincipal'
  }
}

// -----------------------------------------------------------------------------
// Key Vault containing X.509 certificates
// -----------------------------------------------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: 'keyvault-${hash}'
  location: location
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: objectId
        permissions: {
          certificates: [
            'all'
          ]
          secrets: [
            'all'
          ]
        }
      }
      {
        tenantId: tenantId
        objectId: identity.properties.principalId
        permissions: {
          certificates: [
            'all'
          ]
          secrets: [
            'all'
          ]
        }
      }
    ]
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
  }
}

// -----------------------------------------------------------------------------
// Deployment script responsible for generating the X.509 certificates and
// uploading them to Azure Key Vault
// -----------------------------------------------------------------------------

resource certificates 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'certificates'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', identity.name)}': {}
    }
  }
  properties: {
    azCliVersion: '2.28.0'
    retentionInterval: 'P1D'
    arguments: '\\"${organizationName}\\" \\"${resourceGroup().name}\\" \\"${iotHub.name}\\" \\"${deviceIdentity}\\" \\"${keyVault.name}\\"'
    scriptContent: '''
      organization_name="$1"
      resource_group_name="$2"
      iot_hub_name="$3"
      device_identity="$4"
      key_vault_name="$5"

      # We want to use X.509 certificates to authenticate our camera to the IoT Hub.
      # We will create two certificates. The first is the Certificate Authority (CA)
      # certificate, which we later on will upload to the IoT Hub. All device
      # certificates should be generated from this CA certificate.
      openssl genrsa -out ca.key 4096
      openssl req -x509 -new -nodes -key ca.key -sha256 -days 365 \
        -subj "/O=$organization_name/CN=$organization_name" -out ca.pem
      openssl pkcs12 -inkey ca.key -in ca.pem -export -passout pass: \
        -out ca.pfx

      # The second certificate is a device certificate which is derived from the CA
      # certificate. This certificate should be uploaded to the camera. Please note
      # that each device we connect to the IoT Hub requires a unique identity name.
      openssl genrsa -out device.key 2048
      openssl req -new -key device.key -subj "/CN=$device_identity" -out device.csr
      openssl x509 -req -in device.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
        -days 365 -sha256 -out device.pem
      openssl pkcs12 -inkey device.key -in device.pem -export -passout pass: \
        -out device.pfx

      # Install the Azure IoT extension.
      az extension add --name azure-iot

      # At this point we're ready to upload the CA certificate to the IoT Hub.
      az iot hub certificate create --hub-name "$iot_hub_name" --name ca \
        --path ca.pem --verified

      # Our CA certificate is now uploaded and verified, and we are ready to
      # create our device identity in the IoT Hub.
      az iot hub device-identity create --resource-group "$resource_group_name" \
        --hub-name "$iot_hub_name" --device-id "$device_identity" \
        --auth-method x509_ca

      # For future reference, upload the CA certificate and the device
      # certificate to Azure Key Vault.
      az keyvault certificate import --vault-name "$key_vault_name" --name ca \
        --file ca.pfx
      az keyvault certificate import --vault-name "$key_vault_name" --name device \
        --file device.pfx
    '''
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

// The MQTT host the camera should connect to
output host string = iotHub.properties.hostName

// The username the camera should use when connecting to the MQTT host
output username string = '${iotHub.properties.hostName}/${deviceIdentity}/?api-version=2018-06-30'

// The client ID the camera should use when connecting to the MQTT host
output clientId string = deviceIdentity
