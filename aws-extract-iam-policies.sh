#!/bin/bash
#================================================================================
# Title          : aws-extract-iam-policies.sh
# Description    : Use this script to extract IAM policies in AWS account
#                  -  If no argument is given, script will extract ALL policies
#                  -  If the policy is not attached to any role, 
#                     it will be saved as policy-name.json
#                  -  If the policy is attachde to any role, 
#                     it will be saved as role-name.json
#                  -  Output location can be specified as save_to
#
# Author         : https://github.com/abiydv
# Date           : 20180828
# Version        : 1
# Usage          : ./aws-extract-iam-policies.sh [policy-name]
# Depends        : Depends on the library libs/jq 
# Config files   : configs/aws-extract-iam-policies.properties 
#================================================================================

function init(){
  source ./configs/aws-extract-iam-policies.properties
  checkInput "$1"
  getPolicyDocument
  echo "Execution ended | Bye!"
}

function check (){
  if ! "$@"; then
    echo "FAILED - $*"
    exit 1
  else
    echo "SUCCESS - $*"
  fi
}

function checkInput(){
  if [ -n "$1" ]; then
    echo "$1" > ./policy.list
    echo "Policy specified $1"
  else
    echo "No policy specified, extracting all policies"
    getPolicyList
  fi
}

function getPolicyList(){
  echo -n "Extracting ALL IAM managed policies"
  check aws iam list-policies --scope Local --query Policies[].PolicyName | jq -r .[] > ./policy.list
  echo "$(wc -l < ./policy.list) policies in the account"
  echo ""
}

function getPolicyDocument(){
  while read -r policy
  do
    echo -n "$policy : Extracting role and version info"
    role=$(aws iam list-entities-for-policy --policy-arn arn:aws:iam::"$aws_account":policy/"$policy" \
    --query PolicyRoles[].RoleName --output text)
    
    version=$(aws iam get-policy --policy-arn arn:aws:iam::"$aws_account":policy/"$policy" \
    --query Policy.DefaultVersionId --output text)
    
    if [ -n "$role" ];then
      jsonName="$role"
      else
      jsonName="$policy"
    fi
    echo -n "$policy : Extracting policy document"
    check aws iam get-policy-version --policy-arn arn:aws:iam::"${aws_account}":policy/"${policy}" \
    --version-id "$version" --query PolicyVersion.Document | jq . > "${save_to}${jsonName}".json 2>&1
    echo "$policy : Saved to ${save_to}${jsonName}.json"
  done < ./policy.list
}

export PATH=${PATH}:../libs/
init "$1"