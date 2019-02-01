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
#!/bin/bash

function init(){
  source ./configs/aws-useradd.properties
  aws s3 cp s3://${s3_path}${inventory_file} .
  lastStepCheck "Downloading user details from s3"
  getUsers
  getInstanceDetails
}

function getUsers(){
  aws ec2 describe-instances --region ${aws_region} --query "Reservations[*].Instances[*].[Tags[?Key==`User`].Value]" \
    --output text | sort | uniq > ./user-list
  lastStepCheck "Fetching details of all users in aws account"
}

function getInstanceDetails(){
  while read line
  do
    if [ $(echo $line | wc -c) -eq 1 ];then
      continue
    fi

    aws ec2 describe-instances --region ${aws_region} --filters "Name=tag:User,Values=$line" \
      --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,LaunchTime]' \
      --output text > ./user-instance-list

    sed -i "/\b\(stopped\|t2.micro\)\b/d" ./user-instance-list
    lastStepCheck "Fetching details of all instances for $line"

    setEmailHeader "./user-email-list" $line

    while read instanceline
    do
      extract_date=$(echo $instanceline | cut -f4 -d " " | cut -f1 -d "T")
      launch_date=$(date -d $extract_date +%s)
      week_old_date=$(date -d 'now - 1 weeks' +%s)

      if [ $launch_date -lt $week_old_date ];then
        echo $instanceline >> ./user-email-list
      fi
    done < ./user-instance-list

    if [ $(grep "i-" ./user-email-list | wc -l) -ne 0 ]; then
      setEmailFooter "./user-email-list"
      emailUser "./user-email-list" $line
    fi

  done < ./user-list
}

function getUserEmail(){
  grep -i $1 ./${file_name} > ./tmp
  if [ $(wc -l < ./tmp) -gt 1 ];then
    mail_to=$mail_from
  else
    mail_to=$(cut -f5 -d "," ./tmp)
  fi
}

function setEmailHeader(){
  getUserEmail $2
  email_content=$1
  echo "From:$mail_from" > $email_content
  echo "To:$mail_to" >> $email_content
  echo "Cc:$mail_cc" >> $email_content
  echo "Subject: ATTENTION: $2: Your EC2 Instances" >>$email_content
  echo "Importance:High" >> $email_content
  echo "" >> $email_content
  echo "** REQUIRES YOUR IMMEDIATE ATTENTION AND ACTION **" >> $email_content
  echo "Instances older than a week tagged to you (tag:$2)" >> $email_content
  echo "--------------------------------------------------------" >> $email_content
}

function setEmailFooter(){
  echo "" >> $1
  echo "We have identified these long running instances that you have created" >> $1
  echo "Please review, and - " >> $1
  echo "1. Downgrade the instance type to avoid paying for excess capacity." >> $1
  echo "2. Terminate them immediately if you don't need them, to avoid excessive charges." >> $1
  echo "" >> $1
}

function emailUser(){
  user=$2
  mailcontent=$1
  /usr/sbin/sendmail -f $mail_from $mail_to $mail_cc < $mailcontent
}

function lastStepCheck(){
  if [ $? -ne 0 ]; then
    echo "$1 failed"
    exit 1
  else
     echo "$1 successful"
  fi
}

init
