#!/bin/bash
set -e

if [[ $# -ne 4 ]] ; then
  echo "Please provide exactly four arguments."
  echo '  ./deploy.sh <resource group name> <location> <IoT Hub name> <device identity name>'
  exit 1
fi

resourceGroupName=$1
location=$2
iotHubName=$3
deviceIdentityName=$4
caCertificateName=ca

echo "Creating the resource group..."
az group create \
  --name $resourceGroupName \
  --location $location \
  --output none

echo "Creating the IoT Hub..."
az iot hub create \
  --name $iotHubName \
  --resource-group $resourceGroupName \
  --location $location \
  --sku S1 \
  --unit 1 \
  --output none

echo "Creating CA and device certificates..."
mkdir -p cert
openssl genrsa -out ./cert/ca.key 2048
openssl req -x509 -new -nodes -key ./cert/ca.key -sha256 -days 3650 -subj "/O=example.com/CN=example.com" -out ./cert/ca.pem
openssl genrsa -out ./cert/device.key 2048
openssl req -new -key ./cert/device.key -subj "/CN=$deviceIdentityName" -out ./cert/device.csr
openssl x509 -req -in ./cert/device.csr -CA ./cert/ca.pem -CAkey ./cert/ca.key -CAcreateserial -out ./cert/device.crt -days 3650 -sha256

echo "Uploading CA certificate to IoT Hub..."
certEtag=$(az iot hub certificate create \
  --resource-group $resourceGroupName \
  --hub-name $iotHubName \
  --name $caCertificateName \
  --path ./cert/ca.pem \
  --query etag \
  --output tsv)

echo "Proving possession of CA certificate private key to IoT Hub..."
verificationCode=$(az iot hub certificate generate-verification-code \
  --name $caCertificateName \
  --resource-group $resourceGroupName \
  --hub-name $iotHubName \
  --etag $certEtag \
  --query properties.verificationCode \
  --output tsv)

openssl genrsa -out ./cert/proof.key 2048
openssl req -new -key ./cert/proof.key -subj "/CN=$verificationCode" -out ./cert/proof.csr
openssl x509 -req -in ./cert/proof.csr -CA ./cert/ca.pem -CAkey ./cert/ca.key -sha256 -CAcreateserial -out ./cert/proof.pem

certEtag=$(az iot hub certificate show \
  --name $caCertificateName \
  --resource-group $resourceGroupName \
  --hub-name $iotHubName \
  --query etag \
  --output tsv)

az iot hub certificate verify \
  --resource-group $resourceGroupName \
  --hub-name $iotHubName \
  --name $caCertificateName \
  --path ./cert/proof.pem \
  --etag $certEtag \
  --output none

echo "Creating device identity in IoT Hub..."
az iot hub device-identity create \
  --resource-group $resourceGroupName \
  --hub-name $iotHubName \
  --device-id $deviceIdentityName \
  --auth-method x509_ca \
  --output none

echo
echo "Done!"
echo
echo "The following settings will be used when configuring the camera"
echo
echo "MQTT Client Configuration"
echo "Host:     https://$iotHubName.azure-devices.net"
echo "Username: $iotHubName.azure-devices.net/$deviceIdentityName/?api-version=2018-06-30"
echo "ClientID: $deviceIdentityName"
echo
echo "MQTT Event Configuration"
echo "Custom condition prefix: devices/$deviceIdentityName/messages/events/"
