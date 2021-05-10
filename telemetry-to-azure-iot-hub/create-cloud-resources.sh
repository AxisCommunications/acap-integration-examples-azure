#!/bin/bash
set -e

if [[ $# -ne 4 ]] ; then
  echo "Error: Unsupported number of arguments"
  echo
  echo "USAGE:"
  echo "    create-cloud-resources.sh <resource group name> <location> <iot hub name> <device identity name>"
  echo
  echo "WHERE:"
  echo "    resource group name   The name of a new or existing resource group in Azure"
  echo "    location              The name of the Azure location where the resources"
  echo "                          should be created, e.g. eastus for East US"
  echo "    iot hub name          The name of the IoT Hub resource"
  echo "    device identity name  The identity of the device in IoT Hub"
  echo

  exit 1
fi

resource_group_name=$1
location=$2
iot_hub_name=$3
device_identity_name=$4

echo "Creating resource group '$resource_group_name' in '$location' if it does not exist..."
az group create \
  --name "$resource_group_name" \
  --location "$location" \
  --output none

echo "Checking if IoT Hub '$iot_hub_name' in resource group '$resource_group_name' exists..."
if [[ $(az iot hub list --query "[?name=='$iot_hub_name' && resourcegroup=='$resource_group_name'] | length(@)") -ne 1 ]] ; then
  echo "IoT Hub does not exist, creating it..."
  az iot hub create \
    --name "$iot_hub_name" \
    --resource-group "$resource_group_name" \
    --location "$location" \
    --sku S1 \
    --unit 1 \
    --output none
fi

cert_directory=cert
ca_cert_org=example.com
mkdir -p $cert_directory
ca_key_path=./$cert_directory/ca.key
ca_cert_path=./$cert_directory/ca.pem
device_key_path=./$cert_directory/$device_identity_name.key
device_csr_path=./$cert_directory/$device_identity_name.csr
device_cert_path=./$cert_directory/$device_identity_name.crt
proof_key_path=./$cert_directory/proof.key
proof_csr_path=./$cert_directory/proof.csr
proof_cert_path=./$cert_directory/proof.pem
ca_certificate_name=ca

echo "Checking local directory for CA certificate..."
if [[ ! -f "$ca_key_path" && ! -f "$ca_cert_path" ]] ; then
  echo "CA certificate does not exist in local directory, creating it..."
  openssl genrsa -out $ca_key_path 2048
  openssl req -x509 -new -nodes -key $ca_key_path -sha256 -days 3650 -subj "/O=$ca_cert_org/CN=$ca_cert_org" -out $ca_cert_path
fi
local_ca_certificate_thumbprint=$(openssl x509 -in $ca_cert_path -fingerprint -noout | sed -E 's|:||g' | cut -f2 -d'=')

echo "Checking if CA certificate is uploaded to IoT Hub..."
if [[ $(az iot hub certificate list --hub-name "$iot_hub_name" --query "value[?name=='$ca_certificate_name' && properties.thumbprint=='$local_ca_certificate_thumbprint'] | length(@)") -ne 1  ]] ; then
  echo "IoT Hub CA certificate does not exist, uploading local CA certificate..."
  az iot hub certificate create \
    --resource-group "$resource_group_name" \
    --hub-name "$iot_hub_name" \
    --name "$ca_certificate_name" \
    --path "$ca_cert_path" \
    --output none
fi

function etag {
  local current_certificate_etag

  current_certificate_etag=$(az iot hub certificate show \
    --name "$ca_certificate_name" \
    --hub-name "$iot_hub_name" \
    --query etag \
    --output tsv)
  echo "$current_certificate_etag"
}

echo "Checking if IoT Hub CA certificate is verified..."
if [[ $(az iot hub certificate show --hub-name "$iot_hub_name" --name "$ca_certificate_name" --query properties.isVerified -o tsv) != "true" ]] ; then
  echo "Proving possession of CA certificate private key to IoT Hub..."
  verification_code=$(az iot hub certificate generate-verification-code \
    --name $ca_certificate_name \
    --resource-group "$resource_group_name" \
    --hub-name "$iot_hub_name" \
    --etag "$(etag)" \
    --query properties.verificationCode \
    --output tsv)

  openssl genrsa -out "$proof_key_path" 2048
  openssl req -new -key "$proof_key_path" -subj "/CN=$verification_code" -out "$proof_csr_path"
  openssl x509 -req -in "$proof_csr_path" -CA "$ca_cert_path" -CAkey "$ca_key_path" -sha256 -CAcreateserial -out "$proof_cert_path"

  az iot hub certificate verify \
    --resource-group "$resource_group_name" \
    --hub-name "$iot_hub_name" \
    --name "$ca_certificate_name" \
    --path "$proof_cert_path" \
    --etag "$(etag)" \
    --output none
fi

echo "Checking local directory for device certificate..."
if [[ ! -f "$device_key_path" && ! -f "$device_cert_path" ]] ; then
  echo "Device certificate does not exist in local directory, creating it..."
  openssl genrsa -out "$device_key_path" 2048
  openssl req -new -key "$device_key_path" -subj "/CN=$device_identity_name" -out "$device_csr_path"
  openssl x509 -req -in "$device_csr_path" -CA "$ca_cert_path" -CAkey "$ca_key_path" -CAcreateserial -out "$device_cert_path" -days 3650 -sha256
fi

echo "Checking if device identity exists in IoT Hub..."
if [[ $(az iot hub device-identity list --hub-name "$iot_hub_name" --query "[?deviceId=='$device_identity_name'] | length(@)") -ne 1 ]] ; then
  echo "Device identity '$device_identity_name' does not exist in IoT Hub, creating it..."
  az iot hub device-identity create \
    --resource-group "$resource_group_name" \
    --hub-name "$iot_hub_name" \
    --device-id "$device_identity_name" \
    --auth-method x509_ca \
    --output none
fi

echo
echo "Done!"
echo
echo "The following settings will be used when configuring the camera"
echo
echo "MQTT Client Configuration"
echo "Host:       $iot_hub_name.azure-devices.net"
echo "Username:   $iot_hub_name.azure-devices.net/$device_identity_name/?api-version=2018-06-30"
echo "Client id:  $device_identity_name"
echo
echo "MQTT Event Configuration"
echo "Custom condition prefix:  devices/$device_identity_name/messages/events/"
echo
