terraform {
  backend "s3" {
    bucket         = "jenkins-tf-devops"
    key            = "jenkins/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "jenkins-tf-devops_db"
    encrypt        = true
  }
}
