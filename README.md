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
(SonarCloud, when `sonar-project-key` is set), image scan (Trivy), SBOM (Syft),
signing (Cosign keyless).

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

- `SONAR_TOKEN` — org secret for the code-quality gate.
- A least-privilege promotion identity (GitHub App or fine-grained token) with
  `contents:write` + `pull_requests:write` on `microservice-app-gitops` only,
  exposed to `promote.yml` as `gitops-token`.
- `AWS_CI_ROLE_ARN` / `AWS_REGION` repo/org variables — only when activating the
  cloud legs.
