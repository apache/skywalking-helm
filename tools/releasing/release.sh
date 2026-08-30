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

# Everything up to and including the call for vote.
#
#   bash tools/releasing/release.sh              # build, verify, upload, print the vote mail
#   bash tools/releasing/release.sh --dry-run    # do everything except svn commit
#
# The version comes from chart/skywalking/Chart.yaml -- the same place the Makefile reads it, so
# there is one source of truth and no way to sign 5.0.0 while uploading it as 5.0.1.
#
# After this: send the printed mail, wait 72h, then tools/releasing/release-passed.sh.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
CHART_FILE="${PROJECT_DIR}/chart/skywalking/Chart.yaml"
SVN_DEV_URL="https://dist.apache.org/repos/dist/dev/skywalking"
PRODUCT_NAME="skywalking-helm"

DRY_RUN=false
case "${1:-}" in
  "")         ;;
  --dry-run)  DRY_RUN=true ;;
  *)          echo "ERROR: unknown argument '${1}' -- did you mean --dry-run?" >&2; exit 1 ;;
esac

log()  { echo "  $*"; }
step() { echo; echo "=== $* ==="; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------

preflight() {
  step "Preflight"

  # make clean is a prerequisite of make release, and its recipe is a single
  # backslash-continued rm whose later -rf tokens sit mid-argument-list. GNU rm
  # permutes those; BSD rm does not. So on macOS it exits 2 and leaves
  # chart/skywalking/charts/ behind, and the release is built from a dirty tree.
  [[ "$(uname -s)" == "Linux" ]] || die "build the release on Linux -- 'make clean' does not work on macOS (BSD rm), see docs/contributing/release.md"

  # Report every missing tool at once. Dying on the first means one failed run
  # per package, and this check exists precisely to spend zero of them.
  local missing=""
  for tool in helm gpg shasum svn git make tar awk; do
    command -v "${tool}" >/dev/null || missing="${missing} ${tool}"
  done
  [[ -z "${missing}" ]] || die "not installed:${missing}"

  # Present is not the same as usable, and each of these fails LATE otherwise:
  # a missing signing key after the whole build, bad svn credentials after the
  # tag is already pushed.
  # 3.8, not 3: the chart is published only as an OCI artifact, and `helm push` to an
  # oci:// registry landed in 3.8. Helm 4 is fine -- Chart.yaml is apiVersion v2, which
  # both majors read -- so this bounds from below only, and does not cap the major.
  local helm_ver helm_major helm_minor
  helm_ver=$(helm version --short 2>/dev/null | sed 's/^v//; s/[-+].*//')
  helm_major=${helm_ver%%.*}
  helm_minor=$(printf '%s' "${helm_ver}" | cut -d. -f2)
  [[ -n "${helm_major}" ]] || die "could not parse 'helm version --short'"
  if (( helm_major < 3 || (helm_major == 3 && helm_minor < 8) )); then
    die "helm 3.8 or newer is required, found ${helm_ver}"
  fi

  gpg --list-secret-keys >/dev/null 2>&1 && [[ -n "$(gpg --list-secret-keys --with-colons 2>/dev/null | grep '^sec')" ]] \
    || die "gpg has no secret key -- 'make release' signs the artifacts and would fail after the build"

  svn ls "${SVN_DEV_URL}" >/dev/null 2>&1 \
    || die "cannot read ${SVN_DEV_URL} -- check your network and your ASF svn credentials"

  cd "${PROJECT_DIR}"
  [[ -z "$(git status --porcelain)" ]] || die "working tree is dirty -- the source tarball archives the working tree, not HEAD"

  # release-src tars the working directory, and *.tgz is gitignored -- so a
  # leftover chart package from a previous release is invisible to git status
  # and would be embedded in this release's source archive.
  local strays
  strays=$(ls -1 ./*.tgz ./*.tgz.asc ./*.tgz.sha512 2>/dev/null || true)
  [[ -z "${strays}" ]] || die "stray release artifacts in the working tree, run 'make clean' first:
${strays}"

  # awk, not `grep | awk`: grep exits 1 when it matches nothing, pipefail promotes that to the
  # pipeline, and `set -e` then kills the script during the assignment -- silently, and before the
  # check below can report anything. awk exits 0 either way, so the check is reachable.
  VERSION=$(awk '/^version: /{print $2; exit}' "${CHART_FILE}")
  [[ -n "${VERSION}" ]] || die "could not read a 'version:' line from ${CHART_FILE}"
  TAG="v${VERSION}"
  log "version ${VERSION} (from chart/skywalking/Chart.yaml)"

  git rev-parse "${TAG}" >/dev/null 2>&1 && die "tag ${TAG} already exists -- bump Chart.yaml or delete the tag"

  # A re-run after a partial upload would mkdir a local ${VERSION} over a path that already exists
  # in svn, and only find out at commit time -- after the build, the signing and the tag push.
  # Safe to read a non-zero exit as "not there" only because the svn check above already
  # established that the repository is reachable and the credentials work.
  svn ls "${SVN_DEV_URL}/helm/${VERSION}" >/dev/null 2>&1 \
    && die "${SVN_DEV_URL}/helm/${VERSION} already exists -- delete it, or bump the version"

}

build() {
  step "Build"
  cd "${PROJECT_DIR}"
  make clean
  make release
}

tag() {
  # Deliberately after the build and the artifact checks: a tag pushed before
  # them survives a failure, and preflight then refuses to re-run because the
  # tag exists. Fail before the irreversible step, not after it.
  step "Tag ${TAG}"
  cd "${PROJECT_DIR}"
  if ${DRY_RUN}; then
    log "dry run: not creating or pushing ${TAG}"
  else
    git tag -a "${TAG}" -m "Release Apache SkyWalking Helm ${VERSION}"
    git push origin "${TAG}"
  fi
}

verify_artifacts() {
  step "Verify the artifacts"
  cd "${PROJECT_DIR}"

  # Six files: the source tarball and the packaged chart, each signed and
  # checksummed. Both are voted artifacts for this project.
  local expected=(
    "${PRODUCT_NAME}-${VERSION}-src.tgz"
    "${PRODUCT_NAME}-${VERSION}.tgz"
  )

  for f in "${expected[@]}"; do
    [[ -f "${f}"        ]] || die "${f} was not produced by 'make release'"
    [[ -f "${f}.asc"    ]] || die "${f}.asc is missing"
    [[ -f "${f}.sha512" ]] || die "${f}.sha512 is missing"

    gpg --batch --verify "${f}.asc" "${f}" 2>/dev/null || die "signature check failed for ${f}"
    shasum -a 512 -c "${f}.sha512" >/dev/null       || die "checksum check failed for ${f}"
    log "${f} -- signature and checksum OK"
  done

  # A chart that lints but renders nothing is a valid chart. Render it.
  local rendered
  rendered=$(helm template rel "${PRODUCT_NAME}-${VERSION}.tgz" \
    --set oap.image.tag=x --set ui.image.tag=x --set oap.storageType=elasticsearch 2>/dev/null | grep -c '^kind:' || true)
  [[ "${rendered}" -gt 0 ]] || die "the packaged chart renders no resources"
  log "packaged chart renders ${rendered} resources"
}

upload_to_svn() {
  step "Upload to ${SVN_DEV_URL}/helm/${VERSION}"
  cd "${PROJECT_DIR}"

  # EXIT, not RETURN: a RETURN trap does not fire when `set -e` kills the shell part-way through
  # the function, which would leave a temp directory holding a copy of the signed artifacts.
  local workdir
  workdir=$(mktemp -d)
  trap 'rm -rf "${workdir}"' EXIT

  # Sparse checkout: a full checkout of dist/dev/skywalking pulls every
  # sub-project's staging area, which is gigabytes.
  svn co --depth empty "${SVN_DEV_URL}" "${workdir}/skywalking" >/dev/null
  svn up --depth empty "${workdir}/skywalking/helm" >/dev/null 2>&1 || true
  mkdir -p "${workdir}/skywalking/helm/${VERSION}"
  cp "${PRODUCT_NAME}-${VERSION}"*.tgz* "${workdir}/skywalking/helm/${VERSION}/"

  cd "${workdir}/skywalking/helm"
  svn add "${VERSION}"

  if ${DRY_RUN}; then
    log "dry run: not committing. staged files:"
    svn status | sed 's/^/    /'
  else
    svn commit -m "Draft Apache SkyWalking Helm release ${VERSION}"
    log "uploaded"
  fi
}

vote_mail() {
  step "Vote mail -- copy from here"
  cd "${PROJECT_DIR}"

  local checksums
  checksums=$(for f in "${PRODUCT_NAME}-${VERSION}"*.tgz.sha512; do printf '   - '; cat "${f}"; done)

  cat <<EOF

=========================================================================
Subject: [VOTE] Release Apache SkyWalking Helm Chart version ${VERSION}

Content:

Hi the SkyWalking Community,

This is a call for vote to release Apache SkyWalking Helm Chart version ${VERSION}.

Release notes:

 * https://github.com/apache/skywalking-helm/blob/${TAG}/docs/changes/changes.md

Release Candidate:

 * ${SVN_DEV_URL}/helm/${VERSION}
 * sha512 checksums
${checksums}

Release Tag :

 * ${TAG}

Release Commit Hash :

 * https://github.com/apache/skywalking-helm/tree/$(git rev-parse HEAD)

Keys to verify the Release Candidate :

 * https://downloads.apache.org/skywalking/KEYS

Guide to build the release from source :

 * https://github.com/apache/skywalking-helm/blob/${TAG}/docs/contributing/release.md

Voting will start now and will remain open for at least 72 hours, all PMC members are required to
give their votes.

[ ] +1 Release this package.
[ ] +0 No opinion.
[ ] -1 Do not release this package because....

Thanks.
=========================================================================
EOF
}

# ---------------------------------------------------------------------------

preflight
build
verify_artifacts
tag
upload_to_svn
vote_mail

step "Done"
log "1. send the vote mail above to dev@skywalking.apache.org"
log "2. after 72h and three +1 PMC votes, run: bash tools/releasing/release-passed.sh ${VERSION}"
