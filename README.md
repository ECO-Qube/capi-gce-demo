# capi-gke-demo

## Goal

- Deploy 3 nodes with Cluster API on GKE
- Deploy some dummy workload e.g. webserver

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
export CLUSTER_NAME="cluster-demo"
export GOOGLE_APPLICATION_CREDENTIALS="<your key>"
export GCP_PROJECT_ID="k8s-ecoqube-development"

export GCP_PROJECT="k8s-ecoqube-development"
export GCP_B64ENCODED_CREDENTIALS=$( cat <your key> | base64 | tr -d '\n' )
export IMAGE_ID="projects/k8s-ecoqube-development/global/images/cluster-api-ubuntu-1804-v1-21-10-1652204960"
```

Init local temporary bootstrap cluster

```
kind create cluster --config bootstrap-kind-config.yaml
kubectl cluster-info
```

Provision management cluster

```
clusterctl init --infrastructure gcp
```

Generate Cluster API config

```
clusterctl generate cluster capi-quickstart \
  --kubernetes-version v1.21.10 \
  --control-plane-machine-count=1 \
  --worker-machine-count=1 \
  > capi-quickstart.yaml
```

Apply config

```
kubectl apply -f capi-quickstart.yaml
```

Wait until the control plane is up and running using the following ("initialized" must be true) ```kubectl get kubeadmcontrolplane```,
then deploy CNI

```
clusterctl get kubeconfig capi-quickstart > capi-quickstart.kubeconfig
kubectl --kubeconfig=./capi-quickstart.kubeconfig \
  apply -f https://docs.projectcalico.org/v3.21/manifests/calico.yaml
```

Check if worker nodes are running on GCP through `kubectl --kubeconfig=./capi-quickstart.kubeconfig get nodes` or the console.

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
