#!/bin/bash
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
echo "LBC Version: $LBC_VERSION"
echo "=============================="

########################################
# FAILURE TRACKING
# Each step runs inside run_step().
# On failure → logged to FAILED_STEPS[].
# Execution always continues to next step.
########################################
FAILED_STEPS=()

run_step() {
  local step_name="$1"
  local step_func="$2"

  echo ""
  echo "=============================="
  echo "▶  ${step_name}"
  echo "=============================="

  # Run in a subshell so set -e and any fatal error is fully contained
  (
    set -e
    $step_func
  )

  if [ $? -ne 0 ]; then
    echo ""
    echo "❌ FAILED: ${step_name}"
    FAILED_STEPS+=("${step_name}")
  else
    echo ""
    echo "✅ DONE: ${step_name}"
  fi
}

########################################
# STEP FUNCTIONS
########################################

step_configure_kubectl() {
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
  kubectl get nodes
}

step_oidc_provider() {
  eksctl utils associate-iam-oidc-provider \
    --region "$REGION" \
    --cluster "$CLUSTER_NAME" \
    --approve
}

step_node_groups() {
  echo ">>> Creating backend-ng..."
  eksctl create nodegroup \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name backend-ng \
    --node-type c5.large \
    --nodes 2 \
    --nodes-min 2 \
    --nodes-max 6 \
    --node-volume-size 40 \
    --node-volume-type gp3 \
    --tags "project=socialecho,env=prod,component=backend" \
    --node-labels "app=backend,tier=backend" \
    2>/dev/null || echo "⚠️  backend-ng already exists, skipping..."

  echo ">>> Creating db-ng..."
  eksctl create nodegroup \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name db-ng \
    --node-type r5.large \
    --nodes 1 \
    --nodes-min 1 \
    --nodes-max 1 \
    --node-volume-size 100 \
    --node-volume-type gp3 \
    --tags "project=socialecho,env=prod,component=database" \
    --node-labels "app=database,tier=storage" \
    2>/dev/null || echo "⚠️  db-ng already exists, skipping..."

  echo ">>> Creating backend-canary-ng..."
  eksctl create nodegroup \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name backend-canary-ng \
    --node-type c5.large \
    --nodes 1 \
    --nodes-min 1 \
    --nodes-max 3 \
    --node-volume-size 20 \
    --node-volume-type gp3 \
    --tags "project=socialecho,env=canary,component=backend-canary" \
    --node-labels "app=backend,version=canary,tier=backend-canary" \
    2>/dev/null || echo "⚠️  backend-canary-ng already exists, skipping..."

  echo ">>> Creating frontend-canary-ng..."
  eksctl create nodegroup \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name frontend-canary-ng \
    --node-type t3.medium \
    --nodes 2 \
    --nodes-min 1 \
    --nodes-max 5 \
    --node-volume-size 30 \
    --node-volume-type gp3 \
    --tags "project=socialecho,env=canary,component=frontend-canary" \
    --node-labels "app=frontend,version=canary,tier=frontend-canary" \
    2>/dev/null || echo "⚠️  frontend-canary-ng already exists, skipping..."

  echo ">>> Creating frontend-ng..."
  eksctl create nodegroup \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --name frontend-ng \
    --node-type t3.medium \
    --nodes 2 \
    --nodes-min 2 \
    --nodes-max 4 \
    --node-volume-size 30 \
    --node-volume-type gp3 \
    --tags "project=socialecho,env=prod,component=frontend" \
    --node-labels "app=frontend,tier=frontend" \
    2>/dev/null || echo "⚠️  frontend-ng already exists, skipping..."

  echo ""
  echo "Node groups ready:"
  kubectl get nodes --show-labels
}

step_ebs_csi_driver() {
  if eksctl get iamserviceaccount \
      --cluster "$CLUSTER_NAME" \
      --namespace kube-system \
      --name ebs-csi-controller-sa 2>/dev/null | grep -q ebs-csi-controller-sa; then
    echo "⚠️  IAM service account ebs-csi-controller-sa already exists, skipping..."
  else
    eksctl create iamserviceaccount \
      --name ebs-csi-controller-sa \
      --namespace kube-system \
      --cluster "$CLUSTER_NAME" \
      --role-name AmazonEKS_EBS_CSI_DriverRole \
      --role-only \
      --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
      --approve
  fi

  eksctl create addon \
    --name aws-ebs-csi-driver \
    --cluster "$CLUSTER_NAME" \
    --service-account-role-arn arn:aws:iam::$ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole \
    --force || \
  eksctl update addon \
    --name aws-ebs-csi-driver \
    --cluster "$CLUSTER_NAME" \
    --force

  echo "⏳ Waiting for EBS CSI driver pods..."
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=aws-ebs-csi-driver \
    -n kube-system \
    --timeout=120s
}

step_deploy_manifests() {
  kubectl apply -f namespace.yaml            || echo "⚠️  namespace.yaml failed or missing"
  kubectl apply -f secrets.yaml              || echo "⚠️  secrets.yaml failed or missing"
  kubectl apply -f mongo-server.yaml         || echo "⚠️  mongo-server.yaml failed or missing"
  kubectl apply -f mongo-express-server.yaml || echo "⚠️  mongo-express-server.yaml failed or missing"
  kubectl apply -f node-canary.yaml          || echo "⚠️  node-canary.yaml failed or missing"
  kubectl apply -f node-server.yaml          || echo "⚠️  node-server.yaml failed or missing"
  kubectl apply -f frontend-server.yaml      || echo "⚠️  frontend-server.yaml failed or missing"
  kubectl apply -f frontend-canary.yaml      || echo "⚠️  frontend-canary.yaml failed or missing"

  echo ""
  echo "⏳ Pods status:"
  kubectl get pods -A
}

step_lbc() {
  # Download IAM policy
  curl -sO https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json

  # Create IAM policy (skip if already exists)
  aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json 2>/dev/null || \
    echo "⚠️  IAM policy already exists, skipping..."

  # Create IAM service account (skip if already exists)
  if eksctl get iamserviceaccount \
      --cluster "$CLUSTER_NAME" \
      --namespace kube-system \
      --name aws-load-balancer-controller 2>/dev/null | grep -q aws-load-balancer-controller; then
    echo "⚠️  IAM service account aws-load-balancer-controller already exists, skipping..."
  else
    eksctl create iamserviceaccount \
      --cluster="$CLUSTER_NAME" \
      --namespace kube-system \
      --name aws-load-balancer-controller \
      --role-name AmazonEKSLoadBalancerControllerRole \
      --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
      --approve
  fi

  # Helm repo
  helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
  helm repo update

  # Get VPC ID
  VPC_ID=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)
  echo "VPC ID: $VPC_ID"

  # Install or upgrade
  if helm status aws-load-balancer-controller -n kube-system &>/dev/null; then
    echo "⚠️  LBC already installed, upgrading..."
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

  echo "⏳ Waiting for LBC to be ready..."
  kubectl wait --for=condition=available \
    --timeout=180s \
    deployment/aws-load-balancer-controller \
    -n kube-system || true

  kubectl get deployment -n kube-system aws-load-balancer-controller

  kubectl apply -f ingress.yaml || echo "⚠️  ingress.yaml failed or missing"

  echo "🌐 Ingress:"
  kubectl get ingress -A
}

step_argocd() {
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  echo "⏳ Waiting for ArgoCD server..."
  kubectl wait --for=condition=available \
    --timeout=300s \
    deployment/argocd-server \
    -n argocd || true

  echo ""
  echo "🔐 ArgoCD Initial Admin Password:"
  kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath="{.data.password}" | base64 -d
  echo ""

  echo "=============================="
  echo "🚀 ArgoCD Access"
  echo "=============================="
  echo "Run: kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "Open: https://localhost:8080  |  Username: admin"
  echo "=============================="
}

step_monitoring() {
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo update

  kubectl create namespace prometheus --dry-run=client -o yaml | kubectl apply -f -

  if [ -f "grafna_values.yaml" ]; then
    echo "📄 Found grafna_values.yaml — using custom values..."
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
      -n prometheus -f grafna_values.yaml
  elif [ -f "values.yaml" ]; then
    echo "📄 Found values.yaml — using custom values..."
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
      -n prometheus -f values.yaml
  else
    echo "📄 No custom values file — using defaults..."
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
      -n prometheus
  fi

  echo "⏳ Waiting for Grafana pod..."
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=grafana \
    -n prometheus \
    --timeout=180s || true

  kubectl get pods -n prometheus
  kubectl get svc  -n prometheus

  [ -f "grafana-ingress.yaml" ]    && kubectl apply -f grafana-ingress.yaml    || true
  [ -f "prometheus-ingress.yaml" ] && kubectl apply -f prometheus-ingress.yaml || true

  echo ""
  echo "=============================="
  echo "📊 Monitoring Access"
  echo "=============================="
  echo ""
  echo "🚀 Grafana (Port Forward):"
  echo "   kubectl port-forward svc/monitoring-grafana -n prometheus 3000:80"
  echo "   Open: http://localhost:3000  |  Login: admin / prom-operator"
  echo ""
  echo "📈 Prometheus (Port Forward):"
  echo "   kubectl port-forward svc/monitoring-kube-prometheus-sta-prometheus -n prometheus 9090:9090"
  echo "   Open: http://localhost:9090"
  echo ""
  echo "⚠️  Expose via LoadBalancer (optional):"
  echo "   kubectl patch svc monitoring-grafana -n prometheus -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"
  echo "   kubectl patch svc monitoring-kube-prometheus-sta-prometheus -n prometheus -p '{\"spec\":{\"type\":\"LoadBalancer\"}}'"
  echo "=============================="
}

########################################
# RUN ALL STEPS
########################################
run_step "1. Configure kubectl"            step_configure_kubectl
run_step "2. Associate OIDC Provider"      step_oidc_provider
run_step "3. Create Node Groups"           step_node_groups
run_step "4. Install EBS CSI Driver"       step_ebs_csi_driver
run_step "5. Deploy Application Manifests" step_deploy_manifests
run_step "6. AWS Load Balancer Controller" step_lbc
run_step "7. Install ArgoCD"               step_argocd
run_step "8. Install Monitoring Stack"     step_monitoring

########################################
# FINAL CLUSTER STATE
########################################
echo ""
echo "=============================="
echo "FINAL CLUSTER STATE"
echo "=============================="
kubectl get nodes      || true
kubectl get pods -A    || true
kubectl get svc  -A    || true
kubectl get ingress -A || true

echo ""
echo "Quick Access Commands:"
echo "  ArgoCD     → kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Grafana    → kubectl port-forward svc/monitoring-grafana -n prometheus 3000:80"
echo "  Prometheus → kubectl port-forward svc/monitoring-kube-prometheus-sta-prometheus -n prometheus 9090:9090"
echo "  Ingress    → kubectl get ingress -A"

########################################
# FAILED STEPS REPORT  (always last)
########################################
echo ""
echo "=============================="
if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
  echo "✅ ALL STEPS COMPLETED SUCCESSFULLY"
else
  echo "⚠️  SETUP FINISHED WITH FAILURES"
  echo "   The following steps failed — fix and re-run:"
  echo "=============================="
  for step in "${FAILED_STEPS[@]}"; do
    echo "   ❌  $step"
  done
  echo ""
  echo "Tip: Every step is idempotent — safe to re-run the full script anytime."
fi
echo "=============================="
