#!/bin/bash
set -e

########################################
# CONFIGURATION
########################################
CLUSTER_NAME="Devops-JenkinsCI-ArgoCD"
REGION="us-east-1"
INGRESS_FILE="ingress.yaml"

echo "=============================="
echo "ALB Controller Fix Script"
echo "Cluster : $CLUSTER_NAME"
echo "Region  : $REGION"
echo "=============================="

########################################
# STEP 1 — Get VPC ID and Role ARN
########################################
echo ""
echo "[ 1/7 ] Fetching VPC ID and IAM Role..."

VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

ALB_ROLE=$(aws iam get-role \
  --role-name "AmazonEKSLoadBalancerControllerRole-${CLUSTER_NAME}" \
  --query "Role.Arn" \
  --output text)

echo "  VPC  : $VPC_ID"
echo "  Role : $ALB_ROLE"

if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  echo "❌ Could not fetch VPC ID. Check cluster name and region."
  exit 1
fi

if [ -z "$ALB_ROLE" ] || [ "$ALB_ROLE" == "None" ]; then
  echo "❌ Could not fetch IAM Role. Check role name."
  exit 1
fi

########################################
# STEP 2 — Refresh kubeconfig
########################################
echo ""
echo "[ 2/7 ] Refreshing kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
kubectl get nodes --no-headers | wc -l | xargs echo "  Nodes available:"

########################################
# STEP 3 — Delete stale webhooks
########################################
echo ""
echo "[ 3/7 ] Removing stale webhooks..."

# Find and delete any ALB-related mutating webhooks
for wh in $(kubectl get mutatingwebhookconfigurations \
  --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep -i load-balancer || true); do
  echo "  Deleting mutating webhook: $wh"
  kubectl delete mutatingwebhookconfiguration "$wh" 2>/dev/null || true
done

# Find and delete any ALB-related validating webhooks
for wh in $(kubectl get validatingwebhookconfigurations \
  --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep -i load-balancer || true); do
  echo "  Deleting validating webhook: $wh"
  kubectl delete validatingwebhookconfiguration "$wh" 2>/dev/null || true
done

echo "  ✅ Webhooks cleared"

########################################
# STEP 4 — Uninstall existing ALB controller
########################################
echo ""
echo "[ 4/7 ] Uninstalling existing ALB controller..."

if helm status aws-load-balancer-controller -n kube-system &>/dev/null; then
  helm uninstall aws-load-balancer-controller -n kube-system
  echo "  ✅ Uninstalled"
else
  echo "  ⚠️  Not installed via helm, skipping..."
fi

# Wait for old pods to terminate
echo "  Waiting for old pods to terminate..."
kubectl wait --for=delete pod \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  -n kube-system \
  --timeout=60s 2>/dev/null || true

########################################
# STEP 5 — Fresh install ALB controller
########################################
echo ""
echo "[ 5/7 ] Installing ALB controller..."

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ALB_ROLE" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID"

echo ""
echo "  Waiting for ALB controller pods to be ready..."
kubectl rollout status deployment/aws-load-balancer-controller \
  -n kube-system \
  --timeout=120s

echo ""
kubectl get pods -n kube-system | grep aws-load-balancer
echo "  ✅ ALB controller running"

########################################
# STEP 6 — Delete and re-apply ingress
########################################
echo ""
echo "[ 6/7 ] Re-applying ingress..."

# Delete existing ingress if present
kubectl delete ingress socialecho-ingress -n socialecho 2>/dev/null || true
sleep 3

# Write fresh ingress.yaml inline so this script is self-contained
cat > /tmp/socialecho-ingress.yaml << 'INGRESSEOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: socialecho-ingress
  namespace: socialecho
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
    alb.ingress.kubernetes.io/unhealthy-threshold-count: "2"
    alb.ingress.kubernetes.io/success-codes: "200,301,302,404"
    alb.ingress.kubernetes.io/actions.frontend: >-
      {"type":"forward","forwardConfig":{"targetGroups":[
        {"serviceName":"frontend","servicePort":"80","weight":90},
        {"serviceName":"frontend-canary","servicePort":"80","weight":10}
      ]}}
    alb.ingress.kubernetes.io/actions.backend: >-
      {"type":"forward","forwardConfig":{"targetGroups":[
        {"serviceName":"backend","servicePort":"4000","weight":90},
        {"serviceName":"backend-canary","servicePort":"4000","weight":10}
      ]}}
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend
                port:
                  name: use-annotation
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  name: use-annotation
INGRESSEOF

kubectl apply -f /tmp/socialecho-ingress.yaml
echo "  ✅ Ingress applied"

########################################
# STEP 7 — Wait for ALB address
########################################
echo ""
echo "[ 7/7 ] Waiting for ALB address (up to 3 mins)..."

ALB_ADDRESS=""
for i in $(seq 1 36); do
  ALB_ADDRESS=$(kubectl get ingress socialecho-ingress -n socialecho \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

  if [ -n "$ALB_ADDRESS" ]; then
    break
  fi

  echo "  ⏳ Waiting... ($((i * 5))s)"
  sleep 5
done

########################################
# FINAL SUMMARY
########################################
echo ""
echo "=============================="
if [ -n "$ALB_ADDRESS" ]; then
  echo "✅ SUCCESS — App is LIVE"
  echo "=============================="
  echo ""
  echo "  🌐 SocialEcho App  : http://$ALB_ADDRESS"
  echo "  🔌 Backend API     : http://$ALB_ADDRESS/api"
  echo ""
  echo "  📊 Grafana         : $(kubectl get ingress grafana-ingress -n prometheus \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null \
    | xargs -I{} echo 'http://{}')  (admin / prom-operator)"
  echo "  📈 Prometheus      : $(kubectl get ingress prometheus-ingress -n prometheus \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null \
    | xargs -I{} echo 'http://{}')"
  echo ""
  echo "  Quick test:"
  echo "  curl -I http://$ALB_ADDRESS/"
else
  echo "⚠️  ALB address not ready yet — check in 1-2 mins:"
  echo "  kubectl get ingress -n socialecho"
fi
echo "=============================="