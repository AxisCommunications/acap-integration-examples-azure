#!/bin/bash
set -e

if [[ $# -ne 3 ]] ; then
  echo "Error: Unsupported number of arguments"
  echo
  echo "USAGE:"
  echo "    create-cloud-resources.sh <resource group name> <location> <email address>"
  echo
  echo "WHERE:"
  echo "    resource group name   The name of a new or existing resource group in Azure"
  echo "    location              The name of the Azure location where the resources"
  echo "                          should be created, e.g. eastus for East US"
  echo "    email address         A valid e-mail address where API Management system"
  echo "                          notifications will be sent"
  echo

  exit 1
fi

resource_group_name=$1
location=$2
publisher_email=$3

echo "Creating resource group..."
az group create \
  --name $resource_group_name \
  --location $location \
  --output none

echo "Deploying ARM template..."
deployment_name=deployment-$(date '+%Y-%m-%dT%H-%M')
az deployment group create \
  --name $deployment_name \
  --template-file azuredeploy.json \
  --parameters publisherEmail=$publisher_email \
  --resource-group $resource_group_name \
  --output none

endpoint=$(az deployment group show \
  --name $deployment_name \
  --resource-group $resource_group_name \
  --query properties.outputs.endpointUrl.value \
  -o tsv)

api_management_resource_id=$(az deployment group show \
  --name $deployment_name \
  --resource-group $resource_group_name \
  --query properties.outputs.apiManagementResourceId.value \
  -o tsv)

access_token=$(az rest \
  --method post \
  --url $api_management_resource_id/subscriptions/AxisDeviceSubscription/listSecrets?api-version=2021-01-01-preview \
  --query primaryKey \
  -o tsv)

echo
echo "Done!"
echo
echo "Use the following parameters when setting up your Axis camera to send images to Azure."
echo
echo "Endpoint:      $endpoint"
echo "Access token:  $access_token"
echo
