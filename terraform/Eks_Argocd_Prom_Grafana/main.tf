########################################
# TERRAFORM SETTINGS
########################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

########################################
# PROVIDER
########################################

provider "aws" {
  region = "us-east-1"
}

########################################
# USE DEFAULT VPC
########################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

########################################
# EKS CLUSTER
########################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = "test"
  cluster_version = "1.29"

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  enable_irsa = true

  ########################################
  # NODE GROUPS (UNCHANGED)
  ########################################

  eks_managed_node_groups = {

    backend_ng = {
      instance_types = ["c5.large"]
      desired_size   = 2
      min_size       = 2
      max_size       = 6
      disk_size      = 40

      labels = {
        app  = "backend"
        tier = "backend"
      }
    }

    db_ng = {
      instance_types = ["r5.large"]
      desired_size   = 1
      min_size       = 1
      max_size       = 1
      disk_size      = 100

      labels = {
        app  = "database"
        tier = "storage"
      }
    }

    backend_canary_ng = {
      instance_types = ["c5.large"]
      desired_size   = 1
      min_size       = 1
      max_size       = 3
      disk_size      = 20

      labels = {
        app     = "backend"
        version = "canary"
        tier    = "backend-canary"
      }
    }

    frontend_canary_ng = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 1
      max_size       = 5
      disk_size      = 30

      labels = {
        app     = "frontend"
        version = "canary"
        tier    = "frontend-canary"
      }
    }

    frontend_ng = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 2
      max_size       = 4
      disk_size      = 30

      labels = {
        app  = "frontend"
        tier = "frontend"
      }
    }
  }
}

########################################
# EBS CSI DRIVER
########################################

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"
}

########################################
# CONNECT HELM TO EKS
########################################

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(
      data.aws_eks_cluster.cluster.certificate_authority[0].data
    )
    token = data.aws_eks_cluster_auth.cluster.token
  }
}

########################################
# OUTPUTS
########################################

output "cluster_name" {
  value = module.eks.cluster_name
}