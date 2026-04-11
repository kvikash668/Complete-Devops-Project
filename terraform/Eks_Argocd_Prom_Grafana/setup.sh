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

VPC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

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

kubectl wait --for=condition=available \
  --timeout=300s deployment/argocd-server -n argocd

kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

echo "=============================="
echo "6. Install Prometheus + Grafana"
echo "=============================="

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace prometheus || true

helm install monitoring prometheus-community/kube-prometheus-stack -n prometheus

echo "=============================="
echo "🎉 SETUP COMPLETE"
echo "=============================="

kubectl get nodes
kubectl get pods -A
kubectl get svc -A

echo "execute these after suucess--kubectl apply -f namespace.yaml
kubectl apply -f secrets.yaml
kubectl apply -f mongo-server.yaml
kubectl apply -f mongo-express-server.yaml
kubectl apply -f node-canary.yaml
kubectl apply -f node-server.yaml
kubectl apply -f frontend-server.yaml
kubectl apply -f frontend-canary.yaml
kubectl apply -f ingress.yaml "