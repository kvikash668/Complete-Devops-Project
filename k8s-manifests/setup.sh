#!/bin/bash
set -e

########################################
# REQUIRED VARIABLES (reuse from main script)
########################################
CLUSTER_NAME="Devops-JenkinsCI-ArgoCD"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LBC_VERSION="v2.11.0"

echo "=============================="
echo "Cluster: $CLUSTER_NAME"
echo "Region : $REGION"
echo "=============================="

########################################
# 5. Deploy Application Manifests
########################################
echo ""
echo "=============================="
echo "5. Deploy Application Manifests"
echo "=============================="

kubectl apply -f namespace.yaml
kubectl apply -f secrets.yaml
kubectl apply -f mongo-server.yaml
kubectl apply -f mongo-express-server.yaml
kubectl apply -f node-canary.yaml
kubectl apply -f node-server.yaml
kubectl apply -f frontend-server.yaml
kubectl apply -f frontend-canary.yaml

echo "⏳ Pods status:"
kubectl get pods -A

########################################
# 6. AWS Load Balancer Controller
########################################
echo ""
echo "=============================="
echo "6. Install AWS Load Balancer Controller"
echo "=============================="

curl -sO https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json 2>/dev/null || \
  echo "⚠️ IAM policy already exists"

if eksctl get iamserviceaccount \
    --cluster "$CLUSTER_NAME" \
    --namespace kube-system \
    --name aws-load-balancer-controller 2>/dev/null | grep -q aws-load-balancer-controller; then
  echo "⚠️ IAM service account already exists, skipping..."
else
  eksctl create iamserviceaccount \
    --cluster "$CLUSTER_NAME" \
    --namespace kube-system \
    --name aws-load-balancer-controller \
    --role-name AmazonEKSLoadBalancerControllerRole \
    --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
    --approve
fi

helm repo add eks https://aws.github.io/eks-charts
helm repo update

VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo "VPC ID: $VPC_ID"

if helm status aws-load-balancer-controller -n kube-system &>/dev/null; then
  echo "⚠️ Upgrading LBC..."
  helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region="$REGION" \
    --set vpcId="$VPC_ID"
else
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region="$REGION" \
    --set vpcId="$VPC_ID"
fi

echo "⏳ Waiting for LBC..."
kubectl wait --for=condition=available \
  --timeout=180s \
  deployment/aws-load-balancer-controller \
  -n kube-system || true

kubectl apply -f ingress.yaml

echo "🌐 Ingress:"
kubectl get ingress -A

########################################
# 7. ArgoCD
########################################
echo ""
echo "=============================="
echo "7. Install ArgoCD"
echo "=============================="

kubectl create namespace argocd 2>/dev/null || true

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available \
  --timeout=300s \
  deployment/argocd-server \
  -n argocd || true

echo ""
echo "🔐 ArgoCD Password:"
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d

echo ""
echo "Port forward:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "=============================="
echo "🚀 ArgoCD Access"
echo "=============================="
echo "Run the following command:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "👉 Open: https://localhost:8080"
echo "👉 Username: admin"
echo "👉 Password:"
echo "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
echo "=============================="

########################################
# 8. Prometheus + Grafana
########################################
echo ""
echo "=============================="
echo "8. Monitoring Stack"
echo "=============================="

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace prometheus 2>/dev/null || true

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n prometheus

echo "Pods:"
kubectl get pods -n prometheus

echo "Services:"
kubectl get svc -n prometheus

echo ""
echo "=============================="
echo "📊 MONITORING ACCESS DETAILS"
echo "=============================="

echo ""
echo "🚀 Grafana Access (Recommended - Port Forward)"
echo "---------------------------------------------"
echo "Run this command in terminal:"
echo "kubectl port-forward svc/monitoring-grafana -n prometheus 3000:80"
echo ""
echo "👉 Open: http://localhost:3000"
echo "👉 Login: admin / prom-operator"

echo ""
echo "📈 Prometheus Access (Recommended - Port Forward)"
echo "-----------------------------------------------"
echo "Run this command in another terminal:"
echo "kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n prometheus 9090:9090"
echo ""
echo "👉 Open: http://localhost:9090"

echo ""
echo "=============================="
echo "⚠️ OPTIONAL (NOT RECOMMENDED FOR DEV)"
echo "Expose Grafana as LoadBalancer:"
echo "=============================="
echo "kubectl patch svc monitoring-grafana -n prometheus -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"

echo ""
echo "Then verify:"
echo "kubectl get svc -n prometheus"
echo ""

kubectl apply -f grafana-ingress.yaml
kubectl apply -f prometheus-ingress.yaml
kubectl patch svc monitoring-grafana -n prometheus -p '{"spec":{"type":"LoadBalancer"}}'

kubectl patch svc monitoring-kube-prometheus-prometheus \
  -n prometheus \
  -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc -n prometheus

echo "http://a37455585731049b49f5a3d211ba60e6-276800819.us-east-1.elb.amazonaws.com

Login:

admin / prom-operator
📈 Prometheus

Open:

http://ab803a9942750457f8d4500d40c11ab5-277680419.us-east-1.elb.amazonaws.com:9090"

echo " passowrd for grafana=kubectl get secret -n prometheus monitoring-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d "
########################################
# 9. Summary
########################################
echo ""
echo "=============================="
echo "DONE"
echo "=============================="

kubectl get nodes
kubectl get pods -A
kubectl get svc -A

echo ""
echo "ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Grafana: kubectl get svc -n prometheus"
echo "Ingress: kubectl get ingress -A"
