#!/usr/bin/env sh
set -eu

echo ">> Karpenter manifests (kubectl client dry-run)"
for f in /workspace/iac/local/karpenter/*.yaml; do
  echo "   $(basename "$f")"
  kubectl apply --dry-run=client -f "$f" >/dev/null
done

cd /workspace/iac/local/cloudflare

echo ">> terraform fmt -check"
terraform fmt -check -recursive

echo ">> terraform init -backend=false"
terraform init -backend=false -input=false >/dev/null

echo ">> terraform validate"
terraform validate

echo ">> Part 5 (Karpenter YAML + Cloudflare TF) is valid."
