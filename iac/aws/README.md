# Extension (beyond the take-home) — AWS platform IaC (Terragrunt, validate-only)

> **Scope note.** The graded **Part 5** deliverables are the focused artifacts: the Karpenter
> manifests in [`../local/karpenter`](../local/karpenter) and the Cloudflare Terraform in
> [`../local/cloudflare`](../local/cloudflare), both checked by `scripts/50-validate-tf.sh`. This
> `iac/aws` tree is an **optional extension** that shows the full platform those pieces would run on —
> it is not required by the assignment, kept here to demonstrate depth.

Provisions the **infra layer** the rest of the design assumes: a VPC, an EKS cluster (with cluster
admin access entries + a secrets-encryption KMS key), the **Karpenter** controller IAM, and the
**ArgoCD** Helm release. Cloudflare DNS + edge cache lives here too so one `root.hcl` drives the
whole environment.

This is **validate-only** (no cloud account, nothing applied). Every unit validates offline through
Terragrunt `mock_outputs`.

## Layout

```
iac/aws/
├── modules/                  # reusable wrappers — full variable surface, sane defaults
│   ├── vpc/  eks/  karpenter/  argocd/  cloudflare/
└── envs/
    ├── dev/                  # wired + validated
    │   ├── root.hcl          # per-env locals (region, cidr, cluster, tags…) + backend + provider
    │   ├── vpc/  eks/  karpenter/  argocd/  cloudflare/   # one terragrunt.hcl per unit
    ├── staging/              # placeholder (README only)
    └── prod/                 # placeholder (README only)
```

Each `modules/<x>` exposes every meaningful knob as a variable with a default, so a unit only has to
pass what actually changes per environment; everything else falls back to the module default. Each
`envs/<env>/root.hcl` is the single source of per-env values and generates the S3 + DynamoDB backend
and AWS provider; units `include` it (`expose = true`) and read `include.root.locals.*`. The units
wire the dependency graph (`vpc → eks → {karpenter, argocd}`).

## Versions (verified against the registry)

| Component | Source | Version |
|-----------|--------|---------|
| VPC | `terraform-aws-modules/vpc/aws` | `6.6.1` |
| EKS | `terraform-aws-modules/eks/aws` | `21.24.0` |
| Karpenter | `terraform-aws-modules/eks/aws//modules/karpenter` | `21.24.0` |
| ArgoCD | `argo-cd` Helm chart | `10.0.0` |
| Cloudflare provider | `cloudflare/cloudflare` | `~> 5.0` |
| Terragrunt | — | `v1.0.8` |

## How it fits the layering

`controller / IAM = infra (these units)` → `NodePool / EC2NodeClass = GitOps (../karpenter)`.
ArgoCD is bootstrapped onto the cluster here, then manages workloads from Git — the same app-of-apps
used locally on k3d.

## Validate

This extension is validated on its own (the graded `scripts/50-validate-tf.sh` only covers the
Part 5 artifacts in `../karpenter` and `../cloudflare`). From inside the toolbox:

```bash
cd /workspace/iac/aws/envs/dev
TG_DISABLE_BACKEND=true terragrunt run --all validate --non-interactive
```

`TG_DISABLE_BACKEND=true` skips the S3 backend so unapplied dependencies resolve through
`mock_outputs` — fully offline. Drop that flag (and provide AWS credentials) to plan/apply for real.

## Secrets

`cloudflare_api_token` is never stored in `root.hcl`; inject it as `TF_VAR_cloudflare_api_token` at
apply time. `validate` does not need it.
