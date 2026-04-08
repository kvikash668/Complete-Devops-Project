#!/bin/bash

set -e

CLUSTER_NAME="test"
REGION="us-east-1"

echo "=============================="
echo "1. Configure kubectl"
echo "=============================="
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

kubectl get nodes

echo "=============================="
echo "2. Associate OIDC Provider"
echo "=============================="
eksctl utils associate-iam-oidc-provider \
  --region $REGION \
  --cluster $CLUSTER_NAME \
  --approve

echo "=============================="
echo "3. Install EBS CSI Driver"
echo "=============================="
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster $CLUSTER_NAME \
  --force

echo "=============================="
echo "4. Install AWS Load Balancer Controller"
echo "=============================="

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json || true

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update

VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$VPC_ID

echo "=============================="
echo "5. Install ArgoCD"
echo "=============================="

kubectl create namespace argocd || true

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argocd/stable/manifests/install.yaml

echo "Waiting for ArgoCD pods..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "=============================="
echo "6. Expose ArgoCD via LoadBalancer"
echo "=============================="

kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

echo "Waiting for LoadBalancer..."
sleep 30

ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "=============================="
echo "🎉 ArgoCD is Ready!"
echo "=============================="

echo "URL: http://$ARGOCD_URL"

echo "Fetching initial password..."

PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "Username: admin"
echo "Password: $PASSWORD"