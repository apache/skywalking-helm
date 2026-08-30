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

# Order-independent, so `--dry-run 5.0.0` and `5.0.0 --dry-run` both work, and the version may be
# left out entirely -- it is then read from the staging area and confirmed.
VERSION=""
DRY_RUN=false
for arg in "$@"; do
  case "${arg}" in
    --dry-run)                  DRY_RUN=true ;;
    [0-9]*.[0-9]*.[0-9]*)       VERSION="${arg}" ;;
    *)                          echo "ERROR: unknown argument '${arg}' -- usage: $0 [<version>] [--dry-run]" >&2; exit 1 ;;
  esac
done

log()  { echo "  $*"; }
step() { echo; echo "=== $* ==="; }
die()  { echo "ERROR: $*" >&2; exit 1; }

ask() {
  # `read` exits 1 at EOF, which under set -e would kill the run with no message.
  local reply
  read -r -p "  $1" reply || die "nothing on stdin -- run this script from a terminal"
  printf '%s' "${reply}"
}

# Declining ABORTS. These steps are ordered and dependent -- saying no to the
# svn promotion and then continuing would create a GitHub release, and publish
# the chart, for artifacts still sitting in the dev area.
confirm() {
  ${DRY_RUN} && { log "dry run: would $1"; return 1; }
  log "About to $1"
  log "Proceed? [y/N]"
  # `read` exits 1 at EOF. Without this the run reports "declined" when in truth there was no
  # terminal to ask -- e.g. the script was piped, or run from CI.
  read -r reply || die "nothing on stdin -- run this script from a terminal"
  [[ "${reply}" == "y" || "${reply}" == "Y" ]] && return 0
  die "declined -- aborting before anything further"
}

# ---------------------------------------------------------------------------

resolve_version() {
  step "Version"

  # Unlike release.sh this cannot default from Chart.yaml: by the time the vote passes, master
  # has usually moved on to the next development version. The staging area is the authority on
  # what is actually up for release.
  if [[ -z "${VERSION}" ]]; then
    local staged count
    staged=$(svn ls "${SVN_DEV_URL}/helm" 2>/dev/null | sed 's#/$##' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)
    count=$(printf '%s' "${staged}" | grep -c . || true)

    if [[ "${count}" -eq 1 ]]; then
      VERSION="${staged}"
      log "staged for release: ${VERSION}"
    elif [[ "${count}" -gt 1 ]]; then
      log "more than one version is staged:"
      printf '%s\n' "${staged}" | sed 's/^/    /'
    else
      log "nothing is staged under ${SVN_DEV_URL}/helm"
    fi
  else
    log "version given on the command line: ${VERSION}"
  fi

  local reply
  if [[ -n "${VERSION}" ]]; then
    reply=$(ask "Publish ${VERSION}? [y/N] ")
    [[ "${reply}" == "y" || "${reply}" == "Y" ]] || VERSION=""
  fi
  [[ -n "${VERSION}" ]] || VERSION=$(ask "Enter the version to publish: ")

  [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version '${VERSION}' is not MAJOR.MINOR.PATCH"
  TAG="v${VERSION}"
}

preflight() {
  step "Preflight"
  log "publishing ${VERSION}"

  local missing=""
  for tool in svn gh git; do
    command -v "${tool}" >/dev/null || missing="${missing} ${tool}"
  done
  [[ -z "${missing}" ]] || die "not installed:${missing}"

  # gh is used in github_release(), which runs AFTER the svn promotion -- and that
  # promotion cannot be undone. An unauthenticated gh has to fail here or not at all.
  gh auth status >/dev/null 2>&1 \
    || die "gh is not authenticated -- run 'gh auth login'. The GitHub release is created after the
       svn promotion, which cannot be undone, so this has to be working before anything starts."

  svn ls "${SVN_RELEASE_URL}" >/dev/null 2>&1 \
    || die "cannot read ${SVN_RELEASE_URL} -- check your network and your ASF svn credentials"

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
  read -r reply || die "nothing on stdin -- run this script from a terminal"
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
  log "4. the next-version PR was opened by release.sh; merge it if you have not already"
}

# ---------------------------------------------------------------------------

resolve_version
preflight
promote_artifacts
remove_previous
github_release
announce_mail
remaining
