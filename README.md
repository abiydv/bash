# Bash Scripts
[![Build Status](https://travis-ci.org/abiydv/bash.svg?branch=master)](https://travis-ci.org/abiydv/bash)
[![CodeFactor](https://www.codefactor.io/repository/github/abiydv/bash/badge)](https://www.codefactor.io/repository/github/abiydv/bash)

![bash-shell](https://github.com/abiydv/ref-docs/blob/master/images/logos/bash-shell.png)

Bash scripts for some mundane tasks on AWS

### [AWS Datapipeline monitor](./aws-datapipeline-monitor.sh)
This script monitors the Data pipelines in your AWS account and emails you a report if there are no executions for over 2 months. AWS charges for each data pipeline in your account, so it is prudent to clear up old ones not being used anymore. It also uploads this report to S3.

### [AWS EBS daily monitor](./aws-ebs-daily-monitor.sh)
This script monitors the EBS volumes in your AWS account and emails you a report with details of unattached volumes along with the user details of all the volumes (extracted from tags applied to the volume). Unattached EBS volumes also cost you, so it's better to clear up volumes not in use. It also uploads this report to S3.

### [AWS extract IAM policies](./aws-extract-iam-policies.sh)
This script extracts the IAM policies to your local. Helpful if you want to commit the policies to a version control system. It can even be automated by scheduling it to run on a daily/weekly basis. AWS versions your policies but only 5 last versions are available. So it may help to have more versions available outside AWS

### [AWS Lambda monitor](./aws-lambda-monitor.sh)
This script monitors the lambda executions in your AWS account and emails you details of functions which are sitting idle. Since creating Lambda functions is so easy, it often slips attention and the list keeps growing. This script can cleanup your account of all the idle functions. It also uploads this report to s3.

### [AWS long running EC2](./aws-long-running-ec2.sh)
This script notifies users who have EC2 instances running longer than a week in your AWS account. People often create them and "forget". It nudges them lightly to stop them if not being used anymore. It depends on a list of users in your account mapped with their emails - saved on s3.

### [AWS IAM User add](./aws-useradd.sh)
Automate user addition and inventory them. It also sends them emails with username/passowrd and what to do next. We like them to setup their MFA etc. and also send along a doc explaining the steps.

### [AWS IAM User audit](./aws-useraudit.sh)
Audit your IAM userlist and remove long idle users. Crucial to keep your account acces secure.
