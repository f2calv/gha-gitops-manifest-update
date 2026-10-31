#!/bin/bash
# Commits and pushes changes to the updated manifests only. Anything else in the working directory,
# such as tool caches or unrelated edits, is never staged.
#
# Required environment variables: GIT_WORKING_DIRECTORY, GIT_USER_NAME, GIT_USER_EMAIL,
# GIT_BRANCH_NAME, NAMESPACE, IMAGE_REPOSITORY, TAG, MANIFEST_PATHS (space-separated, relative to
# GIT_WORKING_DIRECTORY)

for var in GIT_WORKING_DIRECTORY GIT_USER_NAME GIT_USER_EMAIL GIT_BRANCH_NAME NAMESPACE IMAGE_REPOSITORY TAG MANIFEST_PATHS; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::Required environment variable $var is not set."
    exit 1
  fi
done

set -euo pipefail

cd "$GIT_WORKING_DIRECTORY"
read -r -a PATHS <<< "$MANIFEST_PATHS"
git checkout "$GIT_BRANCH_NAME"
#Missing paths were already reported as warnings by update-manifests.sh.
for p in "${PATHS[@]}"; do
  [[ ! -e "$p" ]] || git add -- "$p"
done
if ! git diff --cached --quiet; then
  git config --global user.name "$GIT_USER_NAME"
  git config --global user.email "$GIT_USER_EMAIL"
  git commit -m "[$NAMESPACE] bump '$IMAGE_REPOSITORY' to '$TAG'"
  git push -v --progress
else
  echo "::warning title=git push::No changes to push."
fi
