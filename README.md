Apache SkyWalking Kubernetes
==========

<img src="https://skywalking.apache.org/assets/logo.svg" alt="Sky Walking logo" height="90px" align="right" />

[![GitHub stars](https://img.shields.io/github/stars/apache/skywalking.svg?style=for-the-badge&label=Stars&logo=github)](https://github.com/apache/skywalking)
[![Twitter Follow](https://img.shields.io/twitter/follow/asfskywalking.svg?style=for-the-badge&label=Follow&logo=twitter)](https://twitter.com/AsfSkyWalking)

SkyWalking Kubernetes repository provides ways to install and configure SkyWalking in a Kubernetes cluster.
The scripts are written in Helm 3.

# Chart Detailed Configuration

Chart detailed configuration can be found at [Chart Readme](./chart/skywalking/README.md)

There are required values that you must set explicitly when deploying SkyWalking.

| name | description | example |
| ---- | ----------- | ------- |
| `oap.image.tag` | the OAP docker image tag | `9.2.0` |
| `oap.storageType` | the storage type of the OAP | `elasticsearch`, `postgresql`, etc. |
| `ui.image.tag` | the UI docker image tag | `9.2.0` |

You can set these required values via command line (e.g. `--set oap.image.tag=9.2.0 --set oap.storageType=elasticsearch`),
or edit them in a separate file(e.g. [`values.yaml`](chart/skywalking/values-es6.yaml), [`values-my-es.yaml`](chart/skywalking/values-my-es.yaml))
and use `-f <filename>` or `--values=<filename>` to set them.

# Install

Let's set some variables for convenient use later.

```shell
export SKYWALKING_RELEASE_VERSION=4.3.0  # change the release version according to your need
export SKYWALKING_RELEASE_NAME=skywalking  # change the release name according to your scenario
export SKYWALKING_RELEASE_NAMESPACE=default  # change the namespace to where you want to install SkyWalking
```

## Install released version using Docker Helm repository (>= 4.3.0)

```shell
helm install "${SKYWALKING_RELEASE_NAME}" \
  oci://registry-1.docker.io/apache/skywalking-helm \
  --version "${SKYWALKING_RELEASE_VERSION}" \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=9.2.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=9.2.0
```

## Install released version using Apache Jfrog Helm repository (<= 4.3.0)

```shell
export REPO=skywalking
helm repo add ${REPO} https://apache.jfrog.io/artifactory/skywalking-helm
```

## Install development version of SkyWalking using master branch

This is needed **only** when you want to install SkyWalking from master branch.

```shell script
export REPO=chart
git clone https://github.com/apache/skywalking-kubernetes
cd skywalking-kubernetes
helm repo add elastic https://helm.elastic.co
helm dep up ${REPO}/skywalking
```

## Install development version of SWCK Adapter using master branch

This is needed **only** when you want to install [SWCK Adapter](https://github.com/apache/skywalking-swck/tree/master/adapter) from master branch. 

SWCK Adapter chart detailed configuration can be found at [Adapter Chart Readme](./chart/adapter/README.md).

You can install the Adapter with the default configuration as follows.

```shell script
export REPO=chart
git clone https://github.com/apache/skywalking-kubernetes
cd skywalking-kubernetes
helm -n skywalking-custom-metrics-system install adapter ${REPO}/adapter --create-namespace
```

## Install development version of SWCK Operator using master branch

This is needed **only** when you want to install [SWCK Operator](https://github.com/apache/skywalking-swck/tree/master/operator) from master branch. 

Before installing Operator, you have to install [cert-manager](https://cert-manager.io/) at first.

```shell script
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml
```

SWCK Operator chart detailed configuration can be found at [Operator Chart Readme](./chart/operator/README.md).

You can install the Operator with the default configuration as follows.

```shell script
export REPO=chart
git clone https://github.com/apache/skywalking-kubernetes
cd skywalking-kubernetes
helm -n skywalking-swck-system install operator ${REPO}/operator
```

## Install a specific version of SkyWalking & Elasticsearch

In theory, you can deploy all versions of SkyWalking that are >= 6.0.0-GA, by specifying the desired `oap.image.tag`/`ui.image.tag`.

Please note that some configurations that are added in the later versions of SkyWalking may not work in earlier versions, and thus if you
specify those configurations, they may take no effect.

here are some examples.

- Deploy SkyWalking 9.2.0 & Elasticsearch 6.8.6

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=9.2.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=9.2.0
```

## Install development version using ghcr.io Helm repository

If you are willing to help testing the latest codes that are not released yet, we provided a snapshot
Helm repository on ghcr.io for convenient use, replace the full commit hash in the version option to
deploy the revision that you want to test.

```shell
helm -n istio-system install skywalking \
  oci://ghcr.io/apache/skywalking-kubernetes/skywalking-helm \
  --version "0.0.0-b670c41d94a82ddefcf466d54bab5c492d88d772" \
  -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=9.2.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=9.2.0
```

## Install development version using source codes

This is needed **only** when you want to install source codes.

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" 
```

## Install a specific version of SkyWalking with an existing Elasticsearch

Modify the connection information to the existing elasticsearch cluster in file [`values-my-es.yaml`](chart/skywalking/values-my-es.yaml).

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  -f ./skywalking/values-my-es.yaml
```

## Install SkyWalking with Satellite

Enable the satellite as gateway, and set the satellite image tag.

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set satellite.enabled=true \
  --set satellite.image.tag=v0.4.0
```

After satellite have been installed, you should replace the `oap` address to the `satellite` address, the address from agent or `istio`, such as `skywalking-satellite.istio-system:11800`.

## Customization

- Override configuration files

You can override the configuration files for OAP or Satellite by adding configuration section `oap.config` and `satellite.config`,
check [the examples](chart/skywalking/values.yaml), search keyword `config: {}`.

- Pass environment variables to OAP

The SkyWalking OAP exposes many configurations that can be specified by environment variables, as listed in [the main repo](https://github.com/apache/skywalking/blob/master/docs/en/setup/backend/configuration-vocabulary.md).
You can set those environment variables by `--set oap.env.<ENV_NAME>=<ENV_VALUE>`, such as `--set oap.env.SW_ENVOY_METRIC_ALS_HTTP_ANALYSIS=k8s-mesh`.

> The environment variables take priority over the overrode configuration files.

# Contact Us
* Submit an [issue](https://github.com/apache/skywalking/issues)
* Mail list: **dev@skywalking.apache.org**. Mail to `dev-subscribe@skywalking.apache.org`, follow the reply to subscribe the mail list.
* Join `skywalking` channel at [Apache Slack](https://join.slack.com/t/the-asf/shared_invite/enQtNzc2ODE3MjI1MDk1LTAyZGJmNTg1NWZhNmVmOWZjMjA2MGUyOGY4MjE5ZGUwOTQxY2Q3MDBmNTM5YTllNGU4M2QyMzQ4M2U4ZjQ5YmY). If the link is not working, find the latest one at [Apache INFRA WIKI](https://cwiki.apache.org/confluence/display/INFRA/Slack+Guest+Invites).
* QQ Group: 392443393(2000/2000, not available), 901167865(available)

# LICENSE
Apache 2.0
