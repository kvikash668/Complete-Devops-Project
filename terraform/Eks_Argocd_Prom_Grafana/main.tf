########################################
# PROVIDER
########################################

provider "aws" {
  region = "us-east-1"
}

########################################
# DATA
########################################

data "aws_caller_identity" "current" {}

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
  version = "~> 20.0"

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
# ALB CONTROLLER IRSA (FIXED MODULE)
########################################

module "alb_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.4.0"

  role_name = "AmazonEKSLoadBalancerControllerRole"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn

      namespace_service_accounts = [
        "kube-system:aws-load-balancer-controller"
      ]
    }
  }
}

########################################
# KUBERNETES & HELM PROVIDERS
########################################

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.cluster.certificate_authority[0].data
  )
  token = data.aws_eks_cluster_auth.cluster.token
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
# SERVICE ACCOUNT (REQUIRED FOR IRSA)
########################################

resource "kubernetes_service_account" "alb_sa" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_irsa.iam_role_arn
    }
  }
}

########################################
# ALB CONTROLLER INSTALL (HELM)
########################################

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  depends_on = [
    module.eks,
    module.alb_irsa,
    kubernetes_service_account.alb_sa
  ]

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "region"
    value = "us-east-1"
  }

  set {
    name  = "vpcId"
    value = data.aws_vpc.default.id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
}

########################################
# OUTPUTS
########################################

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = data.aws_eks_cluster.cluster.endpoint
}