#!/bin/bash
#================================================================================
# Title          : aws-useraudit.sh
# Description    : This script will look for idle users in your aws account
#                  and updates the report on s3 location
#
# Author         : https://github.com/abiydv
# Date           : 20181228
# Version        : 1
# Depends        : Depends on the library libs/jq 
# Config files   : configs/aws-useraudit.properties and
#                  configs/email.properties
#================================================================================

function init(){
  source ./configs/email.properties
  source ./configs/aws-useraudit.properties
  timestamp=$(date +%Y-%m-%d)
  last_month=$(date +%Y-%m-%d -d 'now -3 months')
  getUserReport "$timestamp" "$last_month"
  uploadReport "./idle-users.report"
  cleanFolder
}

function getUserReport(){
  local timestamp="$1"
  local last_month="$2"
        
  check aws iam generate-credential-report &> /dev/null
  sleep 25
  check aws iam get-credential-report --output text --query Content | base64 -d > ./credentials-report-"$timestamp".csv
  true >./idle-users.report
  sed 1d ./credentials-report-"${timestamp}".csv | while read -r user
  do
    local username
    username=$(echo "$user" | cut -f1 -d',')
    local user_age
    user_age=$(echo "$user" | cut -f3 -d',' | cut -c1-10)
    local password_last_used 
    password_last_used=$(echo "$user" | cut -f5 -d',' | cut -c1-10)
    local access_key1_last_used 
    access_key1_last_used=$(echo "$user" | cut -f11 -d',' | cut -c1-10)
    local access_key2_last_used 
    access_key2_last_used=$(echo "$user" | cut -f16 -d',' | cut -c1-10)

      if [[ $password_last_used < $last_month ]] || [[ $password_last_used == "no_information" ]];then
        if [[ $access_key1_last_used == "NA" ]] && [[ $access_key2_last_used == "NA" ]];then
          echo -e "User: $username | Created on: $user_age | Password last used: $password_last_used \
            | No active access keys"
        elif [[ $access_key1_last_used != "NA" ]] && [[ $access_key2_last_used == "NA" ]];then
          if [[ $access_key1_last_used < $last_month ]];then
            echo -e "User: $username | Created on: $user_age | \
                      Password last used: $password_last_used | \
                      Accesskey last used: $access_key1_last_used" >> ./idle-users.report
          fi
        elif [[ $access_key1_last_used == "NA" ]] && [[ $access_key2_last_used != "NA" ]];then
          if [[ $access_key2_last_used < $last_month ]];then
            echo -e "User: $username | Created on: $user_age | \
                      Password last used: $password_last_used | \
                      Accesskey last used: $access_key2_last_used" >> ./idle-users.report
          fi
        elif [[ $access_key1_last_used != "NA" ]] && [[ $access_key2_last_used != "NA" ]];then
          local oldest=$password_last_used
          if [[ $access_key1_last_used < $oldest ]];then
            oldest=$access_key1_last_used
          fi
          if [[ $access_key2_last_used < $oldest ]];then
            oldest=$access_key2_last_used
          fi
          if [[ $oldest < $last_month ]];then
            echo -e "User: $username | Created on: $user_age | \
                      Password last used: $password_last_used | \
                      Accesskey last used: $access_key1_last_used $access_key2_last_used" \
                      >> ./idle-users.report
          fi
        fi
      fi
  done
  local idle_users
  idle_users=$(wc -l < ./idle-users.report)
  check sendEmail "$idle_users" ./idle-users.report
}

function setEmailHeader(){
  echo "From:$mail_from" > ./email.content
  {
    echo "To:$mail_to"
    echo "Cc:$mail_cc"
    echo "Subject: ATTENTION: $1 Inactive (>90 days) Users found in AWS"
    echo "Importance:High"
    echo ""
    echo "** REVIEW AND REMOVE USERS **"
    echo "Users who have not used AWS services in the last 90 days"
    echo "-----------------------------------------------------------------" 
  } >> ./email.content
}

function sendEmail(){
  setEmailHeader "$1"
  column -t "$2" >> ./email.content
  check /usr/sbin/sendmail -f "$mail_from" "$mail_to" "$mail_cc" < ./email.content
}

function check (){
  if ! "$@"; then
    echo "FAILED - $*"
    exit 1
  else
    echo "SUCCESS - $*"
  fi
}

function uploadReport(){
  report_date=$(date +%Y-%m-%d)
  report="$1"
  mv "$report" "$report_date"
  aws s3 cp "$report_date" s3://"$s3_path" --sse
}

function cleanFolder(){
  fileCount=$(aws s3 ls s3://"$s3_path" | wc -l)
  if [ "$fileCount" -gt "5" ]; then
    deleteFile=$(aws s3 ls s3://"$s3_path" | sep -n 1p | awk '{print $4}')
    aws s3 rm s3://"$s3_path"/"$deleteFile"
  fi
}

init