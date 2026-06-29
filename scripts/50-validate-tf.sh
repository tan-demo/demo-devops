#!/usr/bin/env sh
set -eu

# Karpenter v1 CRDs (pinned for a stable validation surface).
KARPENTER_VERSION="${KARPENTER_VERSION:-v1.13.0}"
KARPENTER_CRDS_BASE="https://raw.githubusercontent.com/aws/karpenter-provider-aws/${KARPENTER_VERSION}/pkg/apis/crds"

echo ">> installing Karpenter CRDs ${KARPENTER_VERSION} (idempotent, server-side)"
# CRDs must be registered before dry-run can resolve the custom kinds.
for crd in karpenter.k8s.aws_ec2nodeclasses.yaml karpenter.sh_nodepools.yaml karpenter.sh_nodeclaims.yaml; do
  kubectl apply --server-side --force-conflicts -f "${KARPENTER_CRDS_BASE}/${crd}" >/dev/null
done

echo ">> Karpenter manifests (kubectl server-side dry-run)"
for f in /workspace/iac/local/karpenter/*.yaml; do
  echo "   $(basename "$f")"
  kubectl apply --dry-run=server -f "$f" >/dev/null
done

cd /workspace/iac/local/cloudflare

echo ">> terraform fmt -check"
terraform fmt -check -recursive

echo ">> terraform init -backend=false"
terraform init -backend=false -input=false >/dev/null

echo ">> terraform validate"
terraform validate

echo ">> Part 5 (Karpenter YAML + Cloudflare TF) is valid."
