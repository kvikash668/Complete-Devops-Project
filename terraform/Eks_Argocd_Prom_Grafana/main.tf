########################################
# TERRAFORM SETTINGS
########################################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
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
# VARIABLES
########################################
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "Devops-JenkinsCI-ArgoCD"
}

variable "admin_iam_arn" {
  description = "IAM user/role ARN that gets cluster-admin access"
  type        = string
  default     = "arn:aws:iam::*****:user/KVIKASH668"
}

########################################
# DATA — available AZs in us-east-1
########################################
data "aws_availability_zones" "available" {
  state = "available"
}

########################################
# VPC
########################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags so ALB controller can discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = {
    Project     = "socialecho"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

########################################
# EKS CLUSTER
########################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  enable_irsa                     = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  ########################################
  # ACCESS ENTRY (cluster-admin)
  ########################################
  access_entries = {
    admin = {
      principal_arn = var.admin_iam_arn

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
  # NODE GROUPS
  #
  # FIX: Removed per-node-group `tags` blocks entirely.
  #      The EKS module already propagates the top-level `tags`
  #      to every node group IAM role. Having both caused
  #      "Duplicate tag keys" → IAM role creation failure.
  #
  # Rule: only set tags at the module level below, not inside
  #       each individual node group block.
  ########################################
  eks_managed_node_groups = {

    ##################################################
    # DATABASE → ON_DEMAND (stable for MongoDB)
    ##################################################
    db_ng = {
      instance_types = ["r5.large", "r5a.large", "r4.large"]
      capacity_type  = "ON_DEMAND"

      desired_size = 1
      min_size     = 1
      max_size     = 1

      disk_size = 100

      labels = {
        app  = "database"
        tier = "storage"
      }
    }

    ##################################################
    # BACKEND → SPOT (multiple types avoids Pending)
    ##################################################
    backend_ng = {
      instance_types = ["c5.large", "c5a.large", "m5.large", "m5a.large"]
      capacity_type  = "SPOT"

      desired_size = 2
      min_size     = 2
      max_size     = 6

      disk_size = 40

      labels = {
        app  = "backend"
        tier = "backend"
      }
    }

    ##################################################
    # FRONTEND → SPOT
    ##################################################
    frontend_ng = {
      instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
      capacity_type  = "SPOT"

      desired_size = 2
      min_size     = 1
      max_size     = 4

      disk_size = 30

      labels = {
        app  = "frontend"
        tier = "frontend"
      }
    }

    ##################################################
    # CANARY BACKEND → SPOT
    # min=0 → scales to zero when no canary is active
    # taint → only pods with matching toleration land here
    ##################################################
    backend_canary_ng = {
      instance_types = ["c5.large", "c5a.large", "m5.large"]
      capacity_type  = "SPOT"

      desired_size = 1
      min_size     = 0
      max_size     = 3

      disk_size = 20

      labels = {
        app     = "backend"
        version = "canary"
        tier    = "backend-canary"
      }

      taints = [
        {
          key    = "version"
          value  = "canary"
          effect = "NO_SCHEDULE"
        }
      ]
    }

    ##################################################
    # CANARY FRONTEND → SPOT
    ##################################################
    frontend_canary_ng = {
      instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
      capacity_type  = "SPOT"

      desired_size = 1
      min_size     = 0
      max_size     = 3

      disk_size = 20

      labels = {
        app     = "frontend"
        version = "canary"
        tier    = "frontend-canary"
      }

      taints = [
        {
          key    = "version"
          value  = "canary"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  # FIX: tags defined ONCE here — module propagates to all node group IAM roles
  tags = {
    Project     = "socialecho"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

########################################
# EBS CSI DRIVER — IAM Role (IRSA)
########################################
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name             = "AmazonEKS_EBS_CSI_DriverRole-${var.cluster_name}"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Project   = "socialecho"
    ManagedBy = "terraform"
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  # FIX: removed hardcoded addon_version — it was not supported for this
  # cluster version. AWS will now automatically use the latest compatible version.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = module.ebs_csi_irsa.iam_role_arn

  depends_on = [
    module.eks,
    module.ebs_csi_irsa
  ]
}

########################################
# ALB CONTROLLER — IAM Role (IRSA)
#
# FIX: Role name now includes cluster_name suffix to avoid
#      "EntityAlreadyExists" when a previous run left the role
#      behind in AWS. This makes the name unique per cluster.
#
# ALTERNATIVE if you want to reuse the existing role instead:
#   Run this once before terraform apply:
#   aws iam delete-role --role-name AmazonEKSLoadBalancerControllerRole
########################################
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name                              = "AmazonEKSLoadBalancerControllerRole-${var.cluster_name}"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Project   = "socialecho"
    ManagedBy = "terraform"
  }
}

########################################
# OUTPUTS
########################################
output "cluster_name" {
  description = "EKS Cluster name"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS Region"
  value       = "us-east-1"
}

output "configure_kubectl" {
  description = "Run this to configure kubectl"
  value       = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_controller_role_arn" {
  description = "IAM Role ARN for ALB controller"
  value       = module.alb_controller_irsa.iam_role_arn
}

output "ebs_csi_role_arn" {
  description = "IAM Role ARN for EBS CSI driver"
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "next_steps" {
  description = "Run these commands after terraform apply"
  value       = <<-EOT

  ============================================================
   STEP 1 — Configure kubectl
  ============================================================
  aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}
  kubectl get nodes

  ============================================================
   STEP 2 — Install ALB Controller via Helm
  ============================================================
  helm repo add eks https://aws.github.io/eks-charts
  helm repo update

  VPC_ID=$(aws eks describe-cluster --name ${module.eks.cluster_name} \
    --region us-east-1 \
    --query "cluster.resourcesVpcConfig.vpcId" --output text)

  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=${module.eks.cluster_name} \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${module.alb_controller_irsa.iam_role_arn} \
    --set region=us-east-1 \
    --set vpcId=$VPC_ID

  kubectl rollout status deployment/aws-load-balancer-controller -n kube-system

  ============================================================
   STEP 3 — Deploy Application Manifests (in order)
  ============================================================
  kubectl apply -f namespace.yaml
  kubectl apply -f secrets.yaml
  kubectl apply -f mongo-server.yaml
  kubectl apply -f mongo-express-server.yaml
  kubectl apply -f node-canary.yaml
  kubectl apply -f node-server.yaml
  kubectl apply -f frontend-server.yaml
  kubectl apply -f frontend-canary.yaml

  ============================================================
   STEP 4 — Apply Ingress
  ============================================================
  kubectl apply -f ingress.yaml

  ============================================================
   STEP 5 — Get Your Application URL
  ============================================================
  kubectl get ingress -A
  # Copy the ADDRESS column — that is your ALB DNS name
  # Example: http://k8s-xxxx.us-east-1.elb.amazonaws.com
  # Wait 2-3 minutes after apply for ALB to fully provision

  ============================================================
   TROUBLESHOOTING — If pods stay Pending
  ============================================================
  kubectl get nodes -o wide
  kubectl describe pod <pod-name>         # check Events section
  kubectl get events --sort-by=.lastTimestamp

  EOT
}
