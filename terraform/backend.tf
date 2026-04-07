terraform {
  backend "s3" {
    bucket         = "jenkins-tf-devops-east"
    key            = "jenkins/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "jenkins-tf-devops-lock"
    encrypt        = true
  }
}