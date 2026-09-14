# MicroTodoSuite — shared CI

Centralized, reusable GitHub Actions workflows for every service repository.
One definition here replaces the copy-pasted per-repo pipelines (roadmap task 4,
spec `003-reusable-cicd-delivery` in `microservice-app-gitops`).

## Reusable workflows

| Workflow | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | Build once → quality/scan/SBOM/sign → output the image digest |
| `.github/workflows/release.yml` | semantic-release: version + changelog |
| `.github/workflows/promote.yml` | Open a digest-bump PR to the GitOps repo (dev/staging/prod) |
| `.github/workflows/iac-checks.yml` | Gate a Terraform repository: rule contracts, `terraform fmt`/`validate`/`test`, tflint, Trivy |

Composite actions: `.github/actions/{setup-stack,sbom,sign}`.

## How a service consumes them (thin caller)

Each service repo keeps a ~10-line caller and **no build/test/deploy logic**:

```yaml
# .github/workflows/ci.yml in a service repo
name: ci
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }
jobs:
  ci:
    uses: MicroTodoSuite/.github/.github/workflows/ci.yml@v1
    with:
      service-name: auth-api
      language: go            # go | node | java | python
      sonar-project-key: MicroTodoSuite_auth-api
      sonar-host-url: ${{ vars.SONAR_HOST_URL }}   # self-hosted SonarQube (both profiles)
    secrets: inherit
```

On merge to `main`, the caller also runs `release.yml` then `promote.yml`
(environment `dev`), which opens a PR to the GitOps repo. Staging and prod are
separate promotion PRs that copy the identical digest; prod requires approval.

## Version pin policy

Consumers MUST pin the reusable workflow by an immutable reference:

- `@v1` — a moving release-tag alias, advanced deliberately via a reviewed
  release in this repo. Use this by default.
- `@<commit-sha>` — full SHA pin for high-assurance consumers.

Never pin `@main`: an unreviewed edit would silently change every consumer.

## Gate configuration

Active by default (no pre-existing artifacts needed): build, code-quality
(self-hosted **SonarQube**, runs when both `sonar-project-key` and
`sonar-host-url` are set), image scan (Trivy), SBOM (Syft), signing (Cosign
keyless).

Both profiles (economical and full) use self-hosted SonarQube (team decision,
overrides plan §17). There is one SonarQube server for the org — CI is
per-commit, not per-environment — so a single `SONAR_HOST_URL` serves every
service. The server is a platform add-on (`infrastructure/sonarqube` in the
GitOps repo); until it exists, leave `sonar-host-url` empty and the gate stays
visibly skipped.

Scaffolded but skipped by default (enable when the artifacts exist):
`run-unit`, `run-integration`, `run-contract`, `run-e2e`, `run-perf`,
`run-dast`. Enabling a gate before its tests/contracts exist fails the run on
purpose — the pipeline never reports a gate it did not actually execute.

## Cloud legs (inactive until roadmap tasks 1–2)

`cloud-enabled` (default `false`) gates OIDC-to-AWS + ECR push. Until task 1
delivers the OIDC role and ECR, images publish to GHCR and the switch to ECR is a
value change (`registry` + `cloud-enabled`). Cluster-side signature verification
(Kyverno) and runtime security are roadmap task 2 and consume the signature this
CI produces.

## Required org configuration (one-time)

- `SONAR_TOKEN` — org secret (token of the self-hosted SonarQube) for the
  code-quality gate; `SONAR_HOST_URL` — org/repo variable pointing at the
  self-hosted SonarQube server.
- A least-privilege promotion identity (GitHub App or fine-grained token) with
  `contents:write` + `pull_requests:write` on `microservice-app-gitops` only,
  exposed to `promote.yml` as `gitops-token`.
- `AWS_CI_ROLE_ARN` / `AWS_REGION` repo/org variables — only when activating the
  cloud legs.

## Infrastructure-as-code checks

`iac-checks.yml` is the gate every Terraform repository calls on its pull
requests. It enforces the rules in `microservice-app-ai-agents/rules/iac/`:

| Job | What it runs |
| --- | --- |
| rule contracts | `scripts/iac/contracts.py repo . --kind modules\|live --repo-root "$GITHUB_WORKSPACE"`, at the same commit as the workflow: it scans `working-directory` and applies the repository root's `docs/iac-exceptions.md` |
| terraform | `terraform fmt -check`, then `terraform test` in each module, `terraform validate` in each sample, and `validate` plus `test` in each live root, with the version from `.terraform-version` |
| tflint | tflint with the AWS ruleset, from `.tflint.hcl` or `scripts/iac/tflint.hcl` |
| trivy | `trivy config`, failing on HIGH and CRITICAL misconfigurations |

```yaml
# .github/workflows/iac-checks.yml in a Terraform repository
name: iac-checks
on:
  pull_request: { branches: [main] }
permissions:
  contents: read
jobs:
  iac:
    uses: MicroTodoSuite/.github/.github/workflows/iac-checks.yml@<commit-sha>
    with:
      kind: modules          # or live
```

tflint and Trivy are downloaded by version and verified by SHA-256; the
contracts' Python dependencies are installed from `scripts/iac/requirements.txt`
with `--require-hashes`. Before an apply, `contracts.py plan <plan.json>
--client lex --project mts --domain <domain>` checks the saved plan's names,
tags, and domain (PC-IAC-003, PC-IAC-004, PC-IAC-022). A finding is waived only
by a row in the repository's `docs/iac-exceptions.md` with a reason and an
expiry. `tests/iac-contracts.sh` proves each contract by mutation.
