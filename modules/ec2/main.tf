data "aws_ami" "obi-fedora" {
  most_recent = true

  filter {
    name   = "image-id"
    values = ["ami-01e8b0324bd546dc6"]
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
    values = ["obi-fedora"]
  }
}



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


resource "aws_iam_instance_profile" "instance_profile" {
  name = "S3-SSM-IamProfile"
  role = aws_iam_role.S3-SSM-IamRole.name
}




resource "aws_instance" "ec2_public" {
  //count                       = 1
  ami                         = data.aws_ami.obi-fedora.id
  associate_public_ip_address = true
  instance_type               = "t3.2xlarge"
  key_name                    = var.key_name
  subnet_id                   = var.vpc.public_subnets[0]
  vpc_security_group_ids      = [var.sg_pub_id]
  iam_instance_profile        = "S3-SSM-IamProfile"
  //iam_instance_profile        = "${aws_iam_instance_profile.S3_profile.name},${aws_iam_instance_profile.SSM_profile.name}"
  //iam_instance_profile        = count.index == 0 ? aws_iam_instance_profile.S3_profile.name : aws_iam_instance_profile.SSM_profile.name
  //user_data = data.template_file.init.rendered

  tags = {
    "Name" = "${var.namespace}"
  }

  provisioner "file" {
    source      = "./${var.key_name}.pem"
    destination = "/home/fedora/${var.key_name}.pem"

    connection {
      type        = "ssh"
      user        = "fedora"
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
      user        = "fedora"
      private_key = file("${var.key_name}.pem")
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [ 
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
      user        = "fedora"
      private_key = file("${var.key_name}.pem")
      host        = self.public_ip
    }
  }
}
