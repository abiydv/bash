#!/bin/bash
#=========================================================================================
# Title          : aws-useradd.sh
# Description    : This script will add a new user to the aws account
#                  based on a reference user and it updates the user inventory file on s3.
#                  It will send email to the new user with instructions. If no reference 
#                  user is specified, new user will be added to a default group (user-basic).
# Author         : https://github.com/abiydv
# Date           : 20181228
# Version        : 1
# Usage          : ./aws-useradd.sh newuser,newuser@example.com,ref_user
# Depends        : Depends on the jq library
# Config files   : configs/aws-useradd.properties
#===========================================================================================

function init(){
  source ./configs/aws-useradd.properties
  addUser "$1"
}

function addUser(){
  local new_password
  new_password=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
  local ref_username
  ref_username=$(echo "$1" | cut -f3 -d ',')
  local new_username
  new_username=$(echo "$1" | cut -f1 -d ',')
  local new_useremail
  new_useremail=$(echo "$1" | cut -f2 -d ',')

  if [ -z "$new_useremail" ];then
    echo "ERROR: You've not entered user's email-id. Please try again!"
    exit 1
  fi

  check aws iam create-user --user-name "$new_username" > user-create

  created_time=$(jq -r .User.CreateDate user-create | cut -d "T" -f1)

  if [ -n "$ref_username" ];then
    check aws iam list-groups-for-user --user-name "$ref_username" | jq -r .Groups[].GroupName > ref_user_groups
    
    check aws iam list-attached-user-policies --user-name "$ref_username" \
    | jq -r .AttachedPolicies[].PolicyArn > ref_user_direct_policies
  
    while read -r group
      do
        check aws iam add-user-to-group --user-name "$new_username" --group-name "$group"
      done < ref_user_groups
      while read -r policy
        do
          check aws iam attach-user-policy --user-name "$new_username" --policy-arn "$policy"
        done < ref_user_direct_policies
  else
    echo "No reference user mentioned, adding $new_username to user-basic group only"
    check aws iam add-user-to-group --user-name "$new_username" --group-name user-basic
  fi

  check aws iam create-login-profile --user-name "$new_username" --password "$new_password" --password-reset-required

  updateInventory "$new_username" "$created_time" "$new_useremail"

  setEmailContent "$mail_from" "$new_useremail" "$mail_cc" "$new_username" "emailInstructions"
  setEmailContent "$mail_from" "$new_useremail" "$new_username" "$new_password" "emailPassphrase"
}

function updateInventory(){
  local new_username="$1"
  local created_time="$2"
  local new_useremail="$3"

  check aws s3 cp s3://"$s3_path"/"$inventory_file" .

  serial_no=$(tail -1 "$inventory_file" | cut -f1 -d",")
  new_serial_no=$(( serial_no + 1 ))
  echo "$new_serial_no,$new_username,$created_time,$new_useremail" >> "$inventory_file"

  check aws s3 cp "$inventory_file" s3://"$s3_path"/"$inventory_file" --sse
}

function setEmailContent(){
  local mail_from=$1
  local mail_to=$2
  echo "From:$1" > email_content
  echo "To:$2" >> email_content
  if [ "$5" == "emailInstructions" ];then
    local mail_cc="$3"
    {
      echo "Cc:$3"
      echo "Subject: Welcome to Amazon Web Services (1/2)"
      echo ""
      echo ""
      echo -e "Hello $4,\n\n"
      echo -e "You have been given access to the Amazon Web Services account. \
          You can get started by using the sign-in information provided below.\n\n"
      echo -e "Sign-in URL: ${sign_in_url} \n\n"
      echo -e "Your initial sign-in password will be provided separately from this email. \
          When you sign in for the first time, you must change your password.\n\n"
      echo "To use the AWS services, please complete these next steps - "
      echo " 1. Change console password on first login"
      echo " 2. Setup Multifactor Authentication on your account"
      echo " 3. Setup AWS CLI"
      echo ""
      echo -e "Instructions at this location : ${instructions_url}"
      echo ""
    } >> email_content
  elif [ "$5" == "emailPassphrase" ];then
    local mail_cc=""
    {
      echo "Subject: Welcome to Amazon Web Services (2/2)"
      echo ""
      echo ""
      echo "Password: $4"
      echo ""
      echo ""
    } >> email_content
  fi
  {
    echo "Please write back if you have any questions - $mail_cc"
    echo ""
    echo ""
  } >> email_content
  check sendmail -f "$mail_from" "$mail_to" "$mail_cc" < email_content
}

function check (){
  if ! "$@"; then
    echo "FAILED - $*"
    exit 1
  else
    echo "SUCCESS - $*"
  fi
}

export PATH=$PATH:../lib/
init "$1"