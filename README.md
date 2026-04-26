# GitHub Action: GitOps Manifest Update

This GitHub Action iterates over YAML manifests (Kubernetes `Deployment`, ArgoCD `Application`, or ArgoCD `ApplicationSet`) and updates their image/tag. For ArgoCD `Application` and `ApplicationSet` manifests it also pulls and renders Helm charts. It uses [yq](https://github.com/mikefarah/yq) to manipulate manifest YAML in-place and [Helm](https://helm.sh/) for chart operations. Tool versions are sourced from `.devcontainer/devcontainer.json` by default.

## Examples

```yaml
steps:

# Deployment-only: updates image tag and pushes to git.
- uses: f2calv/gha-gitops-manifest-update@v2
  with:
    tag: 1.2.3
    image-registry: ghcr.io/f2calv
    image-repository: myapp
    manifest-paths: src/workloads/myapp.yaml
    namespace: prd

# Deployment with tag-override: image uses latest-dev, TAG env var tracks full semver.
- uses: f2calv/gha-gitops-manifest-update@v2
  with:
    tag: 1.2.301-feature-my-feature.12
    tag-override: latest-dev
    image-registry: ghcr.io/f2calv
    image-repository: myapp
    manifest-paths: src/workloads/myapp.yaml
    namespace: dev
    git-repo-update: false

# ArgoCD Application: updates targetRevision, pulls and renders Helm chart.
- uses: f2calv/gha-gitops-manifest-update@v2
  with:
    tag: 1.2.3
    image-registry: ghcr.io/f2calv
    image-repository: myapp
    chart-registry: ghcr.io/f2calv
    chart-registry-username: f2calv
    chart-registry-password: ${{ secrets.GITHUB_TOKEN }}
    chart-repository: charts/myapp
    manifest-paths: src/workloads/myapp.yaml
    namespace: prd
    git-working-directory: gitops/

# ArgoCD ApplicationSet: updates targetRevision under .spec.template.spec.
# Namespace is not overwritten because each generator element defines its own.
- uses: f2calv/gha-gitops-manifest-update@v2
  with:
    tag: 1.2.3
    image-registry: ghcr.io/f2calv
    image-repository: myapp
    chart-registry: ghcr.io/f2calv
    chart-registry-username: f2calv
    chart-registry-password: ${{ secrets.GITHUB_TOKEN }}
    chart-repository: charts/myapp
    manifest-paths: src/workloads/myapp.yaml
    namespace: prd
    git-working-directory: gitops/
```

This action is also available as a [reusable workflow](https://github.com/f2calv/gha-workflows/blob/main/.github/workflows/gha-gitops-manifest-update.yml).

## Inputs

### Image

| Input | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `tag` | string | ✅ | | Semantic version e.g. `1.2.3`, `1.2.3-branch-name.12` |
| `tag-override` | string | | | Optional image tag override e.g. `latest`, `latest-dev`. When set the image uses this tag; when empty the image uses `tag` |
| `image-registry` | string | ✅ | | Container registry e.g. `ghcr.io/gh-user`, `xyz.azurecr.io` or `docker.io` |
| `image-repository` | string | ✅ | | Image repository e.g. `[optional-prefix/]myimage` |

### Chart

| Input | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `chart-registry` | string | | | Helm chart OCI registry e.g. `ghcr.io/gh-user` |
| `chart-registry-username` | string | | | Registry username for `helm registry login` |
| `chart-registry-password` | string | | | Registry password for `helm registry login` |
| `chart-repository` | string | | | Chart repository path e.g. `[optional-prefix/]charts/myname` |

### Manifest

| Input | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `manifest-paths` | string | ✅ | | Space-separated YAML manifest paths e.g. `src/workloads/manifest1.yaml src/workloads/manifest2.yaml` |
| `namespace` | string | ✅ | | Destination Kubernetes namespace e.g. `dev`, `prd` |

### Tooling

| Input | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `devcontainer-path` | string | | `.devcontainer/devcontainer.json` | Path to `devcontainer.json` used to resolve yq and Helm versions |

### Git

| Input | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `git-repo-update` | boolean | | `true` | If `false` then skips git operations entirely (demo mode) |
| `git-user-name` | string | | `GitHub Actions Bot` | Git commit author name |
| `git-user-email` | string | | `github-actions[bot]@users.noreply.github.com` | Git commit author email |
| `git-branch-name` | string | | `main` | Branch to commit and push to |
| `git-working-directory` | string | | `.` | Working directory for git operations e.g. `gitops/` |

## Manifest Kind Handling

The action auto-detects the `kind` of each manifest file and applies the appropriate update strategy:

| Kind | Fields updated | Namespace handling |
| --- | --- | --- |
| `Deployment` | `.spec.template.spec.containers[].image`, `.metadata.namespace` | Overwritten with `namespace` input |
| `Application` | `.spec.source.repoURL`, `.spec.source.chart`, `.spec.source.targetRevision`, `.spec.destination.namespace` | Overwritten with `namespace` input |
| `ApplicationSet` | `.spec.template.spec.source.repoURL`, `.spec.template.spec.source.chart`, `.spec.template.spec.source.targetRevision` | **Not overwritten** — each generator element defines its own destination namespace |
