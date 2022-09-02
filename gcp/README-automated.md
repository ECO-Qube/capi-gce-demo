### Setting up Cluster API on GCP

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
export GOOGLE_APPLICATION_CREDENTIALS="/home/criscola/IdeaProjects/helio/k8s-ecoqube-development-668c8628bd09.json"
export GCP_PROJECT_ID="k8s-ecoqube-development"

export GCP_PROJECT="k8s-ecoqube-development"
export GCP_B64ENCODED_CREDENTIALS=$( cat /home/criscola/IdeaProjects/helio/k8s-ecoqube-development-668c8628bd09.json | base64 | tr -d '\n' )
export IMAGE_ID="projects/k8s-ecoqube-development/global/images/cluster-api-ubuntu-1804-v1-21-10-1652204960"

# Enable ClusterResourceSet experimental feature
export EXP_CLUSTER_RESOURCE_SET=true
```

Init local temporary bootstrap cluster

```
kind create cluster --config bootstrap-kind-config-gcp.yaml
kubectl cluster-info
```

Provision temporary management cluster

```
clusterctl init --infrastructure gcp
```

Generate Cluster API config (only for doc purposes, see below note)

> Note: the definitions are already created and present in a single file `scheduling-dev-mgmt.yaml`, please use this one
> instead of generating the resources yourself.

```bash
clusterctl generate cluster scheduling-dev-mgmt \
  --kubernetes-version v1.21.10 \
  --control-plane-machine-count=1 \
  --worker-machine-count=1 \
  > scheduling-dev-mgmt.yaml
```

Add ConfigMap and the relative ClusterResourceSet resources to install the CNI automatically.

Apply config

```
kubectl apply -f scheduling-dev-mgmt.yaml
```

Wait until the control plane is up and running using the following (INITIALIZED API SERVER and AVAILABLE must be true,
wait up to 10 minutes)

```watch -n 1 kubectl get kubeadmcontrolplane```, then get kubeconfig:

```
clusterctl get kubeconfig scheduling-dev-mgmt > scheduling-dev-mgmt.kubeconfig
```

Check if worker nodes are running on GCP through `kubectl --kubeconfig=./scheduling-dev-mgmt.kubeconfig get nodes` or
the console.

#### Deploy management cluster on GCP (production setup)

To deploy the management cluster on GCP as well (production setup), it is necessary to:

1. Rerun the cluster initialization with the GCP provider **in the newly created cluster**.
3. Move the resources with `clusterctl move` (see also
   https://cluster-api.sigs.k8s.io/clusterctl/commands/move.html) from the temporary bootstrap/management cluster to the
   newly created cluster. This will
   **promote it to management cluster**.
4. Decommission the temporary bootstrap/management cluster.
5. Set the kubeconfig to point to the promoted management cluster.
6. Create workload clusters as desired.

Here are the steps:

Make sure your selected kubeconfig is the one of the **bootstrap** cluster (should be `kind-kind` and already selected).

Prepare the cluster to become a management cluster by running:

```
clusterctl init --kubeconfig=$(pwd)/scheduling-dev-mgmt.kubeconfig --infrastructure gcp
```

Move the management cluster to the newly created cluster on GCP (workload cluster will become the management cluster):

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

Decommission the temporary cluster and select new config:

```
kind delete cluster
export KUBECONFIG=$(pwd)/scheduling-dev-mgmt.kubeconfig
```

Create a workload cluster:

> Note: the definitions are already created and present in a single file `scheduling-dev-wkld.yaml`, please use this one
> instead of generating the config yourself.

```
clusterctl generate cluster scheduling-dev-wkld \
  --kubernetes-version v1.21.10 \
  --control-plane-machine-count=1 \
  --worker-machine-count=3 \
  > scheduling-dev-wkld.yaml
```

then follow [this guide](capi-resource-set/cluster-automate.md) to create the config related to the ClusterResourceSets
and automatically provision CNI and Scheduler at cluster initialization.

Finally, apply the config:

```
export KUBECONFIG=$(pwd)/scheduling-dev-mgmt.kubeconfig
kubectl apply -f scheduling-dev-wkld.yaml
```

Allow up to 10 minutes to wait for INITIALIZED and API SERVER AVAILABLE to become true, as explained
before (```watch -n 1 kubectl get kubeadmcontrolplane```). Afterwards, generate kubeconfig:

```
clusterctl get kubeconfig scheduling-dev-wkld > scheduling-dev-wkld.kubeconfig
```

Check that the two control planes are up and running

```
kubectl get kubeadmcontrolplane
```

You can merge the two kubeconfigs for convenience when using tools like `kubie` or `kubectx`

```
KUBECONFIG=./scheduling-dev-mgmt.kubeconfig:scheduling-dev-wkld.kubeconfig kubectl config view --flatten > scheduling-dev.kubeconfig
export KUBECONFIG=$(pwd)/scheduling-dev.kubeconfig
```

then you need to install the target-exporter service, see [repo](https://git.helio.dev/eco-qube/target-exporter).