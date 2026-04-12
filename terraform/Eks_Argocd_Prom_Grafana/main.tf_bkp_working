########################################
# TERRAFORM SETTINGS
########################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

########################################
# VPC
########################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

########################################
# EKS CLUSTER
########################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = "Devops-JenkinsCI-ArgoCD"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true
  enable_irsa                    = true

  ########################################
  # ACCESS ENTRY (YOU)
  ########################################
  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::906345525506:user/KVIKASH668"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  ########################################
  # NODE GROUPS (SPOT OPTIMIZED)
  ########################################

  eks_managed_node_groups = {

    ########################################
    # DATABASE → ON DEMAND (STABLE)
    ########################################
    db_ng = {
      instance_types = ["r5.large"]
      capacity_type   = "ON_DEMAND"

      desired_size = 1
      min_size     = 1
      max_size     = 1

      disk_size = 100

      labels = {
        app  = "database"
        tier = "storage"
      }
    }

    ########################################
    # BACKEND → SPOT (COST OPTIMIZED)
    ########################################
    backend_ng = {
      instance_types = ["c5.large", "c5a.large"]
      capacity_type   = "SPOT"

      desired_size = 2
      min_size     = 2
      max_size     = 6

      disk_size = 40

      labels = {
        app  = "backend"
        tier = "backend"
      }
    }

    ########################################
    # FRONTEND → SPOT
    ########################################
    frontend_ng = {
      instance_types = ["t3.medium", "t3a.medium"]
      capacity_type   = "SPOT"

      desired_size = 2
      min_size     = 1
      max_size     = 4

      disk_size = 30

      labels = {
        app  = "frontend"
        tier = "frontend"
      }
    }

    ########################################
    # CANARY BACKEND → SPOT (SAFE)
    ########################################
    backend_canary_ng = {
      instance_types = ["c5.large"]
      capacity_type   = "SPOT"

      desired_size = 1
      min_size     = 1
      max_size     = 3

      disk_size = 20

      labels = {
        app     = "backend"
        version = "canary"
      }
    }

    ########################################
    # CANARY FRONTEND → SPOT
    ########################################
    frontend_canary_ng = {
      instance_types = ["t3.medium"]
      capacity_type   = "SPOT"

      desired_size = 1
      min_size     = 1
      max_size     = 3

      disk_size = 20

      labels = {
        app     = "frontend"
        version = "canary"
      }
    }
  }
}

########################################
# OUTPUTS
########################################
output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
}