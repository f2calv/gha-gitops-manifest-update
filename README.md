# GitHub Action: GitOps Manifest Update

This GitHub Action updates image tags in GitOps YAML manifests (Kubernetes `Deployment` resources) and pushes the changes back to the source repository. It uses [yq](https://github.com/mikefarah/yq) to manipulate the manifest YAML in-place, setting the container image and `FULLSEMVER` environment variable (from `tag`) on containers named `primary`.

The yq version is sourced from `.devcontainer/devcontainer.json` by default.

## Examples

```yaml
steps:

# Minimal usage example updates manifests but does not push.
- uses: f2calv/gha-gitops-manifest-update@v1
  with:
    image-registry: ghcr.io/f2calv
    image-repository: myapp
    tag-override: 1.2.3
    manifest: myapp
    manifest-path: src/workloads
    tag: 1.2.301-feature-my-feature.12
    git-repo-update: false

# Complete usage example updates manifests and pushes to git.
- uses: f2calv/gha-gitops-manifest-update@v1
  with:
    image-registry: ghcr.io/f2calv
    image-repository: prefix/myapp
    tag-override: 1.2.3
    manifest: myapp
    manifest-path: src/workloads
    tag: 1.2.301-feature-my-feature.12
```

This action is also available as a [reusable workflow](https://github.com/f2calv/gha-workflows/blob/main/.github/workflows/gha-gitops-manifest-update.yml).

## Inputs

| Input | Type | Required | Default | Description |
| ----- | ---- | -------- | ------- | ----------- |
| `image-registry` | string | ✅ | | Container registry e.g. `ghcr.io/gh-user`, `xyz.azurecr.io` or `docker.io` |
| `image-repository` | string | ✅ | | Image repository e.g. `[optional-prefix/]myimage` |
| `tag-override` | string | ✅ | | Image tag override e.g. `latest`, `latest-dev`, `1.2.3` |
| `devcontainer-path` | string | | `.devcontainer/devcontainer.json` | Path to `devcontainer.json` used to resolve yq version |
| `manifest` | string | ✅ | | Manifest name(s) without file extension. Accepts multiple values separated by a space e.g. `deploy1 deploy2 deploy3` |
| `manifest-path` | string | ✅ | | Path to manifest directory e.g. `src/workloads` |
| `tag` | string | ✅ | | Full semantic version e.g. `1.2.301-feature-my-feature.12` |
| `git-repo-update` | boolean | | `true` | If `false` then skips git operations entirely (demo mode) |
| `git-user-name` | string | | `GitHub Actions Bot` | Git commit author name |
| `git-user-email` | string | | `github-actions[bot]@users.noreply.github.com` | Git commit author email |
| `git-branch-name` | string | | `main` | Branch to commit and push to |
