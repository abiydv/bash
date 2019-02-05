#!/bin/bash
#================================================================================
# Title          : aws-lambda-monitor.sh
# Description    : This script will scan the lambdas and create a report with
#                  function which have not been executed for 2 months or more.
#                  It uploads the report to S3 and cleans up reports older than
#                  5 days.
#
# Author         : https://github.com/abiydv
# Date           : 20181228
# Version        : 1
# Usage          : ./aws-lambda-monitor.sh
# Depends        : Depends on the library libs/jq 
# Config files   : configs/aws-lambda-monitor.properties and 
#                  configs/email.properties
#================================================================================

function init(){
  source ./configs/email.properties
  source ./configs/aws-lambda-monitor.properties
  getLambdas
  getLambdaRuns
  setEmailHeader
  setEmailBody
  setEmailFooter
  sendEmail
  uploadReport
  cleanup
  cleanFolder
}

function uploadReport(){
  report_date=$(date +%Y-%m-%d)
  report="./report.csv"
  mv "$report" "$report_date"
  aws s3 cp "$report_date" s3://"$s3_path" --sse
}

function cleanup(){
  rm -f ./*.tmp
  rm -f ./*.list
}

function getLambdas(){
  check aws lambda list-functions --region "$aws_region" > ./lambda.tmp
  jq -r '.Functions[].FunctionName' ./lambda.tmp > ./lambdaName.list
}

function getLambdaRuns(){
  echo "Fetching Lambda execution details"
  echo "<tr><th align=\"left\"> Lambda Name </th><th align=\"left\"> Not run since </th></tr>" > ./report
  
  true > ./report.csv

  while read -r fn_name
  do
    echo ""
    echo "$fn_name ========== "
    local state
    state="INACTIVE"
    local prefix1
    prefix1=$(date +%Y/%m)
    local prefix2
    prefix2=$(date +%Y/%m -d 'now -1 month')
    local prefix3
    prefix3=$(date +%Y/%m -d 'now -2 months')

    for i in $prefix1 $prefix2 $prefix3; do
      true >./stream.list

      check aws logs describe-log-streams --log-group-name /aws/lambda/"$fn_name" \
      --descending --log-stream-name-prefix "$i" \
      --region "$aws_region" | jq -r '.logStreams[]' > ./stream.list

      if [[ -s ./stream.list ]];then
        echo "Executed in $i"
        state="ACTIVE"
        break
      else
        echo "NO Executions in $i"
      fi
    done

    if [ ${state} == "ACTIVE" ];then
      echo "MARK: ACTIVE"
    else
      echo "MARK: INACTIVE"
      echo "<tr><td align=\"left\"> $fn_name </td><td align=\"left\"> $prefix3 </td></tr>" >> ./report
      echo "${fn_name}" >> ./report.csv
    fi
  done < ./lambdaName.list
}

function sendEmail(){
  check /usr/sbin/sendmail -f "$mail_from" "$mail_to" "$mail_cc" < ./email-report
}

function setEmailHeader(){
  local count
  count=$(wc -l < ./report.csv)
  echo "From:$mail_from" > ./email-report
  {
    echo "To:$mail_to"
    echo "Cc:$mail_cc"
    echo "Subject: ATTENTION: $count Idle Lambdas (>2 months)"
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
    echo "<h4>$count Lambdas have no executions since last 2 months</h4>"
  } >> ./email-report
}

function setEmailBody(){
  {
    echo "<br>Complete list below<br><br>"
    echo "<table class=\"emailTable\">"
    cat ./report
    echo "</table>"
  } >> ./email-report
}

function setEmailFooter(){
  {
    echo ""
    echo "</html>"
  } >> ./email-report
}

function check (){
  if ! "$@"; then
    echo "FAILED - $*"
    exit 1
  else
    echo "SUCCESS - $*"
  fi
}

function cleanFolder(){
  fileCount=$(aws s3 ls s3://"$s3_path" | wc -l)
  if [ "$fileCount" -gt "5" ]; then
    deleteFile=$(aws s3 ls s3://"$s3_path" | sed -n 1p | awk '{print $4}')
    check aws s3 rm s3://"$s3_path"/"$deleteFile"
  fi
}

export PATH=$PATH:../libs/
init