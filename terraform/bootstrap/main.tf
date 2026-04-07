provider "aws" {
  region = "us-east-1"
}

############################
# S3 Bucket for TF State
############################

resource "aws_s3_bucket" "tf_state" {
  bucket = "jenkins-tf-devops-east"

  tags = {
    Name        = "terraform-state"
    Environment = "dev"
  }
}

# Enable versioning (VERY IMPORTANT)
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

############################
# DynamoDB for Locking
############################

resource "aws_dynamodb_table" "tf_lock" {
  name         = "jenkins-tf-devops-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "terraform-lock"
  }
}