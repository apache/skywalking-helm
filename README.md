Apache SkyWalking Kubernetes
==========

# Deploy SkyWalking backend to Kubernetes cluster

To install and configure skywalking in a Kubernetes cluster, follow these instructions.

## Structure of repository

### archive

Prior to 6.0.0-GA, only kubernetes YAMLs as examples for users and should be modified to fix real kuberentes enviroment, 
for instance, resources, volume claims.

Now, these YAMLs are archived in the repository, that means we never maintain them, but users still could use them.

We recommend using __helm-chart__ as your first choice.

### helm-chart 

This is recommended as the best practice to deploy SkyWalking backend stack into kubernetes cluster. 

#### old chart position table

| SkyWalking version | Chart position                                               |
| ------------------ | ------------------------------------------------------------ |
| 6.0.0-GA           | [6.0.0-GA](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm2/6.0.0-GA) |
| 6.1.0              | [6.1.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm2/6.1.0) |
| 6.3.0              | [6.3.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm3/6.3.0) |
| 6.4.0              | [6.4.0](https://github.com/apache/skywalking-kubernetes/tree/legacy-helm-chart/helm-chart/helm3/6.4.0) |

Note:  The source code for old charts are in the **legacy-helm-chart** branch.

#### release chart table 
| SkyWalking version | Chart version |
| ------------------ | ------------- |
| 6.5.0              | 1.0.0         |

Note:  The source code for the release chart is located in the chart folder in the master branch.