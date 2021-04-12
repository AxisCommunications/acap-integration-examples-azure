_Copyright (C) 2021, Axis Communications AB, Lund, Sweden. All Rights Reserved._

# Telemetry to Azure

## Table of contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [File structure](#file-structure)
- [Instructions](#instructions)
- [Cleanup](#cleanup)
- [License](#license)

## Overview

In this example we create an application where we send telemetry data from our camera up to an IoT Hub in Azure. Telemetry data from the camera could be motion detection events or custom events from ACAP applications installed on the camera.

![architecture](./assets/architecture.png)

The application consists of the following Azure resources:

- A resource group
- An IoT Hub

An Axis camera has an internal MQTT client that will connect to the IoT Hub in Azure. The camera authenticates to the IoT Hub using an X.509 certificate.

## Prerequisites

- A network camera from Axis Communications (example has been verified to work on a camera with firmware >=10.4)
- Azure CLI ([install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- OpenSSL ([install](https://www.openssl.org/))
- curl ([install](https://curl.se/))

## File structure

```
telemetry-to-azure-iot-hub
├── configure_camera.sh - Bash script that configures a camera to connect to an Azure IoT Hub
└── create_cloud_resources.sh - Bash script that creates Azure resources and certificates for secure communication between camera and cloud
```



## Instructions

### Deploy Azure resources

Let's start with deploying the Azure resources required to receive telemetry from a camera. We have two alternatives when it comes to deploying the Azure resources. The first alternative is to run a bash script that performs all the necessary commands. The second alternative is to run all the commands manually.

#### Deploy Azure resources using a bash script

The bash script `create-cloud-resources.sh` should be called with the following positional arguments.

1. `resource group name` - The name of a new or existing resource group in Azure
1. `location` - The name of the Azure location where the resources should be created
1. `iot hub name` - The name of the IoT Hub resource
1. `device identity` - The identity of the device in the IoT Hub

The following output indicate that all resources have been created successfully (for brevity, output from OpenSSL commands are not shown).

```bash
$ ./create-cloud-resources.sh my-resource-group eastus my-iot-hub device01
> Creating the resource group...
> Creating the IoT Hub...
> Creating CA and device certificates...
> Uploading CA certificate to IoT Hub...
> Proving possession of CA certificate private key to IoT Hub...
> Creating device identity in IoT Hub...
>
> Done!
>
> The following settings will be used when configuring the camera
>
> MQTT Client Configuration
> Host:     https://my-iot-hub.azure-devices.net
> Username: my-iot-hub.azure-devices.net/device01/?api-version=2018-06-30
> ClientID: device01
>
> MQTT Event Configuration
> Custom condition prefix: devices/device01/messages/events/"
```

#### Deploy Azure resources manually

To keep all resources in Azure grouped together we want to create a new resource group. To create a new resource group named `MyResourceGroup` in the `eastus` Azure location ([see available Azure locations](https://azure.microsoft.com/en-us/global-infrastructure/geographies/)) run

```bash
resourceGroupName=MyResourceGroup
location=eastus
az group create --name $resourceGroupName --location $location
```

Next we create the IoT Hub named `my-iot-hub`. We select the S1 tier and a capacity of 1 unit, this is enough to test this application.

```bash
iotHubName=my-iot-hub
az iot hub create \
    --name $iotHubName \
    --resource-group $resourceGroupName \
    --location $location \
    --sku S1 \
    --unit 1
```

We want to use certificates to authenticate our camera to the IoT Hub. We will create two certificates and place them in a new directory we call `cert`. The first certificate is the Certificate Authority (CA) certificate, which will be uploaded to the Azure IoT Hub.

```bash
mkdir -p cert
openssl genrsa -out ./cert/ca.key 2048
openssl req -x509 -new -nodes -key ./cert/ca.key -sha256 -days 3650 -subj "/O=example.com/CN=example.com" -out ./cert/ca.pem
```

The next certificate is a device certificate which is derived from the CA certificate, this certificate will be uploaded to the camera. Each device we connect to the IoT Hub requires a unique identity name. In this example we will give our device the identity `device01`.

```bash
deviceIdentityName=device01
openssl genrsa -out ./cert/device.key 2048
openssl req -new -key ./cert/device.key -subj "/CN=$deviceIdentityName" -out ./cert/device.csr
openssl x509 -req -in ./cert/device.csr -CA ./cert/ca.pem -CAkey ./cert/ca.key -CAcreateserial -out ./cert/device.crt -days 3650 -sha256
```

Now we have our certificates and we will upload them to where they need to go. First we upload the CA certificate with the name `ca` to the IoT Hub. We store the certificate ETag, which we will need in a later step.

```bash
caCertificateName=ca
certEtag=$(az iot hub certificate create \
    --resource-group $resourceGroupName \
    --hub-name $iotHubName \
    --name $caCertificateName \
    --path ./cert/ca.pem \
    --query etag \
    --output tsv)
```

The CA certificate is uploaded to the IoT Hub, but we need to prove ownership of the corresponding certificate private key. The first step in this procedure is to generate a verification code.

```bash
verificationCode=$(az iot hub certificate generate-verification-code \
    --name $caCertificateName \
    --resource-group $resourceGroupName \
    --hub-name $iotHubName \
    --etag $certEtag \
    --query properties.verificationCode \
    --output tsv)
```

We can now create a new certificate and specify the verification code as the common-name and finally sign the certificate using the CA certificate private key.

```bash
openssl genrsa -out ./cert/proof.key 2048
openssl req -new -key ./cert/proof.key -subj "/CN=$verificationCode" -out ./cert/proof.csr
openssl x509 -req -in ./cert/proof.csr -CA ./cert/ca.pem -CAkey ./cert/ca.key -sha256 -CAcreateserial -out ./cert/proof.pem
```

To complete the verification process we upload the `proof.pem` certificate to the IoT Hub.

```bash
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
    --etag $certEtag
```

Our CA certificate is now verified and we can create our device identity in the IoT Hub.

```bash
az iot hub device-identity create \
    --resource-group $resourceGroupName \
    --hub-name $iotHubName \
    --device-id $deviceIdentityName \
    --auth-method x509_ca
```

Now we have configured everything we need in Azure. The next step is to configure the camera!

### Configuring the camera

We have two alternatives when it comes to configuring the camera. The first alternative is to use a bash script, suited for a situation when you wish to configure the camera without knowing the intricate details, or for when you wish to configure a fleet of cameras. The second alternative is to manually configure the camera using its user interface, for when you wish to understand more about the different capabilities of the camera. Both alternatives are described in upcoming chapters.

#### Configure the camera using a bash script

The bash script `configure-camera.sh` depends on _curl_ being installed on your system, and should be called with the following positional arguments.

1. `url` - The URL of the Axis camera, e.g. `http://192.168.0.90:80`
1. `username` - The username used when accessing the Axis camera
1. `password` - The password used when accessing the Axis camera
1. `iot hub name` - The name of the IoT Hub resource to connect to
1. `device identity` - The device identity of the device in the IoT Hub

The following output indicate a successful configuration, where the camera will start to send telemetry to Azure.

```bash
$ ./configure-camera.sh http://192.168.0.90:80 root my-password my-iot-hub-name my-device-identity
> Adding certificate to device...
> Configuring MQTT client...
> Configuring MQTT event settings...
> Activating MQTT client...
>
> Done!
```

#### Configure the camera using the user interface

We will begin by uploading our device certificate to the camera. Begin by navigate to the camera using your preferred web browser. To add a device certificate, follow the steps below.

1. In the user interface of the camera, select _Settings_ -> _System_ -> _Security_
1. Under the list of _Client certificates_, click on "+" to add a new certificate
1. Select _Upload certificate_ and click on OK
1. Select _Separate private key_
1. For the certificate, click on _Select file_ and browse to `cert/` and select `device.crt`
1. For the private key, click on _Select file_ and browse to `cert/` and select `device.key`
1. Click on _Install_

The next step is to configure the MQTT client on the camera.

1. In the user interface of the camera, select _Settings_ -> _System_ -> _MQTT_
1. In the _Server_ section use the following settings
   - Protocol: `MQTT over WebSocket Secure`
   - Host: `<iot-hub-name>.azure-devices.net`
   - Port: `443`
   - Basepath: `$iothub/websocket`
   - Username `<iot-hub-name>.azure-devices.net/<device identity>/?api-version=2018-06-30`
1. Under the _Certificate_ section use the following settings
   - Client certificate: `device`
   - CA certificate: `Baltimore CyberTrust Root`
1. Under the _Policies_ section use the following sections
   - Client id: `<device identity>`
1. Click _Save_

Once the settings are saved, click on _Connect_ on the top of the MQTT settings page.

Finally we will configure what types of telemetry events we want to send to the IoT Hub.

1. In the user interface of the camera, select _Settings_ -> _System_ -> _Events_ -> _MQTT events_
1. Make sure _Use default condition prefix_ is turned off
1. In _Custom condition prefix_ specify `devices/<device identity>/messages/events`
1. Under _Event filter list_ click on "+"
1. Select a condition of interest, for instance `Above operating temperature`
1. Click on _Save_

## Cleanup

### Delete Azure resources

To delete all deployed resources in Azure, run the following CLI command

```bash
az group delete --name $resourceGroupName
```

## License

[Apache 2.0](./LICENSE)
