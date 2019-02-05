#!/bin/bash
#================================================================================
# Title          : aws-ebs-daily-monitor.sh
# Description    : This script will generate a report for idle datapipelines not
#                  run for more than 2 months. The script will upload this report 
#                  to S3 path and also remove reports older than 5 days.
#
# Author         : https://github.com/abiydv
# Date           : 20181228
# Version        : 1
# Usage          : ./aws-datapipeline-monitor.sh
# Depends        : Depends on the library libs/jq 
# Config files   : configs/datapipeline-monitor.properties and 
#                  configs/email.properties
#================================================================================

function init(){
    source ./configs/datapipeline-monitor.properties
    source ./configs/email.properties
    local today
    today=$(date +%Y-%m-%d -d 'now +1 day')
    local expiry
    expiry=$(date +%Y-%m-%d -d 'now -2 months')
    getPipelines
    getPipelineRuns "$today" "$expiry"
    setEmailHeader "./email-report" "./report.csv" "$today" "$expiry"
    setEmailBody "./email-report" "./report"
    setEmailFooter "./email-report"
    sendEmail "./email-report"
    uploadReport "./report.csv"
    cleanup
    cleanFolder
}

function uploadReport(){
    report_date=$(date +%Y-%m-%d)
    report="$1"
    mv "$report" "$report_date"
    aws s3 cp "$report_date" "$s3_path" --sse
}

function cleanup(){
    rm -f ./*.tmp
    rm -f ./*.list
}

function getPipelines(){
    check aws datapipeline list-pipelines --region "$aws_region" > ./pipeline.tmp
    jq -r '.pipelineIdList[].id' ./pipeline.tmp > ./pipelineId.list
}

function getPipelineRuns(){
    local today=$1
    local expiry=$2
    echo "Checking for pipeline runs between $today and $expiry"
    echo "<tr><th align=\"left\"> Pipeline Name </th><th align=\"left\"> Pipeline Id </th></tr>" > ./report
    true >./report.csv
    while read -r pid
    do
        check aws datapipeline list-runs --pipeline-id "$pid" --start-interval "$expiry"T00:00:00,"$today"T00:00:00 \
        --region "$aws_region" --output json > "$pid"-runs.list
                
        size=$(wc -l < "$pid"-runs.list)
            if [ "$size" -lt 1 ] || [ "$size" -eq 1 ];then
                echo "$(jq -r '.pipelineIdList[] | select (.id == "'"${pid}"'") | '\
                '.name' pipeline.tmp),${pid}" >> ./report.csv
                        
                echo "<tr><td align=\"left\">$(jq -r '.pipelineIdList[] | select (.id == "'"${pid}"'") '\
                '| .name' pipeline.tmp)</td><td align=\"left\">${pid}</td></tr>" >> ./report
                        
                echo "INACTIVE: ${pid} : $(jq -r '.pipelineIdList[] | select (.id == "'"${pid}"'") '\
                '| .name' pipeline.tmp)"
            else
                echo "ACTIVE: ${pid} : $(jq -r '.pipelineIdList[] | select (.id == "'"${pid}"'") '\
                '| .name' pipeline.tmp)"
            fi
    done < ./pipelineId.list
}

function sendEmail(){
    /usr/sbin/sendmail -f "$mail_from" "$mail_to" "$mail_cc" < "$1"
}

function setEmailHeader(){
    local count
    count=$(wc -l < "$2")
    echo "From:$mail_from" > "$1"
    {    
        echo "To:$mail_to"
        echo "Cc:$mail_cc"
        echo "Subject: ATTENTION: $count Idle Data Pipelines (>2 months)"
        echo "Content-Type: text/html; charset=\"us-ascii\""
        echo "Content-Transfer-Encoding: binary"
        echo "MIME-Version: 1.0"
        echo "Importance:High"
        echo "<html><head>"
        echo "<style type=\"text/css\">"
        echo "* { font-family: Arial !important; }"
        echo ".emailTable { background-color:#eee;border-collapse:collapse; }"
        echo ".emailTable th { background-color:#000;color:white;width:50%; }"
        echo ".emailTable td, .emailTable th { padding:5px;border:1px solid #000; }"
        echo "</style></head>"
        echo "<h4>$count Data Pipelines have no executions for past 2 months ($3 to $4)</h4>"
    } >> "$1"
}

function setEmailBody(){
    {
        echo "<br>Complete list below<br><br>"
        echo "<table class=\"emailTable\">"
        cat "$2"
        echo "</table>"
    } >> "$1"
}

function setEmailFooter(){
    {
        echo "<h4>Idle pipelines will be deleted in the next 7 days. </h4>"
        echo "</html>"
    } >> "$1"
}

function check (){
  if ! "$@"; then
    echo "FAILED - $*"
    exit 1
  else
    echo "SUCCESS - $*"
  fi
}

cleanFolder(){
    fileCount=$(aws s3 ls "$s3_path" | wc -l)
    if [ "$fileCount" -gt "5" ]; then
      deleteFile=$(aws s3 ls "$s3_path" | sed -n 1p | awk '{print $4}')
      aws s3 rm "${s3_path}"/"${deleteFile}"
    fi
}

export PATH=$PATH:../libs/
init
cleanFolder
