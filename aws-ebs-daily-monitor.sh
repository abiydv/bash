#!/bin/bash
#================================================================================
# Title          : aws-ebs-daily-monitor.sh
# Description    : This script will generate a daily ebs volume report.
#                  To identify the user of a volume, ec2-instance and volume must
#                  have the tag "user":"name". The script will upload this report 
#                  to a given S3 path and also removes reports older than 5 days.       
#
# Author         : https://github.com/abiydv
# Date           : 20181228
# Version        : 1
# Usage          : ./aws-ebs-daily-monitor.sh
# Depends        : Depends on the library libs/jq 
# Config files   : configs/aws-ebs-daily-monitor.properties and 
#                  configs/email.properties
#================================================================================

function uploadReport(){
        local S3_PATH=$1
        local DATED=$2
        mv final_report ./archive/"${DATED}"
        check aws s3 cp ./archive/"${DATED}" "${S3_PATH}" --sse
}

function cleanFolder(){
        local S3_PATH=$1
        fileCount=$(aws s3 ls "${S3_PATH}" | wc -l)
        if [ "$fileCount" -gt "5" ]; then
        deleteFile=$( aws s3 ls "${S3_PATH}" | sed -n 1p | awk '{print $4}' )
        check aws s3 rm "${S3_PATH}"/"${deleteFile}"
        fi
}

function check (){
  if ! "$@"; then
    echo "FAILED - $*"
    exit 1
  else
    echo "SUCCESS - $*"
  fi
}

source ./configs/aws-ebs-daily-monitor.properties
source ./configs/email.properties
DATED=$(date +%Y-%m-%d)

check aws ec2 describe-volumes --region "${REGION}" --filters Name=status,Values=available \
--query 'Volumes[*].[VolumeId,Size,CreateTime]' --output text > ebs-available-volumes

check aws ec2 describe-volumes --region "${REGION}" --filters Name=status,Values=in-use  \
--query 'Volumes[*].[VolumeId,Size,CreateTime,Attachments[*].InstanceId]' \
--output text | paste -d "\t" - - > ebs-inuse-volumes

true > ebs-volume-owners

while read -r line; do
    instance=$(echo "$line" | awk -F " " '{print $4}')
    created=$(echo "$line" | awk -F " " '{print $3}')
    size=$(echo "$line" | awk -F " " '{print $2}')
    volume=$(echo "$line" | awk -F " " '{print $1}')
        
    # shellcheck disable=SC2006
    owner=$(aws ec2 describe-instances --region "$REGION" \
    --filters Name=instance-id,Values="$instance" \
    --query "Reservations[*].Instances[*].[Tags[?Key==`User`].Value]" \
    --output text)
       
    printf "\n%s\t%s\t%s\t%s\t%s" "$volume" "$size" "$created" "$instance" "$owner" >> ebs-volume-owners
done < ebs-inuse-volumes

check aws ec2 describe-volumes --region "${REGION}"  --query 'Volumes[*].{Size:Size}' \
--output text > ebs-volume-sizes
total_ebs_usage=$(awk '{s+=$1} END {printf "%.0f", s}' ebs-volume-sizes)

printf "To:%s\nSubject: Daily EBS Report\n" "$mail_to" > final_report
{
    printf "DAILY EBS REPORT\n\n"
    printf "Total EBS capacity in account (including available EBS): \
      %s GB\n\n" "$total_ebs_usage"
    printf "EBS Volumes in available state not attached to any instances \
    \n---------------------------------------------------------------\n"
    printf "VolumeId\tSize(GB)\tCreated\n"
    cat ebs-available-volumes
    printf "\nEBS Volumes attached to instances\n----------------------------\
    -----------------------------------\n"
    printf "VolumeId\tSize(GB)\tCreated\t\tInstanceId\tUser"
    sort -k 5  ebs-volume-owners
    echo 
} >> final_report

check /usr/sbin/sendmail -f "$mail_from" "$mail_to" "$mail_cc" < final_report
uploadReport "$s3_path" "$DATED"
cleanFolder "$s3_path"