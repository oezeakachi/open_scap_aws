# Import Networking module that creates VPC and configures networking - SG etc
module "networking" {
  source    = "./modules/networking"
  namespace = var.namespace
}

# Imports modules that creates ssh key that uploads private key to aws and keeps the public key in a specified directory
module "ssh-key" {
  source    = "./modules/ssh-key"
  namespace = var.namespace
}


# Maps the environment variable to default bucket_name 

variable "environment" {
  type    = map
  default = {
    bucket_name = "Scap_Results"
  }
}

# S3 Bucket creation

resource "aws_s3_bucket" "SCAPScanResultsBucket" {
  bucket = "${var.SCAPScanResults}"
  //acl    = "public-read-write"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }
}

# Setting access to S3 bucket
resource "aws_s3_bucket_public_access_block" "SCAPScanResultsBucketPublicAccessBlock" {
  bucket                            = aws_s3_bucket.SCAPScanResultsBucket.id
  block_public_acls                 = false
  block_public_policy               = false
  ignore_public_acls                = false
  restrict_public_buckets           = false
}

# Creation of S3 bucket policy
resource "aws_s3_bucket_policy" "SCAPScanResultsBucketPolicy" {
  bucket = aws_s3_bucket.SCAPScanResultsBucket.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny"
        Action    = ["s3:*"]
        Resource  = [aws_s3_bucket.SCAPScanResultsBucket.arn, "${aws_s3_bucket.SCAPScanResultsBucket.arn}/*"]
        Principal = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport": "false"
          }
        }
      }
    ]
  })
}

# Imports the EC2 Module which creates the EC2 instance to be tested

module "ec2" {
  source     = "./modules/ec2"
  namespace  = var.namespace
  vpc        = module.networking.vpc
  sg_pub_id  = module.networking.sg_pub_id
  key_name   = module.ssh-key.key_name
  
}




# Creates cloudwatch Logs

resource "aws_cloudwatch_log_group" "lambda_activities" {
  name              = "Lambda_logs"
}


# Cloudwatch role creation

resource "aws_iam_role" "CW-Access-IamRole" {
  name = "cw-logs-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Cloudwatch policy creation

resource "aws_iam_policy" "policy-for-cw" {
  name        = "policy-for-cw"
  description = "Policy for cw"

 policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:eu-west-1:121525555092:my-scap-scan-bucket"
    }
  ]
}
)
}

# Attachment of policy to role

resource "aws_iam_role_policy_attachment" "cw-attach" {
  for_each = {
    "policy-for-cw"   = aws_iam_policy.policy-for-cw.arn
    "cloudwatch-full-access" = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  }

  role       = aws_iam_role.CW-Access-IamRole.name
  policy_arn = each.value
}

# Attachment of role to instance profile

resource "aws_iam_instance_profile" "lambda_profile" {
  name = "CW-IamProfile"
  role = aws_iam_role.CW-Access-IamRole.name
}

# Creation of clouwatch group and setting of retention policy 

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "Scap_filtering"
  retention_in_days = 7
  lifecycle {
    prevent_destroy = false
  }
}



/*
resource "aws_s3_bucket_notification" "SCAPScanResultsBucketNotification" {
  bucket = aws_s3_bucket.SCAPScanResultsBucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ProcessSCAPScanResults.arn
    events              = ["s3:ObjectCreated:*"]
  }
} */



# Creation of Lambda function 

resource "aws_lambda_function" "ProcessSCAPScanResults" {
  filename      = "${path.module}/lambda_function.py.zip"
  function_name = "ProcessSCAPScanResults"
  role          = aws_iam_role.SCAPEC2InstanceRole.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
  timeout       = 300
  memory_size      = 512 //Increase if needed to avoid timeout of lambda
  source_code_hash = filebase64sha256("${path.module}/lambda_function.py.zip")
  depends_on    = [aws_cloudwatch_log_group.lambda_log_group]
}


# Creation of role for lambda

resource "aws_iam_role" "SCAPEC2InstanceRole" {
  name = "SCAPEC2InstanceRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

// Policy to give lambda access to S3

resource "aws_iam_policy" "policy-for-s3-scap" {
  name        = "policy-for-s3-scap"
  description = "Policy for-s3-scap"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
EOF
}

/*
resource "aws_iam_role_policy_attachment" "s3-scap-attach" {
    
    
 
  role       = aws_iam_role.SCAPEC2InstanceRole.name
  policy_arn = aws_iam_policy.policy-for-s3-scap.arn
} */

// policy to give lambda acces to ssm
resource "aws_iam_policy" "policy-for-ssm-scap" {
  name = "policy-for-ssm-scap"

  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ssm:*",
            "Resource": "*"
        }
    ]
}
EOF
}

// policy to give lambda access to dynamodb
resource "aws_iam_policy" "policy-for-dynamodb-scap" {
  name = "policy-for-dynamodb-scap"

  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "dynamodb:*",
            "Resource": "*"
        }
    ]
}
EOF
} 

// Policy to give lambda access to Security Hub

resource "aws_iam_policy" "policy-for-security-hub-scap" {
  name = "policy-for-security-hub-scap"

  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "securityhub:*",
            "Resource": "*"
        }
    ]
}
EOF
} 


/*
resource "aws_iam_role_policy_attachment" "ssm-scap-attach" {
    
    
 
  role       = aws_iam_role.SCAPEC2InstanceRole.name
  policy_arn = aws_iam_policy.policy-for-ssm-scap.arn
} */


// Attaching the policies to the role the SCAPEC2InstanceRole

resource "aws_iam_role_policy_attachment" "s3-scap-ssm-attach" {
  for_each = {
    "policy-for-s3-scap" = aws_iam_policy.policy-for-s3-scap.arn
    "policy-for-ssm-scap"  = aws_iam_policy.policy-for-ssm-scap.arn
    "policy-for-dynamodb-scap"  = aws_iam_policy.policy-for-dynamodb-scap.arn
    "policy-for-security-hub-scap" = aws_iam_policy.policy-for-security-hub-scap.arn
    "cloudwatch-full-access" = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    //"s3-full-access"  = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    //"ssm-full-access" = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
  }

  role       = aws_iam_role.SCAPEC2InstanceRole.name
  policy_arn = each.value
}

// Create S3 bucket notification to create S3 ObjectCreated event for .xml file types

resource "aws_s3_bucket_notification" "SCAPScanResultsBucketNotification" {
  bucket = aws_s3_bucket.SCAPScanResultsBucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ProcessSCAPScanResults.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".xml"
  }

} 

// Create lambda permission to invoke function when it recieves S3 notification

resource "aws_lambda_permission" "S3InvokeLambdaPermission" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ProcessSCAPScanResults.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.SCAPScanResultsBucket.arn
}

// SSM checks if Security Hub is enabled 

resource "aws_ssm_parameter" "EnableSecurityHubFindingsParameter" {
  name        = "/SCAPTesting/EnableSecurityHub"
  description = "Determines if Security Hub is used by the ProcessSCAPScanResults Lambda Function"
  type        = "String"
  value       = var.EnableSecurityHubFindings
}





# DynamoDB table to hold the ignore list
# Note that backups are not enabled for this table, if you wish to enable backup you 
# can set PointInTimeRecoveryEnabled for the table
resource "aws_dynamodb_table" "SCAPScanIgnoreList" {
  name           = "SCAPScanIgnoreList"
  #billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 1
  write_capacity = 2
  hash_key       = "SCAP_Rule_Name"
  attribute {
    name = "SCAP_Rule_Name"
    type = "S"
  }


}

resource "aws_dynamodb_table" "SCAPScanResults" {
  name           = "SCAPScanResults"
  #billing_mode   = "PAY_PER_REQUEST"
  read_capacity  = 1
  write_capacity = 2
  hash_key       = "InstanceId"
  range_key = "SCAP_Rule_Name"
  attribute {
    name = "InstanceId"
    type = "S"
  }

  attribute {
    name = "SCAP_Rule_Name"
    type = "S"
  }
}

// SSM Document creation

resource "aws_ssm_document" "scan-process" {
  name            = "scanning"
  document_format = "YAML"
  document_type   = "Command"
  content = <<DOC
    schemaVersion: '1.2'
    description: Check ip configuration of a Linux instance.
    parameters: {}
    runtimeConfig:
      'aws:runShellScript':
        properties:
          - id: '0.aws:runShellScript'
            runCommand:  
              - echo "Add the ssg-fedora-ds.xml to the scriptFile variable"
              - scriptFile='/usr/share/xml/scap/ssg/content/ssg-fedora-ds.xml'
              - echo "Run Openscap command"
              - oscap xccdf eval --fetch-remote-resources --profile  xccdf_org.ssgproject.content_profile_standard --results-arf arf.xml --report report.html $scriptFile
              - echo "Grab instance id"
              - instanceId=$(curl http://169.254.169.254/latest/meta-data/instance-id)
              - echo "Create Timestamp"
              - timestamp=$(date +%d-%m-%Y-%T)
              - echo "S3 copy arf.xml"
              - /usr/local/bin/aws s3 cp arf.xml s3://${aws_s3_bucket.SCAPScanResultsBucket.id}/${module.ec2.instance_id}/$timestamp-scap-results.xml
              - echo "S3 copy report.xml"
              - /usr/local/bin/aws s3 cp report.html s3://${aws_s3_bucket.SCAPScanResultsBucket.id}/${module.ec2.instance_id}/$timestamp-scap-results.html
              - echo " Create error log"
              - touch error.log
              - if [ $? -ne 0 ]; then  echo "Error occurred during script execution" >> error.log; fi
              - echo "S3 copy error log"
              - /usr/local/bin/aws s3 cp error.log s3://${aws_s3_bucket.SCAPScanResultsBucket.id}/${module.ec2.instance_id}/error.log
DOC
} 

// SSM Document is invoked

resource "aws_ssm_association" "run_ssm" {
  name = aws_ssm_document.scan-process.name

  targets {
    key    = "InstanceIds"
    values = ["${module.ec2.instance_id}"]
  }
}




/*
resource "aws_lambda_invocation" "invoke_lambda" {
  function_name = aws_lambda_function.ProcessSCAPScanResults.arn
  input         = "{}" // set your input payload here
}*/
