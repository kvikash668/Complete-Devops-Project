terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

############################
# Provider
############################
provider "aws" {
  region = "us-east-1"
}

############################
# Variables
############################
variable "cluster_name" {
  default = "test"
}

############################
# VPC (Required for EKS + ALB)
############################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # REQUIRED for ALB Controller
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

############################
# EKS Cluster
############################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.0.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  ############################
  # Node Groups (as per document)
  ############################
  eks_managed_node_groups = {

    backend_ng = {
      instance_types = ["c5.large"]
      min_size       = 2
      max_size       = 6
      desired_size   = 2
      disk_size      = 40

      labels = {
        app  = "backend"
        tier = "backend"
      }
    }

    db_ng = {
      instance_types = ["r5.large"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      disk_size      = 100

      labels = {
        app  = "database"
        tier = "storage"
      }
    }

    backend_canary_ng = {
      instance_types = ["c5.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      disk_size      = 20

      labels = {
        app     = "backend"
        version = "canary"
      }
    }

    frontend_ng = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      disk_size      = 30

      labels = {
        app  = "frontend"
        tier = "frontend"
      }
    }

    frontend_canary_ng = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 5
      desired_size   = 2
      disk_size      = 30

      labels = {
        app     = "frontend"
        version = "canary"
      }
    }
  }

  tags = {
    Environment = "dev"
    Project     = "socialecho"
  }
}

############################
# EBS CSI Driver (Addon)
############################
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"
}

############################
# Outputs
############################
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}