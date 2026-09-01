#!/bin/bash
# Commits and pushes any changes made to the GitOps working directory, if there are any.
#
# Required environment variables: GIT_WORKING_DIRECTORY, GIT_USER_NAME, GIT_USER_EMAIL,
# GIT_BRANCH_NAME, NAMESPACE, IMAGE_REPOSITORY, TAG

for var in GIT_WORKING_DIRECTORY GIT_USER_NAME GIT_USER_EMAIL GIT_BRANCH_NAME NAMESPACE IMAGE_REPOSITORY TAG; do
  if [[ -z "${!var:-}" ]]; then
    echo "::error::Required environment variable $var is not set."
    exit 1
  fi
done

set -euo pipefail

cd "$GIT_WORKING_DIRECTORY"
if [[ -n "$(git status --porcelain)" ]]; then
  git config --global user.name "$GIT_USER_NAME"
  git config --global user.email "$GIT_USER_EMAIL"
  git checkout "$GIT_BRANCH_NAME"
  git add --all
  git commit -m "[$NAMESPACE] bump '$IMAGE_REPOSITORY' to '$TAG'"
  git push -v --progress
else
  echo "::warning title=git push::No changes to push."
fi
