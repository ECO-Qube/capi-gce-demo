# CAPI GCE Demo (development)

## TOC

- [CAPI GCE Demo (development)](#capi-gce-demo--development-)
  * [TOC](#toc)
  * [System architecture](#system-architecture)
  * [Goal](#goal)
  * [Support infrastructure](#support-infrastructure)
    + [Building the image](#building-the-image)
    + [Setting up Cluster API](#setting-up-cluster-api)
      - [Deploy management cluster on GCP (production setup)](#deploy-management-cluster-on-gcp--production-setup-)
    + [Setting up ArgoCD](#setting-up-argocd)
    + [Logging](#logging)
  * [Workload testing](#workload-testing)
    + [OpenFaaS](#openfaas)
  * [Issues encountered](#issues-encountered)
    + [SSH error while building the image](#ssh-error-while-building-the-image)
    + [Secret data is nil](#secret-data-is-nil)
    + [x509: certificate signed by unknown authority](#x509--certificate-signed-by-unknown-authority)
    + [Unable to sync Prometheus CRD in ArgoCD](#unable-to-sync-prometheus-crd-in-argocd)
  * [Footnotes](#footnotes)
    + [Setting up OpenFaaS with Arkane](#setting-up-openfaas-with-arkane)
    + [Project links](#project-links)

<small><i><a href='http://ecotrust-canada.github.io/markdown-toc/'>Table of contents generated with markdown-toc</a></i></small>


## System architecture

![architecture_v1.png](https://git.helio.dev/eco-qube/doc/-/raw/main/drawio/platform-architecture-v1.png)


## Goal

- Deploy 3 nodes with Cluster API on GCE
- Deploy some dummy workload e.g. webserver

See also on Notion: 

- [DevOps architecture](https://www.notion.so/helioag/DevOps-architecture-f871d3766f604a04ab42917cd4d73322)
- [Workload testing](https://www.notion.so/helioag/Workload-testing-ad6ec3a70e4b4772b016bc8c6c125984)

## Support infrastructure
### Building the image

GCP does not provide pre-built images for nodes unlike some other providers such
as AWS. Therefore, follow this to build the image:

https://github.com/kubernetes-sigs/cluster-api-provider-gcp/blob/main/docs/book/src/topics/prerequisites.md

Don't clean up router and nat otherwise it would not be possible to reach the
VMs from the extern.

### Setting up Cluster API

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

Check if worker nodes are running on GCP through `kubectl --kubeconfig=./scheduling-dev-mgmt.kubeconfig get nodes` or the console.

#### Deploy management cluster on GCP (production setup)

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

> Don't apply the workload cluster directly when setting up ArgoCD, workload clusters will be managed mostly
by ArgoCD. Jump directly to the next section for ArgoCD set up. 

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

Allow up to 10 minutes to wait for `initialized` as explained before.
Afterwards, install the CNI in the newly created workload cluster:

```
clusterctl get kubeconfig scheduling-dev-wkld > scheduling-dev-wkld.kubeconfig
kubectl --kubeconfig=./scheduling-dev-wkld.kubeconfig \
  apply -f https://docs.projectcalico.org/v3.21/manifests/calico.yaml
```

Check that the two control planes are up and running

```
kubectl get kubeadmcontrolplane
```

### Setting up ArgoCD

In the management cluster:

```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Install ArgoCD using your preferred package manager.

Allow ArgoCD to be reachable from your machine:

```
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Get ArgoCD credentials (username is `admin`) and login:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
argocd login localhost:8080
```

Create an Access Token (better if project-scoped) with all the rights and copy it.

Add the private repository (**currently not working due to `unexpected 302 status code` with our GitLab instance, so using a private one until fixed**):

```
argocd repo add https://gitlab.com/eco-qube/capi-gce-demo-argocd.git --username <your_username> --password <your_access_token>
```

Clone the ArgoCD repository and `cd` in it: https://gitlab.com/eco-qube/capi-gce-demo-argocd.git


Deploy the workload cluster through CAPI's resources by applying the `Application` resource in the management cluster:

```
kubectl apply -f apps/scheduling-dev-wkld-app.yaml
```

> [This little operator](https://github.com/a1tan/argocdsecretsynchronizer) might be useful for handling workload clusters automatically after creation with ArgoCD. Basically it replaces `argocd cluster add`. CNI installation could possibly be done automatically as well.

Allow up to 10 minutes to wait for `initialized` as explained before.
Afterwards, install the CNI in the newly created workload cluster:

> I had a couple of times "initialized" not set to true but after installing CNI
> the cluster was working... if it's not initialized EVEN after 10 minutes just
> install the CNI. Be careful not to wait more than 20 minutes or
> `Kubeadmcontolplane` will time out.

```
clusterctl get kubeconfig scheduling-dev-wkld > scheduling-dev-wkld.kubeconfig
kubectl --kubeconfig=./scheduling-dev-wkld.kubeconfig \
  apply -f https://docs.projectcalico.org/v3.21/manifests/calico.yaml
```

Check that the two control planes are up and running:

```
kubectl get kubeadmcontrolplane
```

To add the workload cluster to ArgoCD and deploy stuff there, first
merge the two kubeconfigs:

```
KUBECONFIG=./scheduling-dev-mgmt.kubeconfig:scheduling-dev-wkld.kubeconfig kubectl config view --flatten > scheduling-dev.kubeconfig
export KUBECONFIG=$(pwd)/scheduling-dev.kubeconfig
```

check that both clusters are now shown with kubectl:

```
kubectl config get-contexts -o name
```

Add the workload cluster to ArgoCD:

```
argocd cluster add scheduling-dev-wkld-admin@scheduling-dev-wkld
```

Now it is possible to check the server IP with `argocd cluster list` and set
the corresponding URL in the `spec.destination.server` field of `Application` resources!

### Logging

Apply the Applications related to `kube-prometheus-stack` from the manifests
repository. There are two applications because of
[this issue](#unable-to-sync-prometheus-crd-in-argocd).

Port-forward Grafana (in the workload cluster)

```
kubectl port-forward -n logging deployment/kube-prometheus-stack-grafana 3000
```

Username is `admin` and password is ` 

## Workload testing

### OpenFaaS

Apply the Applications related `openfaas` from the manifests repository.

> One thing that is not clear yet is that its Helm chart deploys Prometheus and 
> Alertmanager with lots of configuration, so making it work with the preexisting
> `kube-prometheus-stack` is unclear at the moment. 

> Another issue is that the Helm chart does not create the `openfaas-fn` namespace,
> so there is a manual step before installing the chart that should be undertaken.
> To solve this I can only imagine either creating a chart wrapping the original
> OpenFaaS chart and add a namespace resource to the installation, or vendor
> the original chart and add a namespace resource. The simplest thing
> done now is to designate `openfaas` as the namespace for the function. As a downside
> functions and infrastructural resources will be mixed in the same namespace.

Port forward:

```
kubectl port-forward -n openfaas svc/gateway 8090:8080
```

Connect to `localhost:8090`

Username is `admin`, password is retrieved like this:

```
kubectl -n openfaas get secret basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode)
```

Next tasks:
- Check monitoring for OpenFaaS function runs
- Play around with CPU limits, create a set of workloads (research how to do this)

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


### x509: certificate signed by unknown authority

Regenerate the kubeconfig with `clusterctl get kubeconfig <cluster_name> > <cluster_name>.kubeconfig`


### Unable to sync Prometheus CRD in ArgoCD

At this time (27.05.22) there's an [open
issue](https://github.com/prometheus-operator/prometheus-operator/issues/4439)
about this. The reason is that a certain field is too long and therefore will
generate an error in ArgoCD. To fix this, CRDs can be applied
[separately](https://github.com/prometheus-operator/prometheus-operator/issues/4439#issuecomment-1030198014)
with `Replace=True`. See the manifests repository to check this out. See also
[how we handle this in Helio's
infrastructure](https://git.helio.dev/helio/IaC/argocd/-/commit/193484292a1c1fc7a7ba1c2efece1a8f6138a12e)
for a vendored chart.


### Sync error in ArgoCD: the server could not find the requested resource

Apparentely ArgoCD does not install the Application CRD in workload clusters.
We have to apply the resource ourselves in the workload cluster:

```
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/crds/application-crd.yaml
```

See also: https://github.com/IBM/sample-app-gitops/issues/6

It might also complain that there is no namespace present, so still in the workload
cluster you should create the namespace of the Application resources.

## Footnotes
### Setting up OpenFaaS with Arkane

> Note: only for local development, use ArgoCD + Helm.

See: https://docs.openfaas.com/deployment/kubernetes/

In the workload cluster, install OpenFaaS through their extra nice tool:

```
arkade install openfaas
arkade info openfaas
```

Port forward the gateway service

```
kubectl port-forward -n openfaas svc/gateway-external 31112:8080
```
### Project links
- EcoQube on Notion: https://www.notion.so/helioag/ECO-Qube-c4807270586240bcafaa71959db42b75
- Relevant DevOps platform Notion page: https://www.notion.so/helioag/DevOps-architecture-f871d3766f604a04ab42917cd4d73322
- EcoQube slack channel: https://helioag.slack.com/archives/C038Q6WA3FH
- ArgoCD manifests repository: https://git.helio.dev/eco-qube/capi-gce-demo-argocd

TODO: Add code repositories, once created.
