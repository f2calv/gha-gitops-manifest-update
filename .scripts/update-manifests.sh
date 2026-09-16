#!/bin/bash
# Rewrites each target manifest's image/tag/chart fields via yq. For ArgoCD
# Application/ApplicationSet manifests, also renders the chart via `helm template`.
#
# Required environment variables: MANIFEST_PATHS, TAG, IMAGE_REGISTRY, IMAGE_REPOSITORY,
# NAMESPACE. GIT_WORKING_DIRECTORY and TAG_OVERRIDE are optional. CHART_REGISTRY,
# CHART_REGISTRY_USERNAME, CHART_REGISTRY_PASSWORD and CHART_REPOSITORY are only required
# when a target manifest is an ArgoCD Application/ApplicationSet.

# Validate required environment variables before enabling strict mode
for var in MANIFEST_PATHS TAG IMAGE_REGISTRY IMAGE_REPOSITORY NAMESPACE; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::Required environment variable $var is not set."
    exit 1
  fi
done

# default the optional vars so `set -u` below doesn't trip on an unset (not just empty) var
: "${GIT_WORKING_DIRECTORY:=}"
: "${TAG_OVERRIDE:=}"
: "${CHART_REGISTRY:=}"
: "${CHART_REGISTRY_USERNAME:=}"
: "${CHART_REGISTRY_PASSWORD:=}"
: "${CHART_REPOSITORY:=}"

set -euo pipefail

# prefix manifest paths with GIT_WORKING_DIRECTORY if set and not '.'
GIT_DIR="${GIT_WORKING_DIRECTORY:-.}"
GIT_DIR="${GIT_DIR%/}"
RESOLVED_PATHS=""
for p in $MANIFEST_PATHS; do
  if [[ "$GIT_DIR" != "." ]]; then
    RESOLVED_PATHS="$RESOLVED_PATHS $GIT_DIR/$p"
  else
    RESOLVED_PATHS="$RESOLVED_PATHS $p"
  fi
done
RESOLVED_PATHS="${RESOLVED_PATHS# }"
echo "MANIFEST_PATHS=$RESOLVED_PATHS"

# force to lowercase (registries/repositories are case-sensitive downstream but by convention lowercase)
IMAGE_REGISTRY="${IMAGE_REGISTRY,,}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY,,}"
CHART_REGISTRY="${CHART_REGISTRY,,}"
CHART_REPOSITORY="${CHART_REPOSITORY,,}"

IMAGE_PREFIX="$IMAGE_REGISTRY/$IMAGE_REPOSITORY"       # e.g. ghcr.io/username/imagename
if [[ -z "${TAG_OVERRIDE:-}" ]]; then
  IMAGE="$IMAGE_PREFIX:$TAG"                           # e.g. ghcr.io/username/imagename:1.2.3
else
  IMAGE="$IMAGE_PREFIX:$TAG_OVERRIDE"                  # e.g. ghcr.io/username/imagename:latest-dev
fi
export IMAGE_REGISTRY IMAGE_REPOSITORY CHART_REGISTRY CHART_REPOSITORY TAG NAMESPACE IMAGE

echo "IMAGE_REGISTRY=$IMAGE_REGISTRY"
echo "IMAGE_REPOSITORY=$IMAGE_REPOSITORY"
echo "TAG=$TAG"
echo "TAG_OVERRIDE=${TAG_OVERRIDE:-}"
echo "IMAGE=$IMAGE"
echo "NAMESPACE=$NAMESPACE"

for MANIFEST_PATH in $RESOLVED_PATHS; do
  echo "-------------------------------------------"
  echo "MANIFEST_PATH=$MANIFEST_PATH"

  if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "::warning title=file $MANIFEST_PATH::File $MANIFEST_PATH does not exist!"
    continue
  fi

  KIND=$(yq '.kind' "$MANIFEST_PATH")
  if [[ "$KIND" == "Application" || "$KIND" == "ApplicationSet" ]]; then
    # we are updating an ArgoCD application/applicationset manifest

    for var in CHART_REGISTRY CHART_REGISTRY_USERNAME CHART_REGISTRY_PASSWORD CHART_REPOSITORY; do
      if [[ -z "${!var:-}" ]]; then
        echo "::error file=$MANIFEST_PATH::CHART_REGISTRY, CHART_REGISTRY_USERNAME, CHART_REGISTRY_PASSWORD and CHART_REPOSITORY are all required to render an ArgoCD $KIND manifest."
        exit 1
      fi
    done

    CHART_NAME=$(basename "$CHART_REPOSITORY")             # e.g. tickprocessor
    MANIFEST_PATH_RENDERED="$MANIFEST_PATH.manifest"        # e.g. src/workloads/tickprocessor.yaml.manifest

    # ApplicationSet stores spec under .spec.template.spec
    if [[ "$KIND" == "ApplicationSet" ]]; then
      SPEC_PREFIX=".spec.template.spec"
    else
      SPEC_PREFIX=".spec"
    fi

    echo "CHART_REGISTRY=$CHART_REGISTRY"
    echo "CHART_REGISTRY_USERNAME=$CHART_REGISTRY_USERNAME"
    echo "CHART_REGISTRY_PASSWORD=***" # Note: value redacted from logs to avoid leaking credentials
    echo "CHART_REPOSITORY=$CHART_REPOSITORY"
    echo "CHART_NAME=$CHART_NAME"
    echo "MANIFEST_PATH_RENDERED=$MANIFEST_PATH_RENDERED"
    echo "-------------------------------------------"

    # ApplicationSet destination namespace is per-generator element — skip overwrite
    if [[ "$KIND" == "Application" ]]; then
      yq -i "${SPEC_PREFIX}.destination.namespace=env(NAMESPACE)" "$MANIFEST_PATH"
    fi
    yq -i "${SPEC_PREFIX}.source.repoURL=env(CHART_REGISTRY)" "$MANIFEST_PATH"
    yq -i "${SPEC_PREFIX}.source.chart=env(CHART_REPOSITORY)" "$MANIFEST_PATH"
    yq -i "${SPEC_PREFIX}.source.targetRevision=env(TAG)" "$MANIFEST_PATH"

    cat "$MANIFEST_PATH"

    yq "${SPEC_PREFIX}.source.helm.valuesObject" "$MANIFEST_PATH" >> temp.values.yaml

    echo ""
    echo ">helm registry login $CHART_REGISTRY --username $CHART_REGISTRY_USERNAME --password-stdin"
    printf '%s' "$CHART_REGISTRY_PASSWORD" | helm registry login "$CHART_REGISTRY" --username "$CHART_REGISTRY_USERNAME" --password-stdin

    echo ""
    echo ">helm pull oci://$CHART_REGISTRY/$CHART_REPOSITORY --version $TAG --untar"
    helm pull "oci://$CHART_REGISTRY/$CHART_REPOSITORY" --version "$TAG" --untar --destination temp-charts

    echo ""
    echo ">helm template --namespace $NAMESPACE $CHART_NAME temp-charts/$CHART_NAME --values temp.values.yaml > $MANIFEST_PATH_RENDERED"
    helm template --namespace "$NAMESPACE" "$CHART_NAME" "temp-charts/$CHART_NAME" --values temp.values.yaml > "$MANIFEST_PATH_RENDERED"

    cat "$MANIFEST_PATH_RENDERED"

    # we are in a loop so do some clean up
    rm -rf temp.values.yaml temp-charts
  else
    # we are updating a regular kubernetes manifest

    # update the image repository
    yq -i '. | select(.kind == "Deployment") as $deployment | select(.kind != "Deployment") as $other | $deployment.spec.template.spec.containers[] |= select(.name == "primary").image=env(IMAGE) | ($deployment, $other)' "$MANIFEST_PATH"

    # update the TAG env variable so we can track a deployment of a new image that has it's full sem ver tag overriden by tagged tag-override, e.g. latest-dev
    yq -i '. | select(.kind == "Deployment") as $deployment | select(.kind != "Deployment") as $other | $deployment.spec.template.spec.containers[] |= select(.name == "primary").env[] |= select(.name == "TAG").value=env(TAG) | ($deployment, $other)' "$MANIFEST_PATH"

    # update all namespaces
    yq -i '.metadata.namespace=env(NAMESPACE)' "$MANIFEST_PATH"

    cat "$MANIFEST_PATH"
  fi
done
