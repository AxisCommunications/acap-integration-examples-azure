_Copyright (C) 2021, Axis Communications AB, Lund, Sweden. All Rights Reserved._

# Images to Azure storage

## Table of contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [File structure](#file-structure)
- [Instructions](#instructions)
- [Cleanup](#cleanup)
- [License](#license)

## Overview

In this example we create an application that sends images from an Axis camera to an Azure storage account.

![architecture](./assets/architecture.png)

This application consists of the following Azure resources.

- An API Management instance
- A managed identity
- A storage account with a blob container

The camera will send images to the blob container via an API Management endpoint. The API Management resource receives a POST request containing the image from the camera. This request is transformed to a PUT request as this is required by the Azure storage REST API. The API Management uses a managed identity to authenticate to Azure storage. The API Management endpoint is secured by a subscription key which is provided to the camera.

## Prerequisites

- A network camera from Axis Communications (example has been verified to work on a camera with firmware version >=9.80.3.1)
- Azure CLI ([install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- curl ([install](https://curl.se/))

## File structure

```
images-to-azure-storage-account
├── azuredeploy.json - Azure Resource Manager (ARM) template describing the Azure resources
├── configure-camera.sh - bash script capable of configuring an Axis camera to send images
└── create-cloud-resources.sh - Deployment script for bash and Azure CLI
```

## Instructions

The instructions are divided into two parts. The first part covers deploying the Azure resources and the second part covers configuring the camera.

To start off, make sure to clone the repository and navigate into the example directory.

```bash
$ git clone https://github.com/AxisCommunications/acap3-examples-azure.git
$ cd acap3-examples-azure/images-to-azure-storage-account
```

### Deploy Azure resources

Let's start with deploying the Azure resources receiving the images sent from a camera. The services are described in `azuredeploy.json` using a [Azure Resource Manager (ARM) template](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/overview).

The Azure resources will be deployed by using an Azure Resource Manager (ARM) template. We have two alternatives when it comes to deploying this ARM template. The first alternative is to run a bash script that performs all the necessary commands. The second alternative is to run all the commands manually.

#### Deploy Azure resources using a bash script

The bash script `create-cloud-resources.sh` should be called with the following positional arguments.

1. `resource group name` - The name of a new or existing resource group in Azure
1. `location` - The name of the Azure location where the resources should be created ([see available Azure locations](https://azure.microsoft.com/en-us/global-infrastructure/geographies/))
1. `email address` - A valid e-mail address where API Management system notifications will be sent

The following output indicates that the resources have been created successfully.

```bash
$ ./create-cloud-resources.sh MyResourceGroup eastus example@example.com
> Creating resource group...
> Deploying ARM template...
>
> Done!
>
> Use the following endpoint when setting up your Axis device to send images to Azure
> https://image-upload-abcdefghijklm.azure-api.net?accessToken=abcdef1234567890abcdef1234567890
```

#### Deploy Azure resources manually

To keep all resources in Azure grouped together we want to create a new resource group. To create a new resource group named `MyResourceGroup` in the `eastus` Azure location ([see available Azure locations](https://azure.microsoft.com/en-us/global-infrastructure/geographies/)) run the following commands in your shell.

```bash
$ resourceGroupName=MyResourceGroup
$ location=eastus
$ az group create --name $resourceGroupName --location $location
```

Next we want to deploy the ARM template to our resource group. We can do that with the following commands.

```bash
$ deploymentName=deployment-$(date '+%Y-%m-%dT%H-%M')
$ publisherEmail=<e-mail address>
$ az deployment group create \
    --name $deploymentName \
    --template-file azuredeploy.json \
    --parameters publisherEmail=$publisherEmail \
    --resource-group $resourceGroupName
```

We create a unique `deploymentName` with today's date and time. This will simplify telling deployments apart in case we run several deployments to the same resource group. Replace `<e-mail address>` with a valid e-mail address. The e-mail address you provide will receive all system notifications sent from the API-management resource that is created. The next step is to fetch the endpoint URL to our new API Management resource, this is the URL where the camera will send images. Run the following command to fetch the endpoint.

```bash
$ endpoint=$(az deployment group show \
    --name $deploymentName \
    --resource-group $resourceGroupName \
    --query properties.outputs.endpointUrl.value \
    -o tsv)
```

The final step is to retrieve the subscription key from API Management. We will use the REST functionality in the Azure CLI to do this. First we need the API Management resource ID, which we will fetch from the outputs from our deployment.

```bash
$ apiManagementResourceId=$(az deployment group show \
    --name $deploymentName \
    --resource-group $resourceGroupName \
    --query properties.outputs.apiManagementResourceId.value \
    -o tsv)
```

Then we use the API Management resource ID to fetch the subscription key and store it in a variable called `accessToken`.

```bash
$ accessToken=$(az rest \
    --method post \
    --url $apiManagementResourceId/subscriptions/AxisDeviceSubscription/listSecrets?api-version=2021-01-01-preview \
    --query primaryKey \
    -o tsv)
```

Now we have everything we need and we can view our endpoint and access token with the following command.

```bash
$ echo "$endpoint?accessToken=$accessToken"
```

We will use this string in the next part where we will [configure the camera](#configure-the-camera)!

### Configure the camera

Now that the resources in Azure are ready to accept images, let's continue with configuring the camera to send them.

We have two alternatives when it comes to configuring the camera. The first alternative is to use a bash script, suited for a situation when you wish to configure the camera without knowing the intricate details, or for when you wish to configure a fleet of cameras. The second alternative is to manually configure the camera using its user interface, for when you wish to understand more about the different capabilities of the camera. Both alternatives are described in upcoming chapters.

#### Configure the camera using a bash script

The bash script `configure-camera.sh` depends on _curl_ being installed on your system, and should be called with the following positional arguments.

1. `url` - The URL of the Axis camera, e.g. `http://192.168.0.90:80`
1. `username` - The username used when accessing the Axis camera
1. `password` - The password used when accessing the Axis camera
1. `recipient` - The URL of the AWS API Gateway, defined as a CloudFormation output parameter
1. `access token` - The access token authorizing requests, linked from a CloudFormation output parameter

The following output indicate a successful configuration, where the camera will start to send a new image to your AWS S3 bucket every minute.

```bash
$ ./configure-camera.sh http://192.168.0.90:80 root my-password https://my-recipient.com my-access-token
> Adding recipient...
> Adding schedule...
> Adding rule...
>
> Done!
```

#### Configure the camera using the user interface

Navigate to the camera using your preferred web browser. In the user interface of the camera, select _Settings_ -> _System_ -> _Events_ -> _Device events_. In this user interface we'll do all configuration, but first let's get an overview of the available tabs.

- **Rules** - Here we'll create a rule that sends images to our Azure storage account
- **Schedules** - In this sample we'll use a schedule to define _when_ a snapshot should be sent. If a schedule doesn't fit your specific use case, you can replace it with any event generated on the camera or even events generated by ACAPs installed on the camera.
- **Recipients** - Here we'll define _where_ images are sent

Let's start with _Recipients_. Select the tab and create a new recipient with the following settings.

- **Name**: `Azure storage`
- **Type**: `HTTPS`
- **URL**: Specify the endpoint and access token you obtained in the first part of this tutorial, format this string as `<endpoint>?accessToken=<accessToken>`. For example: `https://image-upload-abcdefghijklm.azure-api.net?accessToken=abcdef1234567890abcdef1234567890`.

Click the _Save_ button.

Now let's navigate to the _Schedules_ tab. In this sample we'll use a schedule to define when a snapshot should be send. Create a new schedule with the following settings.

- **Type**: `Pulse`
- **Name**: `Every minute`
- **Repeat every**: `1 Minute`

Click the _Save_ button.

Now let's navigate to the _Rules_ tab. Here we'll finally create a rule that combines the recipient and the schedule into a rule. Create a new rule with the following settings.

- **Name**: `Images to Azure storage`
- **Condition**: `Pulse`
  - **Pulse**: `Every Minute`
- **Action**: `Send images through HTTPS`
  - **Recipient**: `Azure storage`
  - **Maximum images**: `1`

Click the _Save_ button.

At this point the rule will become active and send a snapshot to Azure storage every minute.

## Cleanup

To delete the deployed Azure services, including all images in the storage account, either use the Azure portal to delete the resource group, or run the following CLI command.

```bash
$ az group delete --name $resourceGroupName
```

## License

[Apache 2.0](./LICENSE)
