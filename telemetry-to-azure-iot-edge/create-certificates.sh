#!/bin/bash
set -e

if [[ $# -ne 3 ]] ; then
  echo "Error: Unsupported number of arguments"
  echo
  echo "USAGE:"
  echo "    create-certificates.sh <organization name> <edge gateway hostname> <device identity>"
  echo
  echo "WHERE:"
  echo "    organization name       The name of your organization"
  echo "    edge gateway hostname   The hostname of the Azure IoT Edge gateway, i.e. a name on the"
  echo "                            network that resolves into a IPv4 address that points to the"
  echo "                            computer where we will install Azure IoT Edge, e.g."
  echo "                            'azureiotedgedevice'"
  echo "    device identity         The device identity of the camera in Azure IoT Hub, e.g."
  echo "                            'device01'"
  echo

  exit 1
fi

organization_name=$1
edge_gateway_hostname=$2
device_identity=$3

# ------------------------------------------------------------------------------
# CREATE CERTIFICATES
# ------------------------------------------------------------------------------

# The number of days the X.509 certificates are valid for
valid_for_days=365

ca_key_path=./cert/ca.key
ca_cert_path=./cert/ca.pem
edge_device_key_path=./cert/$edge_gateway_hostname.key
edge_device_csr_path=./cert/$edge_gateway_hostname.csr
edge_device_cert_path=./cert/$edge_gateway_hostname.pem
edge_device_ca_key_path=./cert/${edge_gateway_hostname}_ca.key
edge_device_ca_csr_path=./cert/${edge_gateway_hostname}_ca.csr
edge_device_ca_cert_path=./cert/${edge_gateway_hostname}_ca.pem
device_key_path=./cert/$device_identity.key
device_csr_path=./cert/$device_identity.csr
device_cert_path=./cert/$device_identity.pem

mkdir -p cert

# We want to use X.509 certificates to authenticate our camera to Azure IoT
# Edge. We also want Azure IoT Edge to authenticate to the Azure IoT Hub using
# X.509 certificates.
# We will create all required certificates and place them in a new directory
# called 'cert'. The first certificate we create is the root Certificate
# Authority (CA) certificate which later on in the example will be uploaded to
# the Azure IoT Hub.
echo "Checking local directory for root CA certificate..."
if [[ ! -f "$ca_key_path" || ! -f "$ca_cert_path" ]] ; then
  echo "Root CA certificate does not exist in local directory, creating it..."
  openssl genrsa -out $ca_key_path 4096
  openssl req -x509 -new -nodes -key $ca_key_path -sha256 -days $valid_for_days \
    -subj "/O=$organization_name/CN=$organization_name" -config openssl.cnf -extensions "v3_ca" \
    -out $ca_cert_path
fi

# The second certificate is derived from the root CA certificate. It's for Azure
# IoT Edge, a.k.a. the transparent gateway, and will be used when Azure IoT Edge
# connects and authenticates itself to the Azure IoT Hub.
echo "Checking local directory for edge gateway certificate..."
if [[ ! -f "$edge_device_key_path" || ! -f "$edge_device_cert_path" ]] ; then
  echo "Edge gateway certificate does not exist in local directory, creating it..."
  openssl genrsa -out "$edge_device_key_path" 2048
  openssl req -new -key "$edge_device_key_path" -subj "/CN=$edge_gateway_hostname" \
    -config openssl.cnf -extensions "usr_cert" -out "$edge_device_csr_path"
  openssl x509 -req -in "$edge_device_csr_path" -CA "$ca_cert_path" -CAkey "$ca_key_path" -sha256 \
    -days $valid_for_days -CAcreateserial -extfile openssl.cnf -extensions "usr_cert" \
    -out "$edge_device_cert_path"
  rm "$edge_device_csr_path"
fi

# The third certificate is a new intermediate CA certificate, derived from the
# root CA certificate. This intermediate CA certificate will be loaded onto the
# IoT Edge device, a.k.a. transparent gateway, and act as a intermediate
# certificate for connected Azure IoT devices.
echo "Checking local directory for edge gateway CA certificate..."
if [[ ! -f "$edge_device_ca_key_path" || ! -f "$edge_device_ca_cert_path" ]] ; then
  echo "Azure edge gateway CA certificate does not exist in local directory, creating it..."
  openssl genrsa -out "$edge_device_ca_key_path" 4096
  openssl req -new -key "$edge_device_ca_key_path" -subj "/CN=$edge_gateway_hostname.ca" \
    -config openssl.cnf -extensions "v3_intermediate_ca" -out "$edge_device_ca_csr_path"
  openssl x509 -req -in "$edge_device_ca_csr_path" -CA "$ca_cert_path" -CAkey "$ca_key_path" \
    -sha256 -days $valid_for_days -CAcreateserial -extfile openssl.cnf \
    -extensions "v3_intermediate_ca" -out "$edge_device_ca_cert_path"
  cat "$ca_cert_path" >> "$edge_device_ca_cert_path"
  rm "$edge_device_ca_csr_path"
fi

# The fourth certificate is derived from the root CA certificate. It's for the
# Axis camera acting as a Azure IoT device in the Azure IoT Hub. This
# certificate will be used by the Axis camera when authenticating itself to
# Azure IoT Edge.
echo "Checking local directory for device certificate..."
if [[ ! -f "$device_key_path" || ! -f "$device_cert_path" ]] ; then
  echo "Device certificate does not exist in local directory, creating it..."
  openssl genrsa -out "$device_key_path" 2048
  openssl req -new -key "$device_key_path" -subj "/CN=$device_identity" -config openssl.cnf \
    -extensions "usr_cert" -out "$device_csr_path"
  openssl x509 -req -in "$device_csr_path" -CA "$ca_cert_path" -CAkey "$ca_key_path" -sha256 \
    -days $valid_for_days -CAcreateserial -extfile openssl.cnf -extensions "usr_cert" \
    -out "$device_cert_path"
  rm "$device_csr_path"
fi

# ------------------------------------------------------------------------------
# OUTPUT
# ------------------------------------------------------------------------------

echo
echo "Done!"
echo
echo "The following certificates have been created."
echo
echo "Root Certificate Authority (CA) certificate"
echo "--------------------------------------------------------------------------"
echo "All other certificates we generated are rooted in this certificate, and"
echo "later on in the example we will upload this certificate to the Azure IoT"
echo "Hub and to the Azure IoT Edge gateway."
echo
echo "Files:"
echo "    $ca_cert_path"
echo "    $ca_key_path"
echo
echo
echo "Edge gateway certificate"
echo "--------------------------------------------------------------------------"
echo "The device certificate used when Azure IoT Edge connects to, and"
echo "authenticates with, the Azure IoT Hub. This certificate will be installed"
echo "on the Azure IoT Edge gateway."
echo
echo "Files:"
echo "    $edge_device_cert_path"
echo "    $edge_device_key_path"
echo
echo
echo "Azure IoT Edge intermediate Certificate Authority (CA) certificate"
echo "--------------------------------------------------------------------------"
echo "The intermediate CA certificate used when Azure IoT Edge accepts"
echo "connections from downstream devices, i.e. the Axis camera. This"
echo "certificate will be installed on the Azure IoT Edge gateway."
echo
echo "Files:"
echo "    $edge_device_ca_cert_path"
echo "    $edge_device_ca_key_path"
echo
echo
echo "Azure IoT device certificate"
echo "--------------------------------------------------------------------------"
echo "The device certificate used when the Axis camera connects to, and"
echo "authenticates with, Azure IoT Edge. This certificate will be installed on"
echo "the Axis camera."
echo
echo "Files:"
echo "    $device_cert_path"
echo "    $device_key_path"
echo
