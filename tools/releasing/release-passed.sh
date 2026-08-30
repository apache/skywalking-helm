#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Everything after the vote passes. Run this only once the vote thread has three
# +1 PMC votes and no -1.
#
#   bash tools/releasing/release-passed.sh 5.0.0
#   bash tools/releasing/release-passed.sh 5.0.0 --dry-run
#
# Every step here is irreversible on shared infrastructure -- an svn commit into
# dist/release and a GitHub release cannot be taken back -- so each one asks
# first and --dry-run shows the plan without doing any of it.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
SVN_DEV_URL="https://dist.apache.org/repos/dist/dev/skywalking"
SVN_RELEASE_URL="https://dist.apache.org/repos/dist/release/skywalking"
PRODUCT_NAME="skywalking-helm"

VERSION="${1:-}"
DRY_RUN=false
case "${2:-}" in
  "")         ;;
  --dry-run)  DRY_RUN=true ;;
  *)          echo "ERROR: unknown argument '${2}' -- did you mean --dry-run?" >&2; exit 1 ;;
esac

log()  { echo "  $*"; }
step() { echo; echo "=== $* ==="; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# Declining ABORTS. These steps are ordered and dependent -- saying no to the
# svn promotion and then continuing would create a GitHub release, and publish
# the chart, for artifacts still sitting in the dev area.
confirm() {
  ${DRY_RUN} && { log "dry run: would $1"; return 1; }
  log "About to $1"
  log "Proceed? [y/N]"
  read -r reply
  [[ "${reply}" == "y" || "${reply}" == "Y" ]] && return 0
  die "declined -- aborting before anything further"
}

# ---------------------------------------------------------------------------

preflight() {
  step "Preflight"
  [[ -n "${VERSION}" ]] || die "usage: $0 <version> [--dry-run]   e.g. $0 5.0.0"
  TAG="v${VERSION}"
  log "publishing ${VERSION}"

  for tool in svn gh git; do
    command -v "${tool}" >/dev/null || die "${tool} is not installed"
  done

  svn ls "${SVN_DEV_URL}/helm/${VERSION}" >/dev/null 2>&1 \
    || die "${SVN_DEV_URL}/helm/${VERSION} does not exist -- was release.sh run?"
}

promote_artifacts() {
  step "Move the artifacts from dev to release"

  if confirm "svn mv ${SVN_DEV_URL}/helm/${VERSION} -> ${SVN_RELEASE_URL}/helm/"; then
    svn mv "${SVN_DEV_URL}/helm/${VERSION}" "${SVN_RELEASE_URL}/helm/" \
      -m "Apache SkyWalking Helm Chart ${VERSION} released"
    log "moved"
  fi
}

remove_previous() {
  step "Remove the previous release"

  # ASF keeps only the current release in dist/release; older ones live on
  # archive.apache.org. This directory is NOT uniformly laid out -- 4.9.0 is a
  # version directory while 4.8.0 sits as six loose files at the top level -- so
  # list what is actually there and let a human choose rather than guessing a
  # pattern and deleting the wrong thing.
  local listing
  listing=$(svn ls "${SVN_RELEASE_URL}/helm/" | grep -v "^${VERSION}/$" || true)

  if [[ -z "${listing}" ]]; then
    log "nothing else present, nothing to remove"
    return
  fi

  log "everything under ${SVN_RELEASE_URL}/helm/ other than ${VERSION}:"
  echo "${listing}" | sed 's/^/    /'
  echo
  log "Remove ALL of the above? [y/N]"
  ${DRY_RUN} && { log "dry run: not removing"; return; }
  read -r reply
  if [[ "${reply}" == "y" || "${reply}" == "Y" ]]; then
    local targets=()
    while IFS= read -r entry; do
      [[ -n "${entry}" ]] && targets+=("${SVN_RELEASE_URL}/helm/${entry%/}")
    done <<< "${listing}"
    svn rm "${targets[@]}" -m "Remove the previous Apache SkyWalking Helm Chart release"
    log "removed"
  else
    log "skipped -- remove them by hand before announcing"
  fi
}

github_release() {
  step "Create the GitHub release"

  # This is the step that publishes the chart. .github/workflows/publish-helm.yaml
  # fires on `release: types: [released]` and pushes the packaged chart to
  # docker.io/apache/skywalking-helm:$VERSION. A draft or pre-release does NOT
  # fire it.
  cd "${PROJECT_DIR}"
  if gh release view "${TAG}" --repo apache/skywalking-helm >/dev/null 2>&1; then
    log "${TAG} already exists, skipping"
    return
  fi

  if confirm "gh release create ${TAG} (this publishes the chart to Docker Hub)"; then
    # --verify-tag: without it gh CREATES a missing tag from the default branch
    # head, which is not necessarily the commit the PMC voted on.
    gh release create "${TAG}" \
      --repo apache/skywalking-helm \
      --verify-tag \
      --title "${VERSION}" \
      --notes "See https://github.com/apache/skywalking-helm/blob/${TAG}/docs/changes/changes.md"
    log "created -- watch the publish-helm workflow"
    gh run list --repo apache/skywalking-helm --workflow=publish-helm.yaml --limit 1 2>/dev/null || true
  fi
}

announce_mail() {
  step "ANNOUNCE mail -- copy from here"

  cat <<EOF

=========================================================================
Subject: [ANNOUNCEMENT] Apache SkyWalking Helm Chart ${VERSION} Released

Content:

Hi the SkyWalking Community

On behalf of the SkyWalking Team, I'm glad to announce that Apache SkyWalking Helm Chart ${VERSION}
is now released.

SkyWalking Helm Chart: deploy Apache SkyWalking -- the OAP backend, the Horizon UI console and a
storage backend -- on Kubernetes with Helm 3.

Install:

  helm install skywalking oci://registry-1.docker.io/apache/skywalking-helm --version ${VERSION} \\
    --set oap.image.tag=<oap-version> \\
    --set ui.image.tag=<horizon-version> \\
    --set oap.storageType=elasticsearch

  # BanyanDB or PostgreSQL also need their subchart enabled and Elasticsearch,
  # which is on by default, turned off:
  #   --set oap.storageType=banyandb --set elasticsearch.enabled=false \\
  #     --set banyandb.enabled=true --set banyandb.image.tag=<banyandb-version>

Vote Thread: <permalink from lists.apache.org>

Download Links: https://skywalking.apache.org/downloads/

Release Notes: https://github.com/apache/skywalking-helm/blob/${TAG}/docs/changes/changes.md

Documentation: https://skywalking.apache.org/docs/skywalking-helm/${VERSION}/readme/

Website: https://skywalking.apache.org/

SkyWalking Resources:
- Issue: https://github.com/apache/skywalking/issues
- Mailing list: dev@skywalking.apache.org

The Apache SkyWalking Team
=========================================================================
EOF
}

remaining() {
  step "What is left, by hand"
  log "1. website PR against apache/skywalking-website:"
  log "     data/releases.yml  -- add ${VERSION}, drop the previous entry"
  log "     data/docs.yml      -- the Kubernetes Helm entry still points at the old"
  log "                           apache/skywalking-kubernetes repo; fix while you are there"
  log "2. send the ANNOUNCE mail above to dev@skywalking.apache.org and announce@apache.org"
  log "     from your @apache.org address, with the vote permalink filled in"
  log "3. close the 5.0.0 milestone here and 'Helm - ${VERSION}' on apache/skywalking"
  log "4. bump chart/skywalking/Chart.yaml to the next development version"
}

# ---------------------------------------------------------------------------

preflight
promote_artifacts
remove_previous
github_release
announce_mail
remaining
