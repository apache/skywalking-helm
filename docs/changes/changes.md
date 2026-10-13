# Changelog

## 5.1.0

### Breaking changes

- **A release installed with 5.1.0 or later carries only the Kubernetes recommended labels.** It has
  no `app`, `release`, `component`, `chart` or `heritage` label, so `kubectl -l` commands,
  NetworkPolicies, monitors and scripts written against those must use `app.kubernetes.io/*`
  instead. A release installed before 5.1.0 keeps them. See
  [Upgrade](../upgrade/upgrading.md#labels-and-selectors).
- **Argo CD and other render-only tools must set `labelStyle: legacy` on releases installed before
  5.1.0.** These tools render the chart without cluster access, so the chart cannot see the existing
  Deployments and renders the labels of a new release. Kubernetes rejects the new Deployment
  selectors, while the Services switch to labels the running pods never get, so OAP and the UI
  become unreachable until the value is set. `helm upgrade` detects existing releases by itself and
  needs nothing.

### Features

- **Kubernetes recommended labels.** A new release labels everything with `app.kubernetes.io/name`
  (always the chart name), `app.kubernetes.io/instance`, `app.kubernetes.io/component`,
  `app.kubernetes.io/managed-by` and `helm.sh/chart`, and every selector matches on them: the
  Deployments, the Services, OAP cluster discovery and dynamic configuration, Satellite's OAP lookup
  and pod anti-affinity. A release installed before 5.1.0 keeps its old labels and selectors,
  because a Deployment's selector is immutable, and gains the recommended labels next to them; a
  component enabled on it later gets the same style. The chart tells the two apart with `lookup`.
  `labelStyle` (`auto`, `legacy`, `modern`) overrides that, and is left out of the init Job's name
  hash, so changing it does not run init again. To move an older release to the new labels, delete
  its three Deployments and upgrade.
- A new E2E cell, `e2e-upgrade.yaml`, installs the published 5.0.0 chart and upgrades it to the
  working tree with identical values, checking that the old labels and selectors are kept and the
  init Job is never broken by an immutable pod-template change. `e2e-config-override.yaml` now checks
  that a fresh install carries only the recommended labels and selects by them.

### Bugs

- **The Satellite Role and RoleBinding carried OAP's component label.** They now carry Satellite's.

### Documentation
