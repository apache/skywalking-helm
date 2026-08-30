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
#   bash tools/releasing/release.sh              # ask for the versions, then do it
#   bash tools/releasing/release.sh --dry-run    # everything except the four writes
#
# The release is built from a FRESH CLONE this script makes for itself, under
# tools/releasing/, not from your checkout. `make release-src` archives the working tree rather
# than HEAD, so releasing from a working copy ships whatever untracked files happen to be sitting
# in it -- editor state, agent directories, a half-finished values file. Cloning removes the
# question entirely. Your own checkout is only read, for the default version.
#
# The four irreversible writes, all skipped by --dry-run:
#   the git tag, the svn commit, the next-version branch push, and the PR.
#
# After this: send the printed mail, merge the next-version PR, wait 72h, then
# tools/releasing/release-passed.sh.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd "${SCRIPT_DIR}/../.." && pwd)
PRODUCT_NAME="skywalking-helm"
REPO_URL="https://github.com/apache/skywalking-helm.git"
CLONE_DIR="${SCRIPT_DIR}/${PRODUCT_NAME}"
SVN_DEV_URL="https://dist.apache.org/repos/dist/dev/skywalking"
CHART_FILE_REL="chart/skywalking/Chart.yaml"

DRY_RUN=false
case "${1:-}" in
  "")         ;;
  --dry-run)  DRY_RUN=true ;;
  *)          echo "ERROR: unknown argument '${1}' -- did you mean --dry-run?" >&2; exit 1 ;;
esac

log()  { echo "  $*"; }
step() { echo; echo "=== $* ==="; }
die()  { echo "ERROR: $*" >&2; exit 1; }

ask() {
  # `read` exits 1 at EOF. Without this the script dies with no message at all when it is piped
  # or run from CI -- the exact silent failure this script is careful to avoid elsewhere.
  local reply
  read -r -p "  $1" reply || die "nothing on stdin -- run this script from a terminal"
  printf '%s' "${reply}"
}

# The svn staging area lives in a temp directory, outside both your checkout and the clone, so it
# can never be swept up by `make release-src`. The cleanup is registered here, at script scope,
# over a script-scope variable: an EXIT trap runs after the function has already returned and so
# cannot see a `local`, and under `set -u` the unbound name would make the trap itself fail and
# take the script's exit status with it.
WORKDIR=""
cleanup() { [[ -n "${WORKDIR}" ]] && rm -rf "${WORKDIR}"; return 0; }
trap cleanup EXIT

# ---------------------------------------------------------------------------

resolve_versions() {
  step "Versions"

  local current major minor
  current=$(awk '/^version: /{print $2; exit}' "${PROJECT_DIR}/${CHART_FILE_REL}" 2>/dev/null || true)

  RELEASE_VERSION="${current}"
  NEXT_RELEASE_VERSION=""
  if [[ "${RELEASE_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    NEXT_RELEASE_VERSION="${major}.$((minor + 1)).0"
  fi

  log "release version:  ${RELEASE_VERSION:-<unreadable>}   (from your checkout's ${CHART_FILE_REL})"
  log "next dev version: ${NEXT_RELEASE_VERSION:-<unreadable>}"
  echo

  local reply
  reply=$(ask "Are these correct? [y/N] ")
  if [[ "${reply}" != "y" && "${reply}" != "Y" ]]; then
    RELEASE_VERSION=$(ask "Enter release version:  ")
    NEXT_RELEASE_VERSION=$(ask "Enter next dev version: ")
  fi

  # Both get interpolated into a git tag, an svn path and a branch name. Refusing anything that
  # is not plain semver keeps all three predictable, and keeps shell metacharacters out of them.
  [[ "${RELEASE_VERSION}"      =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "release version '${RELEASE_VERSION}' is not MAJOR.MINOR.PATCH"
  [[ "${NEXT_RELEASE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "next version '${NEXT_RELEASE_VERSION}' is not MAJOR.MINOR.PATCH"
  [[ "${RELEASE_VERSION}" != "${NEXT_RELEASE_VERSION}" ]] || die "the release and next versions are both ${RELEASE_VERSION}"

  TAG="v${RELEASE_VERSION}"
  log "releasing ${RELEASE_VERSION}, then opening a PR to move master to ${NEXT_RELEASE_VERSION}"
}

preflight() {
  step "Preflight"

  # Running this from inside the throwaway clone would nest another clone beneath it.
  [[ "${PROJECT_DIR}" != "${CLONE_DIR}" ]] || die "you are inside the throwaway clone -- run this from your own checkout"

  # Report every missing tool at once. Dying on the first means one failed run per package, and
  # this check exists precisely to spend zero of them.
  local missing=""
  for tool in helm gpg shasum svn git make tar awk yq gh; do
    command -v "${tool}" >/dev/null || missing="${missing} ${tool}"
  done
  [[ -z "${missing}" ]] || die "not installed:${missing}"

  # Present is not the same as usable, and each of these otherwise fails LATE: a missing signing
  # key after the whole build, bad svn credentials after the tag is already pushed, an
  # unauthenticated gh after the vote candidate is already staged.
  #
  # 3.8, not 3: the chart is published only as an OCI artifact, and `helm push` to an oci://
  # registry landed in 3.8. Helm 4 is fine -- Chart.yaml is apiVersion v2, which both majors
  # read -- so this bounds from below only, and does not cap the major.
  local helm_ver helm_major helm_minor
  helm_ver=$(helm version --short 2>/dev/null | sed 's/^v//; s/[-+].*//')
  helm_major=${helm_ver%%.*}
  helm_minor=$(printf '%s' "${helm_ver}" | cut -d. -f2)
  [[ -n "${helm_major}" ]] || die "could not parse 'helm version --short'"
  if (( helm_major < 3 || (helm_major == 3 && helm_minor < 8) )); then
    die "helm 3.8 or newer is required, found ${helm_ver}"
  fi

  local seckeys
  seckeys=$(gpg --list-secret-keys --with-colons 2>/dev/null | grep -c '^sec' || true)
  [[ "${seckeys}" -gt 0 ]] || die "gpg has no secret key -- 'make release' signs the artifacts and would fail after the build"

  gh auth status >/dev/null 2>&1 || die "gh is not authenticated -- run 'gh auth login'. It opens the next-version PR at the end."

  svn ls "${SVN_DEV_URL}" >/dev/null 2>&1 \
    || die "cannot read ${SVN_DEV_URL} -- check your network and your ASF svn credentials"

  # `if`, not `X && die`. An && list that fails on its left side returns non-zero, and as a
  # function's last statement that becomes the function's return value, which `set -e` treats as
  # a failed call and uses to kill the run -- with no message at all.
  if git ls-remote --exit-code --tags "${REPO_URL}" "refs/tags/${TAG}" >/dev/null 2>&1; then
    die "tag ${TAG} already exists on the remote -- bump the version, or delete the tag"
  fi

  # Safe to read a non-zero exit as "not there" only because the svn check above already
  # established that the repository is reachable and the credentials work.
  if svn ls "${SVN_DEV_URL}/helm/${RELEASE_VERSION}" >/dev/null 2>&1; then
    die "${SVN_DEV_URL}/helm/${RELEASE_VERSION} already exists -- delete it, or bump the version"
  fi

  log "all checks passed"
}

clone_repo() {
  step "Clone ${REPO_URL}"

  # Not --depth 1: the tag is created and pushed from here, and prepare_next_version branches
  # from here. Both want real history.
  rm -rf "${CLONE_DIR}"
  git clone --quiet "${REPO_URL}" "${CLONE_DIR}"
  cd "${CLONE_DIR}"
  log "cloned $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD)"

  # This project tags master as it stands, with the version bump landing in its own PR
  # beforehand. If the clone does not already say RELEASE_VERSION then master is not ready, and
  # setting it here would tag a commit that exists nowhere but this throwaway directory.
  local cloned
  cloned=$(awk '/^version: /{print $2; exit}' "${CHART_FILE_REL}")
  [[ "${cloned}" == "${RELEASE_VERSION}" ]] \
    || die "master's ${CHART_FILE_REL} says ${cloned}, not ${RELEASE_VERSION} -- land a 'Ready to release ${RELEASE_VERSION}' PR first"
  log "${CHART_FILE_REL} says ${cloned}, matching the release version"
}

build() {
  step "Build"
  cd "${CLONE_DIR}"
  make clean
  make release
}

verify_artifacts() {
  step "Verify the artifacts"
  cd "${CLONE_DIR}"

  # Six files: the source tarball and the packaged chart, each signed and checksummed. Both are
  # voted artifacts for this project.
  local expected=(
    "${PRODUCT_NAME}-${RELEASE_VERSION}-src.tgz"
    "${PRODUCT_NAME}-${RELEASE_VERSION}.tgz"
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
  rendered=$(helm template rel "${PRODUCT_NAME}-${RELEASE_VERSION}.tgz" \
    --set oap.image.tag=x --set ui.image.tag=x --set oap.storageType=elasticsearch 2>/dev/null | grep -c '^kind:' || true)
  [[ "${rendered}" -gt 0 ]] || die "the packaged chart renders no resources"
  log "packaged chart renders ${rendered} resources"

  # tar does not honour .gitignore, so nothing about ignoring the clone directory keeps it out of
  # the archive. Check the archive itself.
  local strays
  strays=$(tar tzf "${PRODUCT_NAME}-${RELEASE_VERSION}-src.tgz" \
    | grep -E "tools/releasing/${PRODUCT_NAME}/|\.tgz\$|/charts/|Chart\.lock" || true)
  [[ -z "${strays}" ]] || die "the source tarball contains things it should not:
${strays}"
  log "source tarball carries no build output"
}

tag() {
  # Deliberately after the build and the artifact checks: a tag pushed before them survives a
  # failure, and preflight then refuses to re-run because the tag exists. Fail before the
  # irreversible step, not after it.
  step "Tag ${TAG}"
  cd "${CLONE_DIR}"
  if ${DRY_RUN}; then
    log "dry run: not creating or pushing ${TAG}"
  else
    git tag -a "${TAG}" -m "Release Apache SkyWalking Helm ${RELEASE_VERSION}"
    git push origin "${TAG}"
    log "pushed ${TAG} at $(git rev-parse --short "${TAG}")"
  fi
}

upload_to_svn() {
  step "Upload to ${SVN_DEV_URL}/helm/${RELEASE_VERSION}"
  cd "${CLONE_DIR}"

  WORKDIR=$(mktemp -d)

  # Sparse checkout: a full checkout of dist/dev/skywalking pulls every sub-project's staging
  # area, which is gigabytes.
  svn co --depth empty "${SVN_DEV_URL}" "${WORKDIR}/skywalking" >/dev/null
  svn up --depth empty "${WORKDIR}/skywalking/helm" >/dev/null 2>&1 || true
  mkdir -p "${WORKDIR}/skywalking/helm/${RELEASE_VERSION}"
  cp "${PRODUCT_NAME}-${RELEASE_VERSION}"*.tgz* "${WORKDIR}/skywalking/helm/${RELEASE_VERSION}/"

  cd "${WORKDIR}/skywalking/helm"
  svn add "${RELEASE_VERSION}" >/dev/null

  if ${DRY_RUN}; then
    log "dry run: not committing. staged files:"
    svn status | sed 's/^/    /'
  else
    svn commit -m "Draft Apache SkyWalking Helm release ${RELEASE_VERSION}"
    log "uploaded"
  fi
}

prepare_next_version() {
  step "Next iteration ${NEXT_RELEASE_VERSION}"
  cd "${CLONE_DIR}"

  local branch="bump-to-${NEXT_RELEASE_VERSION}"
  git checkout --quiet -b "${branch}"

  # sed, not `yq -i`: yq rewrites the whole document, and on this file that reindents every list
  # and drops a blank line -- a 53-line diff for a one-line change.
  sed -i.bak -E "s/^version: .*/version: ${NEXT_RELEASE_VERSION}/" "${CHART_FILE_REL}"
  rm -f "${CHART_FILE_REL}.bak"
  log "${CHART_FILE_REL} -> ${NEXT_RELEASE_VERSION}"

  # Rotate the changelog: what was being written becomes the released version's own page, and a
  # fresh one starts from the template.
  git mv docs/changes/changes.md "docs/changes/changes-${RELEASE_VERSION}.md"
  sed "s/NEXT_RELEASE_VERSION/${NEXT_RELEASE_VERSION}/g" docs/changes/changes.tpl > docs/changes/changes.md
  log "changes.md -> changes-${RELEASE_VERSION}.md, and a new changelog for ${NEXT_RELEASE_VERSION}"

  # Insert the released version directly after "Current Version", so the in-progress changelog
  # keeps the top of the Changelog menu and the released ones stay in descending order.
  yq -i "(.catalog[] | select(.name == \"Changelog\") | .catalog) |= [.[] | select(.name == \"Current Version\")] + [{\"name\": \"${RELEASE_VERSION}\", \"path\": \"/changes/changes-${RELEASE_VERSION}\"} | .name style=\"double\" | .path style=\"double\"] + [.[] | select(.name != \"Current Version\")]" docs/menu.yml
  log "docs/menu.yml -> Changelog gains ${RELEASE_VERSION}"

  git add "${CHART_FILE_REL}" docs
  git commit --quiet -m "Start the next iteration ${NEXT_RELEASE_VERSION}"

  if ${DRY_RUN}; then
    log "dry run: not pushing ${branch}, not opening a PR. It would carry:"
    git show --stat --oneline HEAD | sed 's/^/    /'
  else
    git push --quiet --set-upstream origin "${branch}"
    gh pr create --repo apache/skywalking-helm --base master --head "${branch}" \
      --title "Start the next iteration ${NEXT_RELEASE_VERSION}" \
      --body "Opened by \`tools/releasing/release.sh\` while staging the ${RELEASE_VERSION} vote.

- \`${CHART_FILE_REL}\` moves to ${NEXT_RELEASE_VERSION}
- \`docs/changes/changes.md\` becomes \`changes-${RELEASE_VERSION}.md\`, and a fresh changelog starts for ${NEXT_RELEASE_VERSION}
- \`docs/menu.yml\` gains the ${RELEASE_VERSION} changelog entry

Merge once the ${RELEASE_VERSION} vote thread is open. It does not affect the artifacts under vote, which were built from \`${TAG}\`."
    log "PR opened"
  fi
}

vote_mail() {
  step "Vote mail -- copy from here"
  cd "${CLONE_DIR}"

  local checksums commit
  checksums=$(for f in "${PRODUCT_NAME}-${RELEASE_VERSION}"*.tgz.sha512; do printf '   - '; cat "${f}"; done)
  # HEAD is wrong here: prepare_next_version has already moved the clone onto the bump branch, so
  # resolve the tag itself, falling back in a dry run to what would have been tagged.
  #
  # --verify --quiet, not `2>/dev/null`: a plain `git rev-parse` ECHOES an unresolvable ref back on
  # STDOUT and exits 128, so `$(git rev-parse X 2>/dev/null || git rev-parse master)` captures the
  # literal "v5.1.0^{commit}" AND the fallback hash, and the vote mail goes out with a broken link.
  commit=$(git rev-parse --verify --quiet "${TAG}^{commit}" || git rev-parse --verify master)

  cat <<EOF

=========================================================================
Subject: [VOTE] Release Apache SkyWalking Helm Chart version ${RELEASE_VERSION}

Content:

Hi the SkyWalking Community,

This is a call for vote to release Apache SkyWalking Helm Chart version ${RELEASE_VERSION}.

Release notes:

 * https://github.com/apache/skywalking-helm/blob/${TAG}/docs/changes/changes.md

Release Candidate:

 * ${SVN_DEV_URL}/helm/${RELEASE_VERSION}
 * sha512 checksums
${checksums}

Release Tag :

 * ${TAG}

Release Commit Hash :

 * https://github.com/apache/skywalking-helm/tree/${commit}

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

resolve_versions
preflight
clone_repo
build
verify_artifacts
tag
upload_to_svn
prepare_next_version
vote_mail

step "Done"
log "release version:  ${RELEASE_VERSION}"
log "next dev version: ${NEXT_RELEASE_VERSION}"
log "build clone kept: ${CLONE_DIR}"
echo
log "1. send the vote mail above to dev@skywalking.apache.org"
log "2. merge the 'Start the next iteration ${NEXT_RELEASE_VERSION}' PR"
log "3. after 72h and three +1 PMC votes, run: bash tools/releasing/release-passed.sh ${RELEASE_VERSION}"
