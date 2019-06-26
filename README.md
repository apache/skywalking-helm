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

This is recommended as the best practice to deploy SkyWalking backend stack into kubernetes cluster. You can pick a 
 sub folder base on version your desired version.
