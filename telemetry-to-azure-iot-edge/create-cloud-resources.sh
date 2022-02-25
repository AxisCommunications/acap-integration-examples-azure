#!/bin/bash
set -e

if [[ $# -ne 5 ]]; then
  echo "Error: Unsupported number of arguments"
  echo
  echo "USAGE:"
  echo "    create-cloud-resources.sh <resource group name> <location> <iot hub name> <edge gateway hostname> <device identity>"
  echo
  echo "WHERE:"
  echo "    resource group name     The name of a new or existing resource group in Azure, e.g."
  echo "                            'MyResourceGroup'"
  echo "    location                The name of the Azure location where the resources should be"
  echo "                            created, e.g. 'eastus' for East US"
  echo "    iot hub name            The name of the IoT Hub resource, e.g. 'my-iot-hub'"
  echo "    edge gateway hostname   The hostname of the Azure IoT Edge gateway, i.e. a name on the"
  echo "                            network that resolves into a IPv4 address that points to the"
  echo "                            computer where we will install Azure IoT Edge, e.g."
  echo "                            'azureiotedgedevice'. This hostname will also be used as the"
  echo "                            identity of the IoT Edge device in Azure IoT Hub."
  echo "    device identity         The identity of the device in Azure IoT Hub, e.g. 'device01'"
  echo

  exit 1
fi

resource_group_name=$1
location=$2
iot_hub_name=$3
edge_device_hostname=$4
device_identity=$5

# ------------------------------------------------------------------------------
# CERTIFICATES
# ------------------------------------------------------------------------------

ca_cert_name=ca
ca_cert_path=./cert/ca.pem

if [[ ! -f "$ca_cert_path" ]]; then
  echo "Root Certificate Authory (CA) certificate does not exist in local"
  echo "directory, run create-certificates.sh to create it."
  exit 1
fi

local_ca_certificate_thumbprint=$(openssl x509 -in $ca_cert_path -fingerprint -noout |
  sed -E 's|:||g' |
  cut -f2 -d'=')

# ------------------------------------------------------------------------------
# PROVISION AZURE RESOURCES
# ------------------------------------------------------------------------------

# To keep all resources in Azure grouped together we want to create a new
# resource group.
echo "Creating resource group '$resource_group_name' in '$location' if it does not exist..."
az group create \
  --name "$resource_group_name" \
  --location "$location" \
  --output none

# Next we create the IoT Hub. We select the S1 tier and a capacity of 1 unit,
# which is enough to test this application.
echo "Checking if IoT Hub '$iot_hub_name' in resource group '$resource_group_name' exists..."
if [[ $(az iot hub list --query "[?name=='$iot_hub_name' && resourcegroup=='$resource_group_name'] | length(@)") -ne 1 ]]; then
  echo "IoT Hub does not exist, creating it..."
  az iot hub create \
    --name "$iot_hub_name" \
    --resource-group "$resource_group_name" \
    --location "$location" \
    --sku S1 \
    --unit 1 \
    --output none
fi

# With the IoT Hub created, let's upload the root CA certificate.
echo "Checking if root CA certificate is uploaded to IoT Hub..."
if [[ $(az iot hub certificate list --hub-name "$iot_hub_name" --query "value[?name=='$ca_cert_name' && properties.thumbprint=='$local_ca_certificate_thumbprint'] | length(@)") -ne 1 ]]; then
  echo "IoT Hub root CA certificate does not exist, uploading local root CA certificate..."
  az iot hub certificate create \
    --resource-group "$resource_group_name" \
    --hub-name "$iot_hub_name" \
    --name "$ca_cert_name" \
    --path "$ca_cert_path" \
    --verified \
    --output none
fi

# Our root CA certificate is now uploaded and verified, and we can create our
# device identity, representing the Axis camera, in the IoT Hub.
echo "Checking if device identity exists in IoT Hub..."
if [[ $(az iot hub device-identity list --hub-name "$iot_hub_name" --query "[?deviceId=='$device_identity' && capabilities.iotEdge==\`false\`] | length(@)") -ne 1 ]]; then
  echo "Device identity '$device_identity' does not exist in IoT Hub, creating it..."
  az iot hub device-identity create \
    --resource-group "$resource_group_name" \
    --hub-name "$iot_hub_name" \
    --device-id "$device_identity" \
    --auth-method x509_ca \
    --output none
fi

# We are now ready to create the IoT Edge device, a.k.a. the transparent
# gateway, and add the Axis camera as a child to the IoT Edge device.
echo "Checking if IoT Edge device identity exists in IoT Hub..."
if [[ $(az iot hub device-identity list --hub-name "$iot_hub_name" --query "[?deviceId=='$edge_device_hostname' && capabilities.iotEdge] | length(@)") -ne 1 ]]; then
  echo "IoT Edge device identity '$edge_device_hostname' does not exist in IoT Hub, creating it..."
  az iot hub device-identity create \
    --resource-group "$resource_group_name" \
    --hub-name "$iot_hub_name" \
    --device-id "$edge_device_hostname" \
    --edge-enabled \
    --auth-method x509_ca \
    --output none

  az iot hub device-identity children add \
    --resource-group "$resource_group_name" \
    --hub-name "$iot_hub_name" \
    --device-id "$edge_device_hostname" \
    --child-list "$device_identity"
fi

# With the IoT Edge device created, let's make sure that a deployment manifest
# is ready for the IoT Edge device when it first connects to the IoT Hub.
echo "Setting default modules on IoT Edge device..."
az iot edge set-modules \
  --hub-name "$iot_hub_name" \
  --device-id "$edge_device_hostname" \
  --content ./edge-gateway.deployment.json \
  --output none

# ------------------------------------------------------------------------------
# OUTPUT
# ------------------------------------------------------------------------------

echo
echo "Done!"
echo
echo "The following settings will be used when configuring the camera."
echo
echo "MQTT Client Configuration"
echo "Host:       $edge_device_hostname"
echo "Username:   $edge_device_hostname/$device_identity/?api-version=2018-06-30"
echo "Client id:  $device_identity"
echo
echo "MQTT Event Configuration"
echo "Custom condition prefix:  devices/$device_identity/messages/events/"
echo
