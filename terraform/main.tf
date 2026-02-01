#################
# Data sources
#################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Ubuntu 22.04 LTS (Jammy)
data "aws_ami" "ubuntu_jammy" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#################
# Key pair
#################

resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

#################
# Security group
#################

resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg-${var.aws_region}"
  description = "Allow SSH, Jenkins (8080) and SonarQube (9000)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "SonarQube"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-sg"
  }
}

#################
# IAM Role / Instance Profile
#################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "jenkins-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "jenkins-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

#################
# IAM User (demo / learning only)
#################

resource "aws_iam_user" "admin_user" {
  name = var.iam_user_name
}

resource "aws_iam_user_policy_attachment" "admin_ec2_attach" {
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_access_key" "admin_key" {
  user = aws_iam_user.admin_user.name
}

#################
# EC2 Instance
#################

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu_jammy.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.deployer.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y \
  curl wget gnupg lsb-release \
  openjdk-17-jre-headless \
  docker.io ufw

systemctl enable --now docker

usermod -aG docker ubuntu

# Firewall
ufw allow 22
ufw allow 8080
ufw allow 9000
ufw --force enable

# Jenkins
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | tee /etc/apt/keyrings/jenkins.asc > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/jenkins.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

systemctl enable --now jenkins

# Jenkins hardening
echo 'JENKINS_ARGS="--argumentsRealm.passwd.admin=disabled --argumentsRealm.roles.admin=admin"' \
  > /etc/default/jenkins

systemctl restart jenkins

# SonarQube (persistent)
mkdir -p /opt/sonarqube/data

docker run -d \
  --name sonarqube \
  -p 9000:9000 \
  -v /opt/sonarqube/data:/opt/sonarqube/data \
  --restart unless-stopped \
  sonarqube:lts-community
EOF


  tags = {
    Name = "jenkins"
    Name = "devops"
    Name = "social-echo"
  }
}

