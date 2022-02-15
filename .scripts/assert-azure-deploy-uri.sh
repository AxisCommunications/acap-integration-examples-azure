#!/bin/bash
set -e

if [[ $# -ne 1 ]] ; then
  echo "Error: Unsupported number of arguments"
  echo
  echo "USAGE:"
  echo "    assert-azure-deploy-uri.sh <example name> "
  echo
  echo "WHERE:"
  echo "    example name    The name of the example."
  echo

  exit 1
fi

example_name=$1

content=$(cat README.md)
regex='https://portal.azure.com/#create/Microsoft.Template/uri/([^)]*)'

if ! [[ $content =~ $regex ]]; then
  echo "The expected Azure Deploy button was not found."
  exit 1
fi

actual_uri="${BASH_REMATCH[1]}"
expected_uri="https%3A%2F%2Fraw.githubusercontent.com%2FAxisCommunications%2Facap-integration-examples-azure%2Fmain%2F$example_name%2Fmain.json"

if [[ $actual_uri != "$expected_uri" ]]; then
   echo "The expected ARM template URI was not found."
   exit 1
fi

echo "Success!"
