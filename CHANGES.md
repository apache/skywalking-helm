Changes by Version
==================
Release Notes.

4.8.0
------------------

- Bump up BanyanDB Helm version to 0.5.2.

4.7.0
------------------

- Bump up Banyandb Helm version to 0.3.0.

4.6.0
------------------

- Integrate BanyanDB as storage solution.
- Bump up swck to v0.9.0.
- Bump up BanyanDB Helm version to 0.2.0.
- Bump up OAP and UI to 10.0.0.
- Make release process work with Linux.
- Support setting `secretMounts` in OAP.

4.5.0
------------------

- Add helm chart for swck v0.7.0.
- Add `pprof` port export in satellite.
- Trunc the resource name in swck's helm chart to no more than 63 characters.
- Adding the `configmap` into cluster role for oap init mode.
- Add config to set Pod securityContext.
- Keep the job name prefix the same as OAP Deployment name.
- Use startup probe option for first initialization of application
- Allow setting env for UI deployment.
- Add Istio ServiceEntry permissions.

4.4.0
------------------

- [**Breaking Change**]: remove `.Values.oap.initEs`, there is no need to use this to control whether to run init job anymore,
  SkyWalking Helm Chart automatically delete the init job when installing/upgrading.
- [**Breaking Change**]: remove `files/config.d` mechanism and use `values.yaml` files to put the configurations to override
  default config files in the `/skywalking/config` folder, using `files/config.d` is very limited and you have to clone the source
  codes if you want to use this mechanism, now you can simply use our [Docker Helm Chart](https://hub.docker.com/repository/docker/apache/skywalking-helm) to install.
- Refactor oap init job, and support postgresql storage.
- Upgrade ElasticSearch Helm Chart dependency version.

4.3.0
------------------

- Remove Istio adapter.
- Add `.Values.oap.initEs` to work with ElasticSearch init job.
- Add "pods/log" to OAP so on-demand Pod log can work.

4.2.0
------------------

- Fix Can't evaluate field Capabilities in type interface{}.
- Update the document let that all docker images use the latest version.
- Fix missing `nodes` resource permission when the OAP using `k8s-mesh` analyzer.
- Fix bug that customized config files are not loaded into es-init job.
- Add skywalking satellite support.

4.1.0
------------------

- Add missing service account to init job.
- Improve notes.txt and `nodePort` configuration.
- Improve ingress compatibility.
- Fix bug that customized config files are not loaded into es-init job.
- Add `imagePullSecrets` and node selector.
- Fix istio adapter description.
- Enhancement: allow mounting binary data files.

4.0.0
------------------

#### Features
- Allow overriding configurations files under /skywalking/config
- Unify the usages of different SkyWalking versions
- Add Values for init container in case of using private regestry
- Add `services`, `endpoints` resources in ClusterRole

3.1.0
------------------

#### Features
- Support SkyWalking 8.1.0
- Support enable oap dynamic configuration through k8s configmap

#### Download
- http://skywalking.apache.org/downloads/

3.0.0
------------------

#### Features
- Support SkyWalking 8.0.1

##### Note:
- 8.0.0 image is not suitable as chart image, ISSUE: https://github.com/apache/skywalking/issues/4953

2.0.0
------------------

#### Features
- Support SkyWalking 7.0.0
- Support set ES user/password
- Add CI for release

1.1.0
------------------

#### Features
- Support SkyWalking 6.6.0
- Support deploy Elasticsearch 7
- The official helm repo was changed to the official Elasticsearch repo (https://helm.elastic.co/)

1.0.0
------------------

#### Features
- Deploy SkyWalking by Chart
- Elasticsearch deploy optional
