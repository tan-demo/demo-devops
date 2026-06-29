#!/usr/bin/env sh
set -eu

# Karpenter v1 CRDs published by the AWS provider — pinned so a future release
# bump never silently changes the validation surface for this script.
KARPENTER_VERSION="${KARPENTER_VERSION:-v1.13.0}"
KARPENTER_CRDS_BASE="https://raw.githubusercontent.com/aws/karpenter-provider-aws/${KARPENTER_VERSION}/pkg/apis/crds"

echo ">> installing Karpenter CRDs ${KARPENTER_VERSION} (idempotent, server-side)"
# kubectl client-side dry-run still needs the API resource discoverable, so the
# CRDs must be registered before --dry-run=client/server would resolve the kind.
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
