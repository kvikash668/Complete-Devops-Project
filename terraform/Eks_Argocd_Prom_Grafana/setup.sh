


#!/bin/bash
set -e

########################################
# CONFIGURATION
########################################
CLUSTER_NAME="Devops-JenkinsCI-ArgoCD"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LBC_VERSION="v2.11.0"

echo "=============================="
echo "Account ID : $ACCOUNT_ID"
echo "Cluster    : $CLUSTER_NAME"
echo "Region     : $REGION"
echo "=============================="

########################################
# 1. Configure kubectl
########################################
echo ""
echo "=============================="
echo "1. Configure kubectl"
echo "=============================="

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
kubectl get nodes

########################################
# 2. Associate OIDC Provider
########################################
echo ""
echo "=============================="
echo "2. Associate OIDC Provider"
echo "=============================="

eksctl utils associate-iam-oidc-provider \
  --region $REGION \
  --cluster $CLUSTER_NAME \
  --approve

########################################
# 3. Create Node Groups
########################################
echo ""
echo "=============================="
echo "3. Creating Node Groups"
echo "=============================="

echo ">>> Creating backend-ng..."
eksctl create nodegroup \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name backend-ng \
  --node-type c5.large \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 6 \
  --node-volume-size 40 \
  --node-volume-type gp3 \
  --tags "project=socialecho,env=prod,component=backend" \
  --node-labels "app=backend,tier=backend" \
  2>/dev/null || echo "⚠️ backend-ng already exists, skipping..."

echo ">>> Creating db-ng..."
eksctl create nodegroup \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name db-ng \
  --node-type r5.large \
  --nodes 1 \
  --nodes-min 1 \
  --nodes-max 1 \
  --node-volume-size 100 \
  --node-volume-type gp3 \
  --tags "project=socialecho,env=prod,component=database" \
  --node-labels "app=database,tier=storage" \
  2>/dev/null || echo "⚠️ db-ng already exists, skipping..."

echo ">>> Creating backend-canary-ng..."
eksctl create nodegroup \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name backend-canary-ng \
  --node-type c5.large \
  --nodes 1 \
  --nodes-min 1 \
  --nodes-max 3 \
  --node-volume-size 20 \
  --node-volume-type gp3 \
  --tags "project=socialecho,env=canary,component=backend-canary" \
  --node-labels "app=backend,version=canary,tier=backend-canary" \
  2>/dev/null || echo "⚠️ backend-canary-ng already exists, skipping..."

echo ">>> Creating frontend-canary-ng..."
eksctl create nodegroup \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name frontend-canary-ng \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 5 \
  --node-volume-size 30 \
  --node-volume-type gp3 \
  --tags "project=socialecho,env=canary,component=frontend-canary" \
  --node-labels "app=frontend,version=canary,tier=frontend-canary" \
  2>/dev/null || echo "⚠️ frontend-canary-ng already exists, skipping..."

echo ">>> Creating frontend-ng..."
eksctl create nodegroup \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --name frontend-ng \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 4 \
  --node-volume-size 30 \
  --node-volume-type gp3 \
  --tags "project=socialecho,env=prod,component=frontend" \
  --node-labels "app=frontend,tier=frontend" \
  2>/dev/null || echo "⚠️ frontend-ng already exists, skipping..."

echo ""
echo "✅ All node groups ready:"
kubectl get nodes --show-labels

########################################
# 4. Install EBS CSI Driver
########################################
echo ""
echo "=============================="
echo "4. Install EBS CSI Driver"
echo "=============================="

if eksctl get iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace kube-system \
  --name ebs-csi-controller-sa 2>/dev/null | grep -q ebs-csi-controller-sa; then
  echo "⚠️ IAM service account already exists, skipping..."
else
  eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster $CLUSTER_NAME \
    --role-name AmazonEKS_EBS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve
fi

eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster $CLUSTER_NAME \
  --service-account-role-arn arn:aws:iam::$ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole \
  --force || \
eksctl update addon \
  --name aws-ebs-csi-driver \
  --cluster $CLUSTER_NAME \
  --force

echo "⏳ Waiting for EBS CSI driver pods..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-ebs-csi-driver \
  -n kube-system \
  --timeout=120s

# #!/bin/bash
# set -e

# ########################################
# # CONFIGURATION
# ########################################
# CLUSTER_NAME="Devops-JenkinsCI-ArgoCD"
# REGION="us-east-1"
# ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# LBC_VERSION="v2.11.0"

# echo "=============================="
# echo "Cluster : $CLUSTER_NAME"
# echo "Region  : $REGION"
# echo "Account : $ACCOUNT_ID"
# echo "=============================="

########################################
# 5. Deploy Application Manifests
########################################
echo ""
echo "=============================="
echo "5. Deploy Application Manifests"
echo "=============================="

kubectl apply -f namespace.yaml || true
kubectl apply -f secrets.yaml || true
kubectl apply -f mongo-server.yaml || true
kubectl apply -f mongo-express-server.yaml || true
kubectl apply -f node-canary.yaml || true
kubectl apply -f node-server.yaml || true
kubectl apply -f frontend-server.yaml || true
kubectl apply -f frontend-canary.yaml || true

kubectl get pods -A

########################################
# 6. AWS LOAD BALANCER CONTROLLER
########################################
echo ""
echo "=============================="
echo "6. Install AWS Load Balancer Controller"
echo "=============================="

########################################
# Download IAM policy
########################################
curl -sO https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json 2>/dev/null || true

########################################
# Create IAM role using eksctl (SAFE)
########################################
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --approve

eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --override-existing-serviceaccounts || true

########################################
# Install Helm repo
########################################
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

########################################
# Get VPC ID
########################################
VPC_ID=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo "VPC ID: $VPC_ID"

########################################
# Install / Upgrade Controller (FIXED)
########################################
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$VPC_ID

########################################
# Wait for controller
########################################
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s || true

kubectl get deployment -n kube-system aws-load-balancer-controller

########################################
# Apply ingress
########################################
kubectl apply -f ingress.yaml || true

kubectl get ingress -A

########################################
# 7. INSTALL ARGOCD
########################################
echo ""
echo "=============================="
echo "7. Install ArgoCD"
echo "=============================="

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl rollout status deployment/argocd-server -n argocd --timeout=300s || true

echo ""
echo "ArgoCD Password:"
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

echo ""

########################################
# 8. PROMETHEUS + GRAFANA
########################################
echo ""
echo "=============================="
echo "8. Install Monitoring Stack"
echo "=============================="

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

kubectl create namespace prometheus --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n prometheus

kubectl get pods -n prometheus
kubectl get svc -n prometheus

########################################
# PATCH SERVICES TO LOADBALANCER
########################################
kubectl patch svc monitoring-kube-prometheus-sta-prometheus \
  -n prometheus \
  -p '{"spec":{"type":"LoadBalancer"}}' || true

kubectl patch svc monitoring-grafana \
  -n prometheus \
  -p '{"spec":{"type":"LoadBalancer"}}' || true

########################################
# FINAL OUTPUT
########################################
echo ""
echo "=============================="
echo "SETUP COMPLETE"
echo "=============================="

kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A