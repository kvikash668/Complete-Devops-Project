#!/bin/bash
set -e

echo "🚀 Starting AWS Load Balancer Controller IAM Setup..."

# =========================
# VARIABLES
# =========================
CLUSTER_NAME="Devops-JenkinsCI-ArgoCD"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text | cut -d '/' -f5)

ROLE_NAME="AmazonEKSLoadBalancerControllerRole"

echo "🔹 Account ID: $ACCOUNT_ID"
echo "🔹 OIDC ID: $OIDC_ID"

# =========================
# CREATE IAM POLICY
# =========================
echo "📌 Creating IAM Policy..."
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json || true

# Get policy ARN
POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy"

# =========================
# CREATE IAM ROLE
# =========================
echo "📌 Creating IAM Role..."

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://trust-policy.json || true

# Attach policy
echo "📌 Attaching Policy..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN

# =========================
# UPDATE K8S SERVICE ACCOUNT
# =========================
echo "📌 Patching Kubernetes ServiceAccount..."

kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME \
  --overwrite

# =========================
# RESTART CONTROLLER
# =========================
echo "📌 Restarting Controller..."
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

echo "✅ ALB IAM Setup Completed Successfully!"
echo "👉 Check logs: kubectl logs -n kube-system deploy/aws-load-balancer-controller"
echo "👉 Check ingress: kubectl get ingress -A"