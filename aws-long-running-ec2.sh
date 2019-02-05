#!/bin/bash
#================================================================================
# Title          : aws-long-running-ec2.sh
# Description    : This script will scan the instances and notify users who
#                  have instances running longer than a week.
#
# Author         : https://github.com/abiydv
# Date           : 20181228
# Version        : 1
# Usage          : bash 
# Usage          : ./aws-long-running-ec2.sh
# Depends        :  
# Config files   : configs/aws-useradd.properties
#================================================================================

function init(){
  source ./configs/aws-useradd.properties
  check aws s3 cp s3://"${s3_path}${inventory_file}" .
  #lastStepCheck "Downloading user details from s3"
  getUsers
  getInstanceDetails
}

function getUsers(){
  # shellcheck disable=SC2006
  check aws ec2 describe-instances --region "$aws_region" --query \
  "Reservations[*].Instances[*].[Tags[?Key==`User`].Value]" \
    --output text | sort | uniq > ./user-list
}

function getInstanceDetails(){
  while read -r line
  do
    # shellcheck disable=SC2000
    if [ "$(echo "$line" | wc -c)" -eq 1 ];then
      continue
    fi

    check aws ec2 describe-instances --region "$aws_region" --filters "Name=tag:User,Values=$line" \
      --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,LaunchTime]' \
      --output text > ./user-instance-list

    sed -i "/\b\(stopped\|t2.micro\)\b/d" ./user-instance-list

    setEmailHeader "$line"

    while read -r instanceline
    do
      extract_date=$(echo "$instanceline" | cut -f4 -d " " | cut -f1 -d "T")
      launch_date=$(date -d "$extract_date" +%s)
      week_old_date=$(date -d 'now - 1 weeks' +%s)

      if [ "$launch_date" -lt "$week_old_date" ];then
        echo "$instanceline" >> ./user-email-list
      fi
    done < ./user-instance-list

    if [ "$(grep -c "i-" ./user-email-list)" -ne 0 ]; then
      setEmailFooter
      emailUser
    fi

  done < ./user-list
}

function getUserEmail(){
  grep -i "$1" ./"$file_name" > ./tmp
  if [ "$(wc -l < ./tmp)" -gt 1 ];then
    mail_to="$mail_from"
  else
    mail_to=$(cut -f5 -d "," ./tmp)
  fi
}

function setEmailHeader(){
  getUserEmail "$1"
  echo "From:$mail_from" > ./user-email-list
  {
    echo "To:$mail_to"
    echo "Cc:$mail_cc"
    echo "Subject: ATTENTION: $1: Your EC2 Instances"
    echo "Importance:High"
    echo ""
    echo "** REQUIRES YOUR IMMEDIATE ATTENTION AND ACTION **"
    echo "Instances older than a week tagged to you (tag:$1)"
    echo "--------------------------------------------------------" 
  } >> ./user-email-list
}

function setEmailFooter(){
  {
    echo ""
    echo "We have identified these long running instances that you have created"
    echo "Please review, and - "
    echo "1. Downgrade the instance type to avoid paying for excess capacity."
    echo "2. Terminate them immediately if you don't need them, to avoid excessive charges."
    echo ""
  } >> ./user-email-list
}

function emailUser(){
  /usr/sbin/sendmail -f "$mail_from" "$mail_to" "$mail_cc" < ./user-email-list
}

function check (){
  if ! "$@"; then
    echo "FAILED - $*"
    exit 1
  else
    echo "SUCCESS - $*"
  fi
}

init