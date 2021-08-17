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
| `oap.image.tag` | the OAP docker image tag | `8.1.0-es6`, `8.1.0-es7`, etc. |
| `oap.storageType` | the storage type of the OAP | `elasticsearch`, `elasticsearch7`, etc. |
| `ui.image.tag` | the UI docker image tag | `8.0.1`, `8.1.0`, ect. |

You can set these required values via command line (e.g. `--set oap.image.tag=8.1.0-es6 --set oap.storageType=elasticsearch`),
or edit them in a separate file(e.g. [`values-es6.yaml`](chart/skywalking/values-es6.yaml), [`values-es7.yaml`](chart/skywalking/values-es7.yaml))
and use `-f <filename>` or `--values=<filename>` to set them.

# Install

Let's set some variables for convenient use later.

```shell
export SKYWALKING_RELEASE_NAME=skywalking  # change the release name according to your scenario
export SKYWALKING_RELEASE_NAMESPACE=default  # change the namespace to where you want to install SkyWalking
```

## Install released version using Helm repository

```shell
export REPO=skywalking
helm repo add ${REPO} https://apache.jfrog.io/artifactory/skywalking-helm                                
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=8.0.1-es6 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=8.0.1 \
  --set elasticsearch.imageTag=6.8.6
```

## Install development version using master branch

This is needed **only** when you want to install from master branch.

```shell script
export REPO=chart
git clone https://github.com/apache/skywalking-kubernetes
cd skywalking-kubernetes
helm repo add elastic https://helm.elastic.co
helm dep up ${REPO}/skywalking
```

## Install a specific version of SkyWalking & Elasticsearch

In theory, you can deploy all versions of SkyWalking that are >= 6.0.0-GA, by specifying the desired `oap.image.tag`/`ui.image.tag`.

Please note that some configurations that are added in the later versions of SkyWalking may not work in earlier versions, and thus if you
specify those configurations, they may take no effect.

here are some examples. 

- Deploy SkyWalking 8.0.1 & Elasticsearch 6.8.6

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=8.0.1-es6 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=8.0.1 \
  --set elasticsearch.imageTag=6.8.6
```

- Deploy SkyWalking 8.1.0 & Elasticsearch 7.5.1
```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=8.1.0-es7 \
  --set oap.storageType=elasticsearch7 \
  --set ui.image.tag=8.1.0 \
  --set elasticsearch.imageTag=7.5.1
``` 

- Deploy SkyWalking 6.6.0 with Elasticsearch 7

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=6.6.0-es7 \
  --set oap.storageType=elasticsearch7 \
  --set ui.image.tag=6.6.0
```

- Deploy SkyWalking 6.5.0

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=6.5.0 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=6.5.0
```

**NOTE**: Please make sure the specified OAP image tag supports the specified Elasticsearch version. 

## Install a specific version of SkyWalking with an existing Elasticsearch

Modify the connection information to the existing elasticsearch cluster in file [`values-my-es.yaml`](chart/skywalking/values-my-es.yaml).

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" ${REPO}/skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  -f ./skywalking/values-my-es.yaml
```

## Customization

- Use your own configuration files

Put your own configuration files according to [the overridable files](chart/skywalking/files/conf.d/README.md) under the
working directory, `files/conf.d`, they will override the counterparts in the Docker image.

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
