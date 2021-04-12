#!/bin/bash
set -e

if [[ $# -ne 3 ]] ; then
  echo "Please provide exactly three arguments."
  echo '  ./deploy.sh <resource group name> <location> <email address>'
  exit 1
fi

resourceGroupName=$1
location=$2
publisherEmail=$3

echo "Creating resource group..."
az group create --name $resourceGroupName --location $location

echo "Deploying ARM template..."
deploymentName=deployment-$(date '+%Y-%m-%dT%H-%M')
az deployment group create \
  --name $deploymentName \
  --template-file azuredeploy.json \
  --parameters publisherEmail=$publisherEmail \
  --resource-group $resourceGroupName

endpoint=$(az deployment group show \
  --name $deploymentName \
  --resource-group $resourceGroupName \
  --query properties.outputs.endpointUrl.value \
  -o tsv)

apiManagementResourceId=$(az deployment group show \
  --name $deploymentName \
  --resource-group $resourceGroupName \
  --query properties.outputs.apiManagementResourceId.value \
  -o tsv)

accessToken=$(az rest \
  --method post \
  --url $apiManagementResourceId/subscriptions/AxisDeviceSubscription/listSecrets?api-version=2021-01-01-preview \
  --query primaryKey \
  -o tsv)

echo
echo "Done!"
echo
echo "Use the following endpoint when setting up your Axis device to send images to Azure"
echo "$endpoint?accessToken=$accessToken"
echo
