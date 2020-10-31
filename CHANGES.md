Changes by Version
==================
Release Notes.

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
