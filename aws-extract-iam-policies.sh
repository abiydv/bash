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
  checkInput $1
  getPolicyDocument
  lastStep
}

function checkLastStep(){
  if [ $? -ne 0 ]; then
    echo "  Error!. Exiting."
    lastStep
    exit 1
  else
    echo "  Success!"
  fi
}

function checkInput(){
  if [ ! -z $1 ]; then
    echo "$1" > ./policy.list
    echo "Policy specified $1"
  else
    echo "No policy specified, extracting all policies"
    getPolicyList
  fi
}

function getPolicyList(){
  echo -n "Extracting ALL IAM managed policies"
  aws iam list-policies --scope Local --query Policies[].PolicyName | jq -r .[] > ./policy.list
  checkLastStep
  echo " $(wc -l < ./policy.list) policies in the account"
  echo ""
}

function getPolicyDocument(){
  while read policy
  do
    echo -n "$policy : Extracting role and version info"
    role=`aws iam list-entities-for-policy --policy-arn arn:aws:iam::${aws_account}:policy/${policy} \
    --query PolicyRoles[].RoleName --output text`
    
    version=$(aws iam get-policy --policy-arn arn:aws:iam::${aws_account}:policy/${policy} \
    --query Policy.DefaultVersionId --output text)
    
    checkLastStep
    if [ ! -z $role ];then
      jsonName=$role
      else
      jsonName=$policy
    fi
    echo -n "$policy : Extracting policy document"
    aws iam get-policy-version --policy-arn arn:aws:iam::${aws_account}:policy/${policy} \
    --version-id $version --query PolicyVersion.Document | jq . 2>&1> ${save_to}${jsonName}.json
    checkLastStep
    echo "$policy : Saved to ${save_to}${jsonName}.json"
  done < ./policy.list
}

function lastStep(){
  echo ""
  echo "Execution ended | Bye!"
}

export PATH=${PATH}:../libs/
init $1
