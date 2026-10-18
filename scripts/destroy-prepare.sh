#!/usr/bin/env bash
# Runs before the platform is destroyed (by the Destroy apply workflow, with the apply role). Terraform cannot see what runs INSIDE the
# cluster: Argo CD's applications, PersistentVolumeClaims and Services of type LoadBalancer create EBS volumes and load balancers that
# would be left behind and block the VPC. Remove them first. Needs WORKING_DIRECTORY and AWS_REGION (the workflow sets both).
set -uo pipefail

cluster="$(terraform -chdir="$WORKING_DIRECTORY" output -raw cluster_name 2>/dev/null || true)"
if [ -z "$cluster" ] || ! aws eks describe-cluster --name "$cluster" > /dev/null 2>&1; then
  echo "No cluster to empty."
  exit 0
fi

aws eks update-kubeconfig --name "$cluster" --region "$AWS_REGION"

# Best effort from here: whatever cannot be removed is reported by destroy-verify.sh.
if kubectl get ns argocd > /dev/null 2>&1; then
  # ApplicationSets first (they would re-create Applications), then the Applications: their finalizers prune what they deployed.
  kubectl -n argocd delete applicationsets --all --timeout=2m || true
  kubectl -n argocd delete applications --all --wait=true --timeout=10m || true
fi
kubectl delete pvc --all --all-namespaces --timeout=5m || true
kubectl get svc --all-namespaces --field-selector spec.type=LoadBalancer -o json \
  | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' \
  | while read -r ns name; do kubectl -n "$ns" delete svc "$name" --timeout=2m || true; done
exit 0
