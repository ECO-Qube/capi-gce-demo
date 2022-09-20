# CAPI GCE Demo (development)

## TOC

- [CAPI GCE Demo (development)](#capi-gce-demo--development-)
    * [TOC](#toc)
    * [System architecture](#system-architecture)
    * [Goal](#goal)
    * [Infrastructure setup](#infrastructure-setup)
        + [Setting up CAPI on Azure](#setting-up-capi-on-azure)
        + [Setting up CAPI on GCP](#setting-up-capi-on-gcp)
        + [Setting up CAPI on OpenStack](#setting-up-capi-on-openstack)
        + [Setting up ArgoCD](#setting-up-argocd)
        + [Logging](#logging)
    * [Workload testing](#workload-testing)
        + [OpenFaaS](#openfaas)
    * [Issues encountered](#issues-encountered)
        + [SSH error while building the image](#ssh-error-while-building-the-image)
        + [Secret data is nil](#secret-data-is-nil)
        + [x509: certificate signed by unknown authority](#x509--certificate-signed-by-unknown-authority)
        + [Unable to sync Prometheus CRD in ArgoCD](#unable-to-sync-prometheus-crd-in-argocd)
        + [Sync error in ArgoCD: the server could not find the requested resource](#sync-error-in-argocd--the-server-could-not-find-the-requested-resource)
        + [Cannot find image on Azure](#cannot-find-image-on-azure)
        + [ArgoCD never fully syncs KubeAdmControlPlane resource](#argocd-never-fully-syncs-kubeadmcontrolplane-resource)
    * [Footnotes](#footnotes)
        + [Setting up OpenFaaS with Arkane](#setting-up-openfaas-with-arkane)
        + [Project links](#project-links)

<small><i><a href='http://ecotrust-canada.github.io/markdown-toc/'>Table of contents generated with markdown-toc</a></i></small>

## System architecture

![architecture_v1.png](https://git.helio.dev/eco-qube/doc/-/raw/main/artifacts/platform-architecture.png)

## Goal

- Deploy 3 nodes with Cluster API.
- Deploy some dummy workload (stress test).
- Telemetry Aware Scheduler (TAS) should schedule pods such that target is achieved as close as possible. If targets are
  all reached, incoming Pods should stay pending.
- TAS should be automatically deployed when a workload cluster is provisioned.

See also on Notion:

- [DevOps architecture](https://www.notion.so/helioag/DevOps-architecture-f871d3766f604a04ab42917cd4d73322)
- [Workload testing](https://www.notion.so/helioag/Workload-testing-ad6ec3a70e4b4772b016bc8c6c125984)

## Infrastructure setup

### Setting up CAPI on Azure

Go to [link](azure/README.md)

### Setting up CAPI on GCP

Go to [link](gcp/README-automated.md).

### Setting up CAPI on OpenStack

Go to [link](openstack/README.md)

### Setting up ArgoCD

In the management cluster:

```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Install ArgoCD CLI using your preferred package manager.

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

Add the private repository (**currently not working due to `unexpected 302 status code` with our GitLab instance, so
using a private one until fixed**):
Note that Gitlab needs the `.git` suffix.

```
argocd repo add https://gitlab.com/eco-qube/capi-gce-demo-argocd.git --username <your_username> --password <your_access_token>
```

Clone the ArgoCD repository and `cd` in it: https://gitlab.com/eco-qube/capi-gce-demo-argocd.git

Deploy the workload cluster through CAPI's resources by applying the `Application` resource in the management cluster:

```
kubectl apply -f apps/scheduling-dev-wkld-app.yaml
```

> [This little operator](https://github.com/a1tan/argocdsecretsynchronizer) might be useful for handling workload clusters automatically after creation with ArgoCD. Basically it replaces `argocd cluster add`. CNI installation could possibly be done automatically as well.

Allow up to 10 minutes to wait for `initialized` as explained before. Afterwards, install the CNI in the newly created
workload cluster:

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

To add the workload cluster to ArgoCD and deploy stuff there, first merge the two kubeconfigs:

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

Now it is possible to check the server IP with `argocd cluster list` and set the corresponding URL in
the `spec.destination.server` field of `Application` resources!

### Logging

Apply the Applications related to `kube-prometheus-stack` from the manifests repository. There are two applications
because of
[this issue](#unable-to-sync-prometheus-crd-in-argocd).

```
kubectl apply -f apps/kube-prometheus-stack-crds.yaml 
kubectl apply -f apps/kube-prometheus-stack.yaml 

```

Port-forward Grafana (in the workload cluster)

```
kubectl port-forward -n logging deployment/kube-prometheus-stack-grafana 3000
```

Username is `admin` and password is `prom-operator`

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
kubectl -n openfaas get secret basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode
```

Next tasks:

- Check monitoring for OpenFaaS function runs
- Play around with CPU limits, create a set of workloads (research how to do this)

## Issues encountered

### SSH error while building the image

While building the image, unreachable error their offer rsa etc. from packer or ansible. Add this to `~/.ssh/config`:

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

This is most likely correlated with **image versions**. The built image version need to be the same for management and
workload clusters (maybe also bootstrap cluster, haven't checked but there is a config that can be used to create the
kind cluster with a given version in this document).

### x509: certificate signed by unknown authority

Regenerate the kubeconfig with `clusterctl get kubeconfig <cluster_name> > <cluster_name>.kubeconfig`

### Unable to sync Prometheus CRD in ArgoCD

At this time (27.05.22) there's an [open issue](https://github.com/prometheus-operator/prometheus-operator/issues/4439)
about this. The reason is that a certain field is too long and therefore will generate an error in ArgoCD. To fix this,
CRDs can be applied
[separately](https://github.com/prometheus-operator/prometheus-operator/issues/4439#issuecomment-1030198014)
with `Replace=True`. See the manifests repository to check this out. See also
[how we handle this in Helio's infrastructure](https://git.helio.dev/helio/IaC/argocd/-/commit/193484292a1c1fc7a7ba1c2efece1a8f6138a12e)
for a vendored chart.

### Sync error in ArgoCD: the server could not find the requested resource

Apparentely ArgoCD does not install the Application CRD in workload clusters. We have to apply the resource ourselves in
the workload cluster:

```
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/crds/application-crd.yaml
```

See also: https://github.com/IBM/sample-app-gitops/issues/6

It might also complain that there is no namespace present, so still in the workload cluster you should create the
namespace of the Application resources.

### Cannot find image on Azure

See the available images here:

```
az vm image list --publisher cncf-upstream --offer capi --all -o table
```

### ArgoCD never fully syncs KubeAdmControlPlane resource

This is most likely due to Go parsing of Time types. When you specify a timeout like this `20m` Kubernetes will
translate it to `20m0s`. ArgoCD does not know this about this step, so it will just try to match desired and actual
timeouts as if they were normal strings and not Time. To solve this just set ``timeoutForControlPlane: 20m0s``.

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
- Relevant DevOps platform Notion
  page: https://www.notion.so/helioag/DevOps-architecture-f871d3766f604a04ab42917cd4d73322
- EcoQube slack channel: https://helioag.slack.com/archives/C038Q6WA3FH
- ArgoCD manifests repository: https://git.helio.dev/eco-qube/capi-gce-demo-argocd

TODO: Add code repositories, once created.
