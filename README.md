Apache SkyWalking Kubernetes
==========

<img src="http://skywalking.apache.org/assets/logo.svg" alt="Sky Walking logo" height="90px" align="right" />

[![GitHub stars](https://img.shields.io/github/stars/apache/skywalking.svg?style=for-the-badge&label=Stars&logo=github)](https://github.com/apache/skywalking)
[![Twitter Follow](https://img.shields.io/twitter/follow/asfskywalking.svg?style=for-the-badge&label=Follow&logo=twitter)](https://twitter.com/AsfSkyWalking)

SkyWalking Kubernetes repository provides ways to install and configure SkyWalking in a Kubernetes cluster.
The scripts are written in Helm 3.

## Documentation

### Chart Detailed Configuration

Chart detailed configuration can be found at [Chart Readme](./chart/skywalking/README.md)

### Deploy SkyWalking in a Kubernetes cluster

There are required values that you must set explicitly when deploying SkyWalking.

| name | description | example |
| ---- | ----------- | ------- |
| `oap.image.tag` | the OAP docker image tag | `8.1.0-es6`, `8.1.0-es7`, etc. |
| `oap.storageType` | the storage type of the OAP | `elasticsearch`, `elasticsearch7`, etc. |
| `ui.image.tag` | the UI docker image tag | `8.1.0`, `8.1.0`, ect. |

You can set these required values via command line (e.g. `--set oap.image.tag=8.1.0-es6 --set oap.storageType=elasticsearch`),
or edit them in a separate file(e.g. [`values-es6.yaml`](chart/skywalking/values-es6.yaml), [`values-es7.yaml`](chart/skywalking/values-es7.yaml))
and use `-f <filename>` or `--values=<filename>`.

#### Prerequisites

```shell script
git clone https://github.com/apache/skywalking-kubernetes
cd skywalking-kubernetes/chart
helm repo add elastic https://helm.elastic.co
helm dep up skywalking
export SKYWALKING_RELEASE_NAME=skywalking  # change the release name according to your scenario
export SKYWALKING_RELEASE_NAMESPACE=default  # change the namespace according to your scenario
```

#### Deploy a specific version of SkyWalking & Elasticsearch

- Deploy SkyWalking 8.0.1 & Elasticsearch 6.8.6

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=8.0.1-es6 \
  --set oap.storageType=elasticsearch \
  --set ui.image.tag=8.0.1 \
  --set elasticsearch.imageTag=6.8.6
```

- Deploy SkyWalking 8.1.0 & Elasticsearch 7.5.1
```shell script
helm install "${SKYWALKING_RELEASE_NAME}" skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  --set oap.image.tag=8.1.0-es7 \
  --set oap.storageType=elasticsearch7 \
  --set ui.image.tag=8.1.0 \
  --set elasticsearch.imageTag=7.5.1
``` 

**NOTE**: Please make sure the specified OAP image tag supports the specified Elasticsearch version. 

#### Deploy a specific version of SkyWalking with an existing Elasticsearch

Modify the connection information to the existing elasticsearch cluster in file [`values-my-es.yaml`](chart/skywalking/values-my-es.yaml).

```shell script
helm install "${SKYWALKING_RELEASE_NAME}" skywalking -n "${SKYWALKING_RELEASE_NAMESPACE}" \
  -f ./skywalking/values-my-es.yaml
```

## Structure of repository

### helm-chart 

This is recommended as the best practice to deploy SkyWalking backend stack into kubernetes cluster. 

#### release chart table 
| SkyWalking version | Chart version |
| ------------------ | ------------- |
| 6.5.0              | 1.0.0         |
| 6.6.0              | 1.1.0         | 
| 7.0.0              | 2.0.0         | 
| 8.0.1              | 3.0.0         | 
| 8.1.0              | 3.1.0         | 

Please head to the [releases page](http://skywalking.apache.org/downloads/) to download a release of Apache SkyWalking.

Note:  The source code for the release chart matches the git tag.

#### old chart position table

| SkyWalking version | Chart position                                               |
| ------------------ | ------------------------------------------------------------ |
| 6.0.0-GA           | [6.0.0-GA](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm2/6.0.0-GA) |
| 6.1.0              | [6.1.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm2/6.1.0) |
| 6.3.0              | [6.3.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm3/6.3.0) |
| 6.4.0              | [6.4.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm3/6.4.0) |

Note:  The source code for old charts are in the **legacy-helm-chart** branch.

# Contact Us
* Submit an [issue](https://github.com/apache/skywalking/issues)
* Mail list: **dev@skywalking.apache.org**. Mail to `dev-subscribe@skywalking.apache.org`, follow the reply to subscribe the mail list.
* Join `skywalking` channel at [Apache Slack](https://join.slack.com/t/the-asf/shared_invite/enQtNzc2ODE3MjI1MDk1LTAyZGJmNTg1NWZhNmVmOWZjMjA2MGUyOGY4MjE5ZGUwOTQxY2Q3MDBmNTM5YTllNGU4M2QyMzQ4M2U4ZjQ5YmY). If the link is not working, find the latest one at [Apache INFRA WIKI](https://cwiki.apache.org/confluence/display/INFRA/Slack+Guest+Invites).
* QQ Group: 392443393(2000/2000, not available), 901167865(available)

# LICENSE
Apache 2.0
