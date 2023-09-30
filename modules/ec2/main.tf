// Data filter searches for AMI 

data "aws_ami" "rhel9" {
  most_recent = true

  filter {
    name   = "image-id"
    values = ["ami-03a291743697ffd0b"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  } 

  filter {
    name   = "name"
    values = ["composer-api-48539f0a-8fd7-4c46-a304-6032982a3631"]
  }
}


// IAM role that gives access to SSM + S3 via EC2 instance 

resource "aws_iam_role" "S3-SSM-IamRole" {
  name = "ss3-ssm-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

// S3 Policy creation 

resource "aws_iam_policy" "policy-for-s3" {
  name        = "policy-for-s3"
  description = "Policy for S3"

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

// iam policy for ssm 

resource "aws_iam_policy" "policy-for-ssm" {
  name = "ssm-policy"

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

// Policy attachment for ssm and s3 policy to role

resource "aws_iam_role_policy_attachment" "s3-ssm-attach" {
  for_each = {
    "policy-for-s3"   = aws_iam_policy.policy-for-s3.arn
    "policy-for-ssm"  = aws_iam_policy.policy-for-ssm.arn
    "s3-full-access"  = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    "ssm-full-access" = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
  }

  role       = aws_iam_role.S3-SSM-IamRole.name
  policy_arn = each.value
}

// Adding role to instance profile

resource "aws_iam_instance_profile" "instance_profile" {
  name = "S3-SSM-IamProfile"
  role = aws_iam_role.S3-SSM-IamRole.name
}


//Creation of EC2 instance

resource "aws_instance" "ec2_public" {
  //count                       = 1
  ami                         = data.aws_ami.rhel9.id
  associate_public_ip_address = true
  instance_type               = "t3.2xlarge"
  key_name                    = var.key_name
  subnet_id                   = var.vpc.public_subnets[0]
  vpc_security_group_ids      = [var.sg_pub_id]
  iam_instance_profile        = "S3-SSM-IamProfile"
  tags = {
    "Name" = "${var.namespace}"
  }

  provisioner "file" {
    source      = "./${var.key_name}.pem"
    destination = "/home/ec2-user/${var.key_name}.pem"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.key_name}.pem")
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 ~/${var.key_name}.pem"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.key_name}.pem")
      host        = self.public_ip
    }
  }
// Configuration of EC2 instance
  provisioner "remote-exec" {
    inline = [ 
      "sudo subscription-manager remove --all",        
      "sudo subscription-manager clean",
      "sudo subscription-manager register --username rh-ee-oezeakac  --password Ambrosius925! --auto-attach",
      "sudo yum repolist",
      "sudo yum install unzip -y",
      "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "sudo yum install -y https://s3.eu-west-1.amazonaws.com/amazon-ssm-eu-west-1/latest/linux_amd64/amazon-ssm-agent.rpm",
      "sudo systemctl enable amazon-ssm-agent",
      "sudo systemctl start amazon-ssm-agent",
      "sudo yum install openscap-scanner scap-security-guide -y"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${var.key_name}.pem")
      host        = self.public_ip
    }
  }
}