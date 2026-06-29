# Part 4 — GitLab CI → GitHub Actions migration notes

The legacy `ci/legacy.gitlab-ci.yml` was migrated **by intent, not line-by-line**. Several of
its practices are exactly what we are moving away from; each is called out below with the change
and the reason.

## What changed and why

| Legacy (GitLab) | Migrated (GitHub Actions) | Why |
|---|---|---|
| AWS keys hard-coded in `variables:` | Removed entirely; secrets via GitHub Secrets / OIDC | Credentials never belong in pipeline source. Committing them is an instant fail. |
| `sonar_check` with `allow_failure: true` | **Semgrep** SAST with `--error`; `build` job `needs: sast` | A quality job that can't fail is decoration. Now a finding hard-fails and blocks the build. |
| `unit_test`: `npm test \|\| echo "flaky, continuing"` | **pytest** on the FastAPI app (`test_main.py`); failures hard-fail | Legacy pipeline tested Node against a service that is Python; pytest covers the four HTTP endpoints without swallowing failures. |
| `build_image` pushes `:latest` only | `docker/metadata-action` tags by **git SHA** (`sha-<sha>`), `latest` only on default branch | Immutable, traceable image tags. A floating `latest` is not reproducible. |
| `docker:20.10-dind` (privileged DinD) | `docker/setup-buildx-action` (Buildx) | No privileged Docker-in-Docker. |
| `deploy_prod`: manual `kubectl set image ...:latest` with `KUBECONFIG_CONTENT` | **Removed from CI**; deploy is GitOps via ArgoCD | CI builds + pushes an immutable image; ArgoCD syncs it. No cluster credentials in CI; no imperative drift. |
| `only: master` | `on: push (main)` + `pull_request` | PRs get scanned/built; pushes to main publish. |

**Improvements added (bonus):** Trivy scan gating on HIGH/CRITICAL (`ignore-unfixed`), and cosign
**keyless** signing of the pushed digest (OIDC, no private key to manage).

## SAST scope

Semgrep scans the **shipped** code (`app/`, `charts/`, `iac/`, `argocd/`). Exercise/harness
artifacts are excluded via `.semgrepignore` (`ci/` legacy reference with its example key,
`troubleshoot/` Part 3 exercise, `toolbox/` local-dev image that runs as root by design). The gate
still runs 502 rules and fails on real issues in shipped code.

## Migrating GitLab CI/CD variables & secrets to GitHub

GitLab keeps these under **Settings → CI/CD → Variables** (masked / protected). In GitHub they split
by sensitivity:

- **Secrets** (Settings → Secrets and variables → Actions → *Secrets*) — masked, write-only:
  - `CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD` → **not needed** (GHCR auth uses the built-in
    `GITHUB_TOKEN` with `packages: write`; no registry credentials to store)
  - `SONAR_TOKEN` → not needed (Semgrep OSS rules need no token; use `SEMGREP_APP_TOKEN` only for Semgrep Cloud)
  - `KUBECONFIG_CONTENT` → **eliminated** (ArgoCD owns deployment)
- **Variables** (same screen → *Variables*) — non-sensitive config (region, image name) as plain `vars`.
- **AWS auth**: do **not** port the static `AWS_ACCESS_KEY_ID/SECRET`. Use **OIDC**
  (`aws-actions/configure-aws-credentials` with `role-to-assume`) so the workflow assumes a role with
  short-lived credentials — no long-lived keys stored anywhere.
- **Protection**: use GitHub *Environments* with required reviewers for any prod-affecting job, mirroring
  GitLab `protected` variables and `when: manual`.
