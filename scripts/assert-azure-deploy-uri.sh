#!/bin/bash
set -e

if [[ $# -ne 2 ]] ; then
  echo "Error: Unsupported number of arguments"
  echo
  echo "USAGE:"
  echo "    assert-azure-deploy-uri.sh <example name> <file path>"
  echo
  echo "WHERE:"
  echo "    example name    The name of the example."
  echo "    file path       The path of the file to assert."
  echo

  exit 1
fi

example_name=$1
file_path=$2

file_content=$(cat $file_path)
regex='https://portal.azure.com/#create/Microsoft.Template/uri/([^)]*)'

if ! [[ $file_content =~ $regex ]]; then
  echo "The expected Azure Deploy button was not found in '$file_path'."
  exit 1
fi

actual_uri="${BASH_REMATCH[1]}"
expected_uri="https%3A%2F%2Fraw.githubusercontent.com%2FAxisCommunications%2Facap-integration-examples-azure%2Fmain%2F$example_name%2Fmain.json"

if [[ $actual_uri != $expected_uri ]]; then
   echo "The expected ARM template URI was not found in '$file_path'."
   exit 1
fi

echo "Success!"
