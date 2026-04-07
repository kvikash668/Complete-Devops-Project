variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "key_name" {
  default = "jenkins-key"
}

variable "public_key_path" {
  default = "~/.ssh/id_ed25519.pub"
}

variable "allowed_cidr" {
  description = "Allowed CIDR for SSH/HTTP/HTTPS"
  default     = "0.0.0.0/0"
}

variable "iam_user_name" {
  description = "IAM user name"
  default     = "devops-user"
}