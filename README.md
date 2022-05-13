# capi-gce-demo

## Goal

- Deploy 3 nodes with Cluster API on GCE
- Deploy some dummy workload e.g. webserver

## Building the image

GCP does not provide pre-built images for nodes unlike some other providers such
as AWS. Therefore, follow this to build the image:

https://github.com/kubernetes-sigs/cluster-api-provider-gcp/blob/main/docs/book/src/topics/prerequisites.md

Don't clean up router and nat otherwise it would not be possible to reach the
VMs from the extern.

## Setting up Cluster API

From https://cluster-api.sigs.k8s.io/user/quick-start.html

Environment variables to set

```
export GCP_REGION="europe-west6"
export GCP_PROJECT="k8s-ecoqube-development"
# Make sure to use same kubernetes version here as building the GCE image
export KUBERNETES_VERSION=1.21.10
export GCP_CONTROL_PLANE_MACHINE_TYPE=n1-standard-2
export GCP_NODE_MACHINE_TYPE=n1-standard-2
export GCP_NETWORK_NAME=default
export CLUSTER_NAME="scheduling-dev-mgmt"
export GOOGLE_APPLICATION_CREDENTIALS="/home/criscola/IdeaProjects/helio/k8s-ecoqube-development-5abe3168f3ed.json"
export GCP_PROJECT_ID="k8s-ecoqube-development"

export GCP_PROJECT="k8s-ecoqube-development"
export GCP_B64ENCODED_CREDENTIALS=$( cat /home/criscola/IdeaProjects/helio/k8s-ecoqube-development-5abe3168f3ed.json | base64 | tr -d '\n' )
export IMAGE_ID="projects/k8s-ecoqube-development/global/images/cluster-api-ubuntu-1804-v1-21-10-1652204960"

```
Init local temporary bootstrap cluster

```
kind create cluster --config bootstrap-kind-config.yaml
kubectl cluster-info
```

Provision temporary management cluster

```
clusterctl init --infrastructure gcp
```

Generate Cluster API config

```
clusterctl generate cluster scheduling-dev-mgmt \
  --kubernetes-version v1.21.10 \
  --control-plane-machine-count=1 \
  --worker-machine-count=1 \
  > scheduling-dev-mgmt.yaml
```

Apply config

```
kubectl apply -f scheduling-dev-mgmt.yaml
```

Wait until the control plane is up and running using the following ("initialized" must be true) ```watch -n 1 kubectl get kubeadmcontrolplane```,
then deploy CNI

```
clusterctl get kubeconfig scheduling-dev-mgmt > scheduling-dev-mgmt.kubeconfig
kubectl --kubeconfig=./scheduling-dev-mgmt.kubeconfig \
  apply -f https://docs.projectcalico.org/v3.21/manifests/calico.yaml
```

Check if worker nodes are running on GCP through `kubectl --kubeconfig=./capi-quickstart.kubeconfig get nodes` or the console.

### Deploy management cluster on GCP (production setup)

To deploy the management cluster on GCP as well (production setup), it is necessary to:

1. Rerun the cluster initialization with the GCP provider **in the newly created
   cluster**.
3. Move the resources with `clusterctl move` (see also
   https://cluster-api.sigs.k8s.io/clusterctl/commands/move.html) from the
   temporary bootstrap/management cluster to the newly created cluster. This will
   **promote it to management cluster**.
4. Decomission the temporary bootstrap/management cluster.
5. Set the kubeconfig to point to the promoted management cluster.
6. Create workload clusters as desired.

Here are the steps:

Make sure your selected kubeconfig is the one of the bootstrap/management
cluster (should be `kind-kind` and already selected).

Prepare the cluster to become a management cluster by running:

```
clusterctl init --kubeconfig=$(pwd)/scheduling-dev-mgmt.kubeconfig --infrastructure gcp
```

Move the management cluster to the newly created cluster on GCP (workload
cluster will become the management cluster):

```
clusterctl move --to-kubeconfig=./scheduling-dev-mgmt.kubeconfig 
```

You should see something like this:

```
Performing move...
Discovering Cluster API objects
Moving Cluster API objects Clusters=1
Moving Cluster API objects ClusterClasses=0
Creating objects in the target cluster
Deleting objects from the source cluster
```

Decomission the temporary cluster:

```
kind delete cluster
```

Create a workload cluster:

```
export KUBECONFIG=$(pwd)/scheduling-dev-mgmt.kubeconfig
clusterctl generate cluster scheduling-dev-wkld \
  --kubernetes-version v1.21.10 \
  --control-plane-machine-count=1 \
  --worker-machine-count=1 \
  > scheduling-dev-wkld.yaml
kubectl apply -f scheduling-dev-wkld.yaml
```

You can go back to the previous steps and repeat them to 

WIP: I think the management cluster needs to have less resources like
the machine ones, as they are not needed and conceptually wrong to have like this.
The management cluster also needs to not have the kubeadm control plane etc.
because the management cluster should have it and handle the workload cluster
(would be cool to have two separate commands for generating the resources...)

## Setting up OpenFaaS

See: https://docs.openfaas.com/deployment/kubernetes/

Retrieve and set workload cluster Kubeconfig:

```
clusterctl get kubeconfig capi-quickstart > capi-quickstart.kubeconfig
export KUBECONFIG=$(pwd)/capi-quickstart.kubeconfig
```

Install OpenFaaS through their super nice tool:

```
arkade install openfaas
arkade info openfaas
```

Port forward the gateway service

```
kubectl port-forward -n openfaas svc/gateway-external 31112:8080
```

Connect to `localhost:31112`

## Issues encountered

### SSH error while building the image

While building the image, unreachable error their offer rsa etc. from packer or
ansible. Add this to `~/.ssh/config`:

```
Host 127.0.0.1
    PubkeyAcceptedAlgorithms +ssh-rsa
    HostkeyAlgorithms +ssh-rsa
```

### Secret data is nil

```
I0510 23:24:52.386997       1 reconcile.go:39] controller/gcpmachine "msg"="Reconciling instance resources" "name"="capi-quickstart-control-plane-ttgm9" "namespace"="default" "reconciler group"="infrastructure.cluster.x-k8s.io" "reconciler kind"="GCPMachine" 
E0510 23:24:52.387163       1 gcpmachine_controller.go:231] controller/gcpmachine "msg"="Error reconciling instance resources" "error"="failed to retrieve bootstrap data: error retrieving bootstrap data: linked Machine's bootstrap.dataSecretName is nil" "name"="capi-quickstart-md-0-ww676" "namespace"="default" "reconciler group"="infrastructure.cluster.x-k8s.io" "reconciler kind"="GCPMachine" 
E0510 23:24:52.387496       1 controller.go:317] controller/gcpmachine "msg"="Reconciler error" "error"="failed to retrieve bootstrap data: error retrieving bootstrap data: linked Machine's bootstrap.dataSecretName is nil" "name"="capi-quickstart-md-0-bn6zd" "namespace"="default" "reconciler group"="infrastructure.cluster.x-k8s.io" "reconciler kind"="GCPMachine" 
E0510 23:24:52.388371       1 controller.go:317] controller/gcpmachine "msg"="Reconciler error" "error"="failed to retrieve bootstrap data: error retrieving bootstrap data: linked Machine's bootstrap.dataSecretName is nil" "name"="capi-quickstart-md-0-ww676" "namespace"="default" "reconciler group"="infrastructure.cluster.x-k8s.io" "reconciler kind"="GCPMachine" 
I0510 23:24:52.939668       1 gcpmachine_controller.go:243] controller/gcpmachine "msg"="GCPMachine instance is running" "name"="capi-quickstart-control-plane-ttgm9" "namespace"="default" "reconciler group"="infrastructure.cluster.x-k8s.io" "reconciler kind"="GCPMachine" "instance-id"="capi-quickstart-control-plane-ttgm9"
```

This is most likely correlated with **image versions**. The built image version
need to be the same for management and workload clusters (maybe also bootstrap
cluster, haven't checked but there is a config that can be used to create the
kind cluster with a given version in this document). 