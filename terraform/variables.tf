variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "allowed_cidr" {
  description = "CIDR allowed to access SSH/Jenkins/Sonar"
  type        = string
}

variable "key_name" {
  description = "Name for the AWS key pair"
  type        = string
  default     = "jenkins-key"
}

variable "public_key_path" {
  description = "Absolute path to your public SSH key file"
  type        = string
}


variable "iam_user_name" {
  description = "IAM user name to create with EC2 management permissions"
  type        = string
  default     = "jenkins-admin"
}
