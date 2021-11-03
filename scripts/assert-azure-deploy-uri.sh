#!/bin/bash
set -e

if [[ $# -ne 2 ]] ; then
  echo "Error: Unsupported number of arguments"
  echo
  echo "USAGE:"
  echo "    assert-azure-deploy-uri.sh <file path> <expected uri>"
  echo
  echo "WHERE:"
  echo "    file path       The path of the file to assert."
  echo "    expected uri    The expected URI of the ARM template."
  echo

  exit 1
fi

file_path=$1
expected_uri=$2

file_content=$(cat $file_path)
regex='https://portal.azure.com/#create/Microsoft.Template/uri/([^)]*)'

if ! [[ $file_content =~ $regex ]]; then
  echo "The expected Azure Deploy button was not found in '$file_path'."
  exit 1
fi

actual_uri="${BASH_REMATCH[1]}"

if [[ $actual_uri != $expected_uri ]]; then
   echo "The expected ARM template URI was not found in '$file_path'."
   exit 1
fi

echo "Success!"
