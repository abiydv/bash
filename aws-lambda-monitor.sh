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
#!/bin/bash

function init(){
  source ./configs/email.properties
  source ./configs/aws-lambda-monitor.properties
  local today=$(date +%Y-%m-%d -d 'now +1 day')
  local expiry=$(date +%Y-%m-%d -d 'now -2 months')
  getLambdas
  getLambdaRuns ${today} ${expiry}
  setEmailHeader "./email-report" "./report.csv" $today $expiry
  setEmailBody "./email-report" "./report"
  setEmailFooter "./email-report"
  sendEmail "./email-report"
  uploadReport "./report.csv"
  cleanup
  cleanFolder
}

function uploadReport(){
  report_date=$(date +%Y-%m-%d)
  report=$1
  mv $report $report_date
  aws s3 cp $report_date s3://${s3_path} --sse
}

function cleanup(){
  rm -f *.tmp
  rm -f *.list
}

function getLambdas(){
  aws lambda list-functions --region ${aws_region} > ./lambda.tmp
  lastStepCheck "Fetching details of all lambdas in aws account"
  jq -r '.Functions[].FunctionName' ./lambda.tmp > ./lambdaName.list
}

function getLambdaRuns(){
  echo "Fetching Lambda execution details"
  echo "<tr><th align=\"left\"> Lambda Name </th><th align=\"left\"> Not run since </th></tr>" > ./report
  
  > ./report.csv

  while read fn_name
  do
    echo ""
    echo "${fn_name} ========== "
    local state="INACTIVE"
    local prefix1=$(date +%Y/%m)
    local prefix2=$(date +%Y/%m -d 'now -1 month')
    local prefix3=$(date +%Y/%m -d 'now -2 months')

    for i in $prefix1 $prefix2 $prefix3; do
      >./stream.list

      aws logs describe-log-streams --log-group-name /aws/lambda/${fn_name} --descending --log-stream-name-prefix ${i} \
      --region ${aws_region} | jq -r '.logStreams[]' > ./stream.list

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
      echo "<tr><td align="left"> ${fn_name} </td><td align="left"> ${prefix3} </td></tr>" >> ./report
      echo "${fn_name}" >> ./report.csv
    fi
  done < ./lambdaName.list
}

function sendEmail(){
  /usr/sbin/sendmail -f $mail_from $mail_to $mail_cc < $1
}

function setEmailHeader(){
  local count=$(echo $2 | wc -l)
  echo "From:$mail_from" > $1
  echo "To:$mail_to" >> $1
  echo "Cc:$mail_cc" >> $1
  echo "Subject: ATTENTION: $count Idle Lambdas (>2 months)" >> $1
  echo "Content-Type: text/html; charset=\"us-ascii\"" >> $1
  echo "Content-Transfer-Encoding: binary"  >> $1
  echo "MIME-Version: 1.0"  >> $1
  echo "Importance:High" >> $1
  echo "<html><head>" >> $1
  echo "<style type="text/css">" >> $1
  echo "* { font-family: Arial !important; }" >> $1
  echo ".emailTable { background-color:#eee;border-collapse:collapse; }" >> $1
  echo ".emailTable th { background-color:#000;color:white;width:50%; }" >> $1
  echo ".emailTable td, .emailTable th { padding:5px;border:1px solid #000; }" >> $1
  echo "</style></head>" >> $1
  echo "<h4>$count Lambdas have no executions since last 2 months</h4>" >> $1
}

function setEmailBody(){
  echo "<br>Complete list below<br><br>" >> $1
  echo "<table class="emailTable">" >> $1
  cat $2 >> $1
  echo "</table>" >> $1
}

function setEmailFooter(){
  echo "" >> $1
  echo "</html>" >> $1
}

function lastStepCheck(){
  if [ $? -ne 0 ]; then
    echo "ERROR: ${1} failed"
    exit 1
  else
    echo "${1} successful"
  fi
}

function cleanFolder(){
  fileCount=$(aws s3 ls s3://${s3_path} | wc -l)
  if [ "$fileCount" -gt "5" ]; then
    deleteFile=$(aws s3 ls s3://${s3_path} | sed -n 1p | awk '{print $4}' )
    aws s3 rm s3://${s3_path}/${deleteFile}
  fi
}

export PATH=$PATH:../libs/
init