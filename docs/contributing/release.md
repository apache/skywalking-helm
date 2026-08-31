# Package and Publish a Release

Two scripts drive a release of `apache/skywalking-helm`. They are the procedure; this page explains
what they do and what is left for a human.

| Script | Covers |
| --- | --- |
| [`tools/releasing/release.sh`](../../tools/releasing/release.sh) | everything up to and including the call for vote — build, verify, tag, upload to svn, print the vote mail |
| [`tools/releasing/release-passed.sh`](../../tools/releasing/release-passed.sh) | everything after the vote passes — promote the artifacts, create the GitHub release, print the ANNOUNCE mail |

`release.sh` reads the version out of `chart/skywalking/Chart.yaml`; `release-passed.sh` takes it as
its first argument. Both accept `--dry-run`. Both call the `Makefile`, whose per-target detail is in
[Makefile reference](#makefile-reference) at the end — reference, not procedure.

## What gets released

Two artifacts are signed, uploaded and **voted on** — the source tarball *and* the packaged chart.
That is settled by precedent: every version under
[`dist/release/skywalking/helm/`](https://dist.apache.org/repos/dist/release/skywalking/helm/)
carries six files.

| Where | Artifact | For chart `5.0.0` |
| --- | --- | --- |
| dist.apache.org | source tarball, `.asc`, `.sha512` | `skywalking-helm-5.0.0-src.tgz` |
| dist.apache.org | packaged chart, `.asc`, `.sha512` | `skywalking-helm-5.0.0.tgz` |
| Docker Hub (OCI) | the chart users install — a convenience binary, pushed **after** the vote | `oci://docker.io/apache/skywalking-helm:5.0.0` |
| ghcr.io (OCI) | `0.0.0-<sha>` snapshot of every `master` commit — **not** a release | `oci://ghcr.io/apache/skywalking-helm/skywalking-helm:0.0.0-<sha>` |

The dist path for this project is `skywalking/helm/`. The `skywalking/kubernetes/` directory on dist
is a leftover from the repository's old name (`skywalking-kubernetes`) and still holds `4.7.0`;
nothing new goes there.

The Git tag is `v$VERSION` (`v5.0.0`). Every other coordinate is the plain `$VERSION` (`5.0.0`).
`VERSION` and `CHART_NAME` are read out of `chart/skywalking/Chart.yaml` by the `Makefile` and are
never passed as arguments — see [The version is read, never passed](#the-version-is-read-never-passed).

## 1. Prepare

Everything here lands in one **"Ready to release $VERSION"** PR against `master`. Do not push to
`master` directly — that is the project's rule, not something the tooling stops you doing. The
`.asf.yaml` ruleset on the default branch restricts *deletion and force-push* only, so a direct push
would succeed.

### Milestones

Issues are disabled on this repository, so a release spans two milestones:

- [`apache/skywalking-helm` milestones](https://github.com/apache/skywalking-helm/milestones) —
  the PRs of this release (`5.0.0`).
- [`apache/skywalking` milestones](https://github.com/apache/skywalking/milestones) — the
  user-facing issues, filed there under `Helm - $VERSION`.

Close everything finished in both; move the rest to the next milestone, creating it if needed.

### Changelog

[`docs/changes/changes.md`](../changes/changes.md) must have a finished section for `$VERSION`,
headed `## $VERSION`, covering breaking changes, features and fixes. This is what the vote mail and
the ANNOUNCE mail link to.

### Version bump

```shell
# chart/skywalking/Chart.yaml
version: 5.0.0
```

Then sweep the prose. The chart version is quoted in `helm install` examples across nearly the whole
docs tree — at `5.0.0` that is **19 files** under `README.md` and `docs/`, not a handful. Do not work
from a remembered list; let grep produce it:

```shell
grep -rln '4\.9\.0' README.md docs/          # the version you are leaving behind
grep -rn -- '--version' README.md docs/ | grep -v '4\.9\.0\|5\.0\.0'   # stragglers on other pins
```

Neither comes back empty, so read the hits rather than counting them. The first keeps the deliberate
historical references — [Upgrading](../upgrade/upgrading.md) documents the `4.9.0` → `5.0.0` bump,
[Where to Get the Chart](../install/chart-sources.md) records that `4.9.0` never reached Docker Hub,
and this page cites the dist layout.

The second command is there because not every occurrence is literal: `docs/install/quick-start.md`
passes the chart version through a `SKYWALKING_RELEASE_VERSION` shell variable, and
`docs/install/chart-sources.md` also carries `--version` for the *subchart* pins (`3.3.1` and
friends), which must **not** be bumped along with the chart. Image tags quoted in the docs
(`oap.image.tag`, `ui.image.tag`, `banyandb.image.tag`) must match
[Version Compatibility](../evaluate/version-compatibility.md) — which itself carries the chart
version in its own install example, so it is part of the sweep, not the reference standing outside
it.

### Dependency versions

Every dependency version has to resolve before you can build. BanyanDB Helm is released by
[`apache/skywalking-banyandb-helm`](https://github.com/apache/skywalking-banyandb-helm) and pushed
to the same Docker Hub OCI namespace, so ask the registry:

```shell
helm show chart oci://docker.io/apache/skywalking-banyandb-helm --version 0.7.0
```

An `Error: ... not found` means it is not published there. Cross-check the source release exists too:
<https://dist.apache.org/repos/dist/release/skywalking/banyandb-helm/>.

Audit every dependency before tagging:

```shell
grep '^  version:' chart/skywalking/Chart.yaml
```

The dependency versions are the indented `version:` lines; the chart's own `version:` starts at
column 0. Do not anchor the search to the `- name:` line above it — two entries carry an `alias:` in
between, including the BanyanDB one.

### Checklist before running the scripts

1. `version:` in `chart/skywalking/Chart.yaml` bumped, and the docs sweep done.
2. `dependencies:` in `chart/skywalking/Chart.yaml` all resolve.
3. `docs/changes/changes.md` has a finished `## $VERSION` section.
4. [E2E tests](e2e-tests.md) green on the release commit.
5. Both milestones tidy.
6. The "Ready to release $VERSION" PR merged.

## 2. Add your GPG public key to Apache svn

1. Log in to [id.apache.org](https://id.apache.org/) and submit your key fingerprint.
2. Append your GPG public key to the
   [SkyWalking KEYS](https://dist.apache.org/repos/dist/release/skywalking/KEYS) file — **PMC
   members only**; ask a PMC member otherwise. **Do not overwrite the existing content, append at
   the end.**

The build signs with `gpg --batch --yes`, which will not prompt: the release key must be the default
secret key in your keyring, with its passphrase available through the agent.

```shell
gpg --list-secret-keys --keyid-format=long
```

## 3. Build, verify, tag, upload and call the vote — `release.sh`

**Run it from your own checkout.** Linux and macOS both work — the build was verified end to end
on each.

```shell
bash tools/releasing/release.sh --dry-run   # everything except the four writes
bash tools/releasing/release.sh
```

You do not need a clean tree, because the script does not build from your tree. It clones
`apache/skywalking-helm` fresh into `tools/releasing/skywalking-helm/` and does everything there.
That is not tidiness: `make release-src` archives the working *tree*, not `HEAD`, so releasing from
a working copy ships whatever untracked files happen to be sitting in it — editor state, an agent
directory, a half-finished values file. Cloning removes the question. Your checkout is only read,
for the default version.

Note that ignoring such a directory does **not** protect you — `tar` does not read `.gitignore`, so
a gitignored directory is silently archived. That is why the clone is excluded in the Makefile *and*
`verify_artifacts` inspects the finished tarball.

It asks for both versions before doing anything, defaulting from your checkout's `Chart.yaml`:

```
=== Versions ===
  release version:  5.1.0   (from your checkout's chart/skywalking/Chart.yaml)
  next dev version: 5.2.0

  Are these correct? [y/N]
```

Answer anything but `y` to type them in. Both must be plain `MAJOR.MINOR.PATCH` — they end up in a
git tag, an svn path and a branch name, and refusing anything else keeps shell metacharacters out of
all three.

`--dry-run` still clones, builds, signs and verifies, and still runs the svn checkout and the
next-version commit. It skips exactly four things: the tag push, the svn commit, the branch push and
the PR.

### The order matters

| Stage | What it does |
| --- | --- |
| `resolve_versions` | asks for the release and next-dev versions, defaulting from your `Chart.yaml` |
| `preflight` | refuses to start (see below) |
| `clone_repo` | fresh clone into `tools/releasing/skywalking-helm/`; everything below runs there |
| `build` | `make clean` then `make release` — six files in the clone |
| `verify_artifacts` | signature, checksum, a real render, and an inspection of the source tarball |
| `tag` | `git tag -a v$VERSION` and `git push origin v$VERSION` |
| `upload_to_svn` | sparse checkout of `dist/dev/skywalking`, then `svn add` + `svn commit` |
| `prepare_next_version` | rotates the changelog, bumps the chart, opens the next-version PR |
| `vote_mail` | prints the mail, with the real checksums and commit hash filled in |

`clone_repo` also refuses to continue unless master's `Chart.yaml` already says the release version.
This project tags master as it stands, so if the version is not already there then master is not
ready — and setting it inside the clone would tag a commit that exists nowhere else.

The tag is pushed **after** the build and the artifact checks, deliberately. A tag pushed first
survives a failed build, and preflight then refuses to re-run because `v$VERSION` exists — so the
irreversible step comes last, and a failure leaves nothing on the remote to clean up.

Preflight refuses to start when:

- any of `helm`, `gpg`, `shasum`, `svn`, `git`, `make`, `tar`, `awk` is missing. All of them are
  reported in one message — finding them one at a time costs one failed run per package;
- `helm` is older than 3.8. The chart ships only as an OCI artifact, and `helm push` to an `oci://`
  registry arrived in 3.8. Helm 4 is accepted: `Chart.yaml` is `apiVersion: v2`, which both majors
  read;
- `gpg` holds no secret key. `make release` signs with `gpg --batch`, so without one the run would
  fail *after* building and packaging everything;
- `gh` is not authenticated. It opens the next-version PR at the very end, so an unauthenticated
  `gh` would otherwise surface only after the vote candidate is already staged;
- `dist/dev/skywalking` cannot be read — a network problem, or svn credentials that are not set up;
- `v$VERSION` already exists on the remote, or `dist/dev/skywalking/helm/$VERSION` already does. The second catches
  a re-run after a partial upload, which would otherwise only surface at `svn commit` — after the
  build, the signing and the tag push.

The point of the capability checks is *when* they fail. A missing signing key or unusable svn
credentials are both perfectly capable of stopping a release half-way through, with a tag already on
the remote; preflight is the only place where stopping is free.

`verify_artifacts` checks, for each of the two artifacts, that the file and its `.asc` and `.sha512`
are present, that `gpg --batch --verify` passes and that `shasum -a 512 -c` passes. It then runs
`helm template` over the packaged chart and requires at least one rendered `kind:` — a chart that
lints but renders nothing is a valid chart. That render uses `oap.storageType=elasticsearch` with
`elasticsearch.enabled` left at its default `true`, so it exercises the ECK path. Finally it lists
the source tarball and fails if it contains the build clone, a `.tgz`, a `charts/` directory or a
`Chart.lock`.

### The next-version PR

`prepare_next_version` runs after the candidate is staged, on a `bump-to-$NEXT` branch of the clone:

- `chart/skywalking/Chart.yaml` moves to the next dev version — with `sed`, not `yq`, because `yq`
  rewrites the whole document and turns a one-line bump into a fifty-line reindent;
- `docs/changes/changes.md` becomes `docs/changes/changes-$VERSION.md`, and a fresh changelog is
  rendered from `docs/changes/changes.tpl`;
- `docs/menu.yml` gains the released version, inserted directly after `Current Version` so the
  in-progress changelog keeps the top of the menu and released versions stay newest-first.

Merge it once the vote thread is open. It cannot affect the artifacts under vote — those were built
from the tag, before this branch existed.

### Send the vote mail

The script prints the mail and stops; it sends nothing. Copy it, check the checksums and the commit
hash it filled in, and send it to `dev@skywalking.apache.org` from your Apache address. Confirm the
six files are visible at `https://dist.apache.org/repos/dist/dev/skywalking/helm/$VERSION/` first.

Voting stays open for at least 72 hours.

## 4. Vote check

What a voter runs. Everything happens in a scratch directory, from the staged URL, never from the
release manager's working copy.

```shell
export VERSION=5.0.0
curl -O "https://dist.apache.org/repos/dist/dev/skywalking/helm/$VERSION/skywalking-helm-$VERSION-src.tgz{,.asc,.sha512}"
curl -O "https://dist.apache.org/repos/dist/dev/skywalking/helm/$VERSION/skywalking-helm-$VERSION.tgz{,.asc,.sha512}"
```

1. **Both artifacts are present**, each with `.asc` and `.sha512` — six files.
2. **Signatures.**

    ```shell
    curl https://downloads.apache.org/skywalking/KEYS -o KEYS && gpg --import KEYS
    gpg --batch --verify skywalking-helm-$VERSION-src.tgz.asc skywalking-helm-$VERSION-src.tgz
    gpg --batch --verify skywalking-helm-$VERSION.tgz.asc     skywalking-helm-$VERSION.tgz
    ```

3. **Checksums.**

    ```shell
    shasum -a 512 -c skywalking-helm-$VERSION-src.tgz.sha512
    shasum -a 512 -c skywalking-helm-$VERSION.tgz.sha512
    ```

4. **`LICENSE` and `NOTICE` are inside both tarballs** — the chart tarball gets them from
   `make prepare`, which copies them in from the repository root just before packaging.

    ```shell
    tar tzf skywalking-helm-$VERSION-src.tgz | grep -E '\./(LICENSE|NOTICE)$'
    tar tzf skywalking-helm-$VERSION.tgz     | grep -E 'skywalking-helm/(LICENSE|NOTICE)$'
    ```

5. **Build from source.** Extract the source tarball and package it; this needs network access,
   because `helm dep up` fetches the subcharts.

    ```shell
    mkdir src && tar xzf skywalking-helm-$VERSION-src.tgz -C src
    ( cd src && make package )      # keep the build in a subshell — see below
    ```

    Do not expect the resulting `.tgz` to checksum-match the voted one — `helm package` records file
    timestamps. Compare the file listing and the rendered output instead.

    **Stay out of `src/` for the steps below.** `make package` writes its own
    `skywalking-helm-$VERSION.tgz` into `src/`, with exactly the name of the artifact you
    downloaded. If you `cd src` and stay there, steps 6 and 7 silently inspect your local rebuild
    instead of the artifact under vote — and a rebuild passes even when the staged tarball is
    wrong. Run them from the scratch directory, where the downloaded file is.

6. **The chart renders — both storage paths.** `helm lint` and `helm template` both succeed on a
   chart that renders nothing, so look at the output, not the exit code. This chart has three
   required values, and no default backend: `oap.storageType` is `null` in `values.yaml`.

    BanyanDB is opt-in, and turning it on means turning Elasticsearch off:

    ```shell
    helm template sw skywalking-helm-$VERSION.tgz \
      --set oap.image.tag=11.0.0 \
      --set oap.storageType=banyandb \
      --set ui.image.tag=horizon-1.0.0 \
      --set elasticsearch.enabled=false \
      --set banyandb.enabled=true \
      --set banyandb.image.tag=0.11.0 > render-banyandb.yaml

    grep -c '^kind:' render-banyandb.yaml            # non-zero; 15 for 5.0.0
    grep -q '^kind: Deployment$' render-banyandb.yaml
    ```

    Elasticsearch is the default, and that is the render most users get. `elasticsearch.enabled` is
    `true` in `values.yaml`, so **do not carry `--set elasticsearch.enabled=false` over from the
    first command** — with it you get the first render minus BanyanDB (11 resources at `5.0.0`) and
    no ECK resource whatsoever, which is what the storage-type flag alone buys you:

    ```shell
    helm template sw skywalking-helm-$VERSION.tgz \
      --set oap.image.tag=11.0.0 \
      --set oap.storageType=elasticsearch \
      --set ui.image.tag=horizon-1.0.0 > render-es.yaml

    grep -c '^kind:' render-es.yaml                              # non-zero; 34 for 5.0.0
    grep -q '^kind: Elasticsearch$' render-es.yaml               # the ECK cluster CR
    grep -q 'charts/eck-operator/templates/statefulset.yaml' render-es.yaml
    grep -q 'sw-elasticsearch-es-http:9200' render-es.yaml       # OAP wired to the ECK service
    ```

    The `^kind: Elasticsearch$` anchor matters: `kind: Elasticsearch` also appears indented inside
    the operator's CRD schemas, so an unanchored grep passes on a render that contains no cluster.
    The three greps together are what "exercises ECK" means — the operator subchart, the
    `Elasticsearch` resource it reconciles, and the OAP deployment pointing at the `-es-http`
    service that ECK creates for it.

7. **The chart is stamped with the release version.** The subcharts are vendored into the tarball,
   so their versions are readable without a registry:

    ```shell
    tar xzOf skywalking-helm-$VERSION.tgz skywalking-helm/Chart.yaml | grep -E '^version:'
    tar tzf skywalking-helm-$VERSION.tgz | grep -E '^skywalking-helm/charts/[^/]+/Chart.yaml$'
    tar xzOf skywalking-helm-$VERSION.tgz skywalking-helm/Chart.yaml | grep -E '^  version:'
    ```

    `version:` must be `$VERSION`. The third command prints the dependency versions actually baked
    into the package — four entries at `5.0.0`, one per vendored subchart the second command lists.
    Note that `helm package` re-serializes `Chart.yaml`: keys come out alphabetized and the Apache
    header is gone from *that one file* inside the chart tarball. That is helm's doing and is not a
    defect; the license-header check belongs to the source tarball.

8. **License headers** across the source tarball
   ([license-eye](https://github.com/apache/skywalking-eyes)), and a functional smoke test if you
   have a cluster handy — [Quick Start](../install/quick-start.md).

The chart on Docker Hub is **not** part of the vote. It does not exist yet at this point.

Vote result rules:

1. PMC votes are +1 binding, everyone else +1 non-binding.
2. Vote passes with at least 3 binding +1 and more +1 than -1, within 72 hours.
3. **Send the closing mail**, listing the voters by name.

   ```text
   [RESULT][VOTE] Release Apache SkyWalking Helm version $VERSION

   3 days passed, we've got ($NUMBER) +1 bindings:
   xxx
   xxx
   xxx
   ...
   (list names)

   I'll continue the release process.
   ```

## 5. Publish — `release-passed.sh`

**PMC members only.** Run it once the vote thread has three binding +1 and no -1.

```shell
bash tools/releasing/release-passed.sh 5.0.0 --dry-run
bash tools/releasing/release-passed.sh 5.0.0
```

The version is the argument here — this script never reads `Chart.yaml`, so it can publish a
release from a checkout that has already moved on.

Every step is irreversible on shared infrastructure, so each asks first, and **declining aborts the
run** — with the one exception marked below. That is deliberate: the steps are ordered and
dependent, and saying no to the svn promotion and then carrying on would create a GitHub release,
and publish the chart, for artifacts still sitting in the dev area. `--dry-run` takes every prompt
as a no *without* aborting, so it walks the whole plan and does none of it.

| Stage | Prompt | Declining |
| --- | --- | --- |
| `resolve_version` | confirm the version to publish | — |
| `preflight` | — | fails if `svn` / `gh` / `git` are missing, if `gh` is not authenticated, if `dist/release/skywalking` cannot be read, or if `dist/dev/skywalking/helm/$VERSION` does not exist |
| `promote_artifacts` | `svn mv` from `dist/dev` to `dist/release` | aborts |
| `remove_previous` | remove everything under `release/helm/` other than `$VERSION` | **skips and continues** — the one exception |
| `github_release` | `gh release create` — this is what publishes the chart | aborts |
| `announce_mail` | — | prints the mail, sends nothing |
| `remaining` | — | prints what is left by hand |

`gh auth status` is checked in preflight rather than left to `github_release`, because
`github_release` runs *after* `promote_artifacts` — and an `svn mv` into `dist/release` cannot be
taken back. An unauthenticated `gh` has to stop the run before that, or not at all.

`remove_previous` is the exception because skipping it is survivable: `dist/release` is meant to
hold only the current version, but a stale sibling breaks nothing. Declining prints
`remove them by hand before announcing`, and the run continues. It lists what is there and asks
rather than guessing a pattern, because that directory is not uniformly laid out — today `4.9.0` is
a version directory while `4.8.0` sits as six loose files at the top level of `helm/`.

Old releases stay available from
[archive.apache.org](https://archive.apache.org/dist/skywalking/helm/); nothing extra to do for
that. Wait for the mirrors before announcing:

```shell
curl -sI "https://downloads.apache.org/skywalking/helm/$VERSION/skywalking-helm-$VERSION-src.tgz" | head -1
```

### The GitHub release is what publishes the chart

`.github/workflows/publish-helm.yaml` listens for `release: types: [released]`, so
`github_release` is the step that puts the chart on Docker Hub; `make publish` is the
[manual fallback](#make-publish--the-manual-fallback) only. The script runs:

```shell
gh release create "v$VERSION" --repo apache/skywalking-helm --verify-tag \
  --title "$VERSION" --notes "See .../blob/v$VERSION/docs/changes/changes.md"
```

`--verify-tag` is load-bearing: without it `gh` **creates** a missing tag from the default branch
head, which is not necessarily the commit the PMC voted on. The release is a full release, never a
draft or pre-release — the `released` event fires when a release is published as a full release (or
when an existing pre-release is converted into one), and never for drafts. If the release already
exists the script says so and moves on.

Before it pushes anything the workflow runs three hard guards, under a repository guard
(`github.repository == 'apache/skywalking-helm'`, so forks never publish):

| Check | Trips when | Effect |
| --- | --- | --- |
| Tag shape | the release tag is not `vMAJOR.MINOR.PATCH` | **Fails the job.** The tag is attacker-influenceable text that reaches a shell; only one shape is ever released. |
| Credentials | `DOCKERHUB_USER` / `DOCKERHUB_TOKEN` are not available to the repository | **Fails the job.** They are ASF org secrets; failing early beats an opaque `unauthorized` from the registry. |
| Version matches the tag | `version:` in `chart/skywalking/Chart.yaml` ≠ the tag minus its leading `v` | **Fails the job.** Publishing `5.0.0` from a `v5.1.0` tag would be silent and unfixable once the tag is immutable. |

It packages with `make package` (not bare `helm package`, so `NOTICE` and `LICENSE` are in the
chart), re-checks that both files are inside the tarball, and pushes to
`oci://docker.io/apache`, where `helm push` appends the chart name — landing at
`apache/skywalking-helm:$VERSION`.

Watch it and verify the result — this is not ceremony. Docker Hub currently holds
`apache/skywalking-helm` tags `4.3.0` through `4.8.0` only: **`4.9.0` was released but never reached
the registry**, which is the gap this workflow exists to close. Confirm yours landed:

```shell
gh run list --workflow publish-helm.yaml --repo apache/skywalking-helm --limit 3
helm show chart oci://docker.io/apache/skywalking-helm --version "$VERSION"
```

A `FetchReference ... not found` means the chart is not there, whatever the workflow's exit status
said.

Pushes to `master` keep doing what they always did — a `0.0.0-<sha>` snapshot to
`oci://ghcr.io/apache/skywalking-helm/skywalking-helm`, documented in
[Where to Get the Chart](../install/chart-sources.md).

### What the script leaves for you

It prints this list at the end; the detail is here.

1. **Website**, in [apache/skywalking-website](https://github.com/apache/skywalking-website):
   - `data/releases.yml` — under **SkyWalking Kubernetes Helm**, replace the version block with
     `$VERSION`: the `src` link through
     `https://www.apache.org/dyn/closer.cgi/skywalking/helm/$VERSION/…` and the `asc` / `sha512`
     links through `https://downloads.apache.org/skywalking/helm/$VERSION/…`. Set the release date.
   - `data/docs.yml` — the **Kubernetes Helm** entry. It still points at tags of the old
     `skywalking-kubernetes` repository; once the docs published from `docs/menu.yml` are wired into
     the site, add a version entry the way `skywalking-swck` does it — `version: v$VERSION`,
     `link: /docs/skywalking-helm/v$VERSION/readme/`, `commitId: <tag sha>` — and update `Latest`.
2. **The ANNOUNCE mail** the script printed, to `dev@skywalking.apache.org` and
   `announce@apache.org`, from your Apache address, with the vote thread permalink filled in from
   [lists.apache.org](https://lists.apache.org/list.html?dev@skywalking.apache.org).
3. **Milestones** — close `$VERSION` here and `Helm - $VERSION` on `apache/skywalking`, and open the
   next pair.
4. **The next development version** — bump `version:` in `chart/skywalking/Chart.yaml`.

## `make publish` — the manual fallback

```makefile
publish: package
	helm push ${CHART_NAME}-${VERSION}.tgz oci://docker.io/apache
```

It re-packages from your **working tree** and pushes to Docker Hub. Reach for it only when Actions is
unavailable or the release workflow is broken — the GitHub release created by `release-passed.sh` is
the normal path.

It has **none** of the workflow's guards:

- It does not check the chart version against any tag; it publishes whatever `Chart.yaml` says.
- It does not check credentials first; you get the registry's `unauthorized` instead.
- It builds from your working copy, not from the tag — uncommitted local edits get published, and
  nothing ties the pushed chart to the voted artifact.

If you must use it: `helm registry login docker.io` first (write access to the `apache`
Docker Hub organization is required), run it from a pristine checkout of `v$VERSION`, and only after
the vote has passed and the artifacts have moved to `dist/release`. Verify with
`helm show chart oci://docker.io/apache/skywalking-helm --version $VERSION`.

---

## Makefile reference

The scripts in [3](#3-build-verify-tag-upload-and-call-the-vote--releasesh) and
[5](#5-publish--release-passedsh) call these targets. Nothing below is a step to run by hand during
a release.

### The version is read, never passed

```makefile
CHART_DIR = chart/skywalking
VERSION = $(shell cat ${CHART_DIR}/Chart.yaml | grep '^version: ' | awk '{print $$2}')
CHART_NAME = $(shell cat ${CHART_DIR}/Chart.yaml | grep '^name: ' | awk '{print $$2}')

RELEASE_SRC = ${CHART_NAME}-${VERSION}-src
```

`make release VERSION=…` does not do what it looks like: a command-line assignment overrides the make
variable but not the file `helm package` writes — that name comes from `Chart.yaml` — so the
chart-package signing step and `publish` go looking for a tarball that does not exist (the source
tarball is built under the overridden name, so only the chart half breaks). Bumping a release means
editing the `version:` line in `chart/skywalking/Chart.yaml` and committing it. `CHART_NAME` comes
from the chart's `name:` field (`skywalking-helm`), not from the directory name (`skywalking`), so at
chart version `5.0.0` the artifacts are `skywalking-helm-5.0.0.tgz` and
`skywalking-helm-5.0.0-src.tgz`.

`chart/skywalking` is the only chart in this repository, and `CHART_DIR` has only ever pointed at it,
so a release packages, signs and publishes exactly one chart.

`TMPDIR` defaults to `/tmp` and is the only variable declared with `?=`, i.e. the only one meant to be
overridden (`make release TMPDIR=/var/tmp`). The recipe shell is `/bin/bash -eo pipefail`.

### Targets at a glance

| Target | Depends on | Produces |
| --- | --- | --- |
| `prepare` | — | `NOTICE` + `LICENSE` copied into `chart/skywalking/` |
| `package` | `prepare` | `skywalking-helm-<version>.tgz` |
| `clean` | — | nothing; deletes artifacts and resolved dependencies |
| `release-src` | `clean` | `skywalking-helm-<version>-src.tgz` |
| `release` | `release-src`, `package` | both tarballs, each with `.asc` and `.sha512` |
| `publish` | `package` | the chart pushed to Docker Hub as an OCI artifact |

Do not use `make -j`: `release-src` starts by wiping the tree that `package` writes into.

### `prepare` — the NOTICE/LICENSE copy dance

```makefile
prepare:
	cp -R NOTICE ${CHART_DIR}/NOTICE
	cp -R LICENSE ${CHART_DIR}/LICENSE
```

`NOTICE` and `LICENSE` live at the repository root, but an Apache release artifact has to carry them
*inside* the distributed tarball. `helm package` only picks up files under the chart directory, so
they are copied in immediately before packaging and deleted immediately after — the working tree
never keeps a second copy, and neither file is tracked under `chart/skywalking/`.

If a `make package` run dies partway through, those two copies are left behind. `make clean` removes
them.

### `package`

```makefile
package: prepare
	helm dep up ${CHART_DIR}
	helm package ${CHART_DIR}
	rm -rf ${CHART_DIR}/NOTICE
	rm -rf ${CHART_DIR}/LICENSE
```

`helm dep up` resolves every entry in the `dependencies:` block of `Chart.yaml` — `eck-operator`,
`eck-elasticsearch`, `postgresql`, `skywalking-banyandb-helm` — downloading each into
`chart/skywalking/charts/` and writing `chart/skywalking/Chart.lock`. Both are gitignored. `helm
package` then rolls the chart directory, its vendored subcharts, and the just-copied `NOTICE` and
`LICENSE` into `skywalking-helm-<version>.tgz` in the repository root, and the two copies are removed.

The subcharts are baked into the package. Whatever `helm dep up` resolved at package time is what
users get.

### `clean`

Deletes, in one `rm` invocation:

- `$(TMPDIR)/skywalking-helm-<version>-src.tgz`
- `bin/`
- `chart/skywalking/NOTICE`, `chart/skywalking/LICENSE`
- `chart/skywalking/Chart.lock`, `chart/skywalking/charts/`
- `skywalking-helm-<version>.tgz` and its `.asc` / `.sha512`
- `skywalking-helm-<version>-src.tgz` and its `.asc` / `.sha512`

One `rm -rf` with one list of operands. It used to repeat `rm -rf` on each backslash-continued line,
which — there being no `&&` between them — left those tokens sitting in the argument list of a single
`rm` whose only flag was `-f`. GNU `rm` permutes arguments, so on Linux the trailing `-rf` still
applied and `-f` swallowed the stray `rm` operands, and the target did what it read like. BSD `rm` —
macOS — stops option parsing at the first operand, so `-r` never took effect: it failed with
`rm: bin/: is a directory`, left `bin/` and `chart/skywalking/charts/` behind, and exited `1`, which
aborted `make clean`, `make release-src` and `make release`. The recipe is one `rm -rf` again and
survives BSD `rm`. `release.sh` carried a Linux-only guard for as long as that recipe was broken;
with the recipe fixed the guard was obsolete, and it has been removed.
If you touch it, keep it a single `rm -rf` and re-read the whole thing rather than one line.

Because `clean` wipes `charts/` and `Chart.lock`, the next `package` re-resolves dependencies from
scratch.

### `release-src`

```makefile
release-src: clean
	tar -zcvf $(TMPDIR)/$(RELEASE_SRC).tgz \
	--exclude bin --exclude .git --exclude .idea \
	--exclude .gitignore --exclude .DS_Store --exclude .github \
	. && \
	mv $(TMPDIR)/$(RELEASE_SRC).tgz .
```

It archives the whole working directory — hence the `clean` prerequisite, which removes `charts/`,
`Chart.lock` and this version's `.tgz` files before the tar runs. The tar is built in `$(TMPDIR)` and
only then moved into the repository root, so the archive never contains itself.

`clean` only knows the **current** `$(VERSION)`: it deletes `skywalking-helm-5.0.0*.tgz*`, not
`skywalking-helm-4.9.0.tgz`. A tarball left over from a previous release is not excluded by the tar
either (the exclude list has no `*.tgz`), so it would ship as a binary inside the ASF *source*
release. `release.sh` preflight refuses to start when one is present, which is the check that catches
this.

`tar .` takes the *working tree*, not `HEAD` — which is why preflight also refuses a dirty tree. Run
from a pristine checkout of the release commit: any untracked scratch file that is not in the exclude
list ships inside the ASF source release.

### `release`

```makefile
release: release-src package
	gpg --batch --yes --armor --detach-sig $(RELEASE_SRC).tgz
	shasum -a 512 $(RELEASE_SRC).tgz > $(RELEASE_SRC).tgz.sha512
	gpg --batch --yes --armor --detach-sig $(CHART_NAME)-$(VERSION).tgz
	shasum -a 512 $(CHART_NAME)-$(VERSION).tgz > $(CHART_NAME)-$(VERSION).tgz.sha512
```

The full sequence, in order: `clean` → `release-src` → `prepare` → `package` → sign and checksum.
**Both** artifacts are signed and checksummed, leaving six files in the repository root:

```text
skywalking-helm-5.0.0-src.tgz
skywalking-helm-5.0.0-src.tgz.asc
skywalking-helm-5.0.0-src.tgz.sha512
skywalking-helm-5.0.0.tgz
skywalking-helm-5.0.0.tgz.asc
skywalking-helm-5.0.0.tgz.sha512
```

Signing is armored and detached, and `--batch --yes` means GPG will not prompt.

### `publish`

See [`make publish` — the manual fallback](#make-publish--the-manual-fallback).
