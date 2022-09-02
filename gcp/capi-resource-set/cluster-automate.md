# How to

The automation is majorly achieved by the [cluster resource set feature](https://cluster-api.sigs.k8s.io/tasks/experimental-features/experimental-features.html) of Cluster API.

### Gather Kubernetes Objects' Definition

For example:

- to install calico, you can download the Calico yaml manifest:

  ```Sh
  curl -L https://docs.projectcalico.org/manifests/calico.yaml -o calico.yaml
  ```

- to create name space, you can create a yaml config:

  ```Yaml
  ---
  kind: Namespace
  apiVersion: v1
  metadata:
    name: custom-metrics
    labels:
      name: custom-metrics
  ```

- for helm charts, render it locally:

  ```
  helm template helm/chart/dir --output-dir out/put/dir
  ```



### Generate Configmap

To make my life easier, I put relevant resources into a same yaml fie. Those files are in the [resource-original-definition folder](capi-resource-set/resource-original-definition). Next step will be convert those files to configmaps which will be applied to the mgmt cluster later.

```Sh
kubectl create configmap calico-configmap --from-file=resource-original-definition/calico.yaml -o yaml --dry-run=client > calico-configmap.yaml
```

I created a [shell script](capi-resource-set/convert-to-configmap) to automate this, since our aim is to automate everything :)

If there are other k8s objects need to be add, just put them in the resource-original-definition folder and edit the shell script (maybe someone can make this script more elegant)



### Create ClusterResourceSet

In order to make the mgmt cluster aware of how to apply the k8s objects, we need to create ClusterResourceSet to bind those objects with target cluster:

```Yaml
---
apiVersion: addons.cluster.x-k8s.io/v1alpha3
kind: ClusterResourceSet
metadata:
  name: calico
spec:
  clusterSelector:
    matchLabels:
      cni: calico 
  resources:
  - kind: ConfigMap
    name: calico-configmap
```

This [file](capi-resource-set/cluster-resource-sets) contains everything we need for the TAS cluster. For further added components, this file also need to be updated.

Besides, notice that the ClusterResourceSet will look for proper cluster by checking the Labels. Thus we need to tag the cluster with the same labels as described in the ClusterResourceSet definition.

You can either do it imperatively once the cluster is created:

```Sh
kubectl label cluster cluster-50 cni=calico
```

Or you can add the label tag in the cluster’s manifest:

```Yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: cluster-50
  labels:
    cni: calico
```

In ECO-Qube project we use Argo-CD. After change the cluster's manifest, it only take effects after delete and regenerate the current cluster.



### Last Step

Apply all the configmaps and the ClusterResourceSet to our mgmt cluster. It will take effect the next time when provisioning the target worker cluster.

```sh
kubectl apply -f capi-resource-set/
```







# Issues encountered

### webhook-error when using Experimental flags and multiple providers

The first time I applied the ClusterResourceSet to the cluster, I received the following errors: `failed calling webhook "default.clusterresourceset.addons.cluster.x-k8s.io"`and `failed calling webhook "default.machinepool.cluster.x-k8s.io"`.

It turns out that it is because the ClusterResourceSet is an experimental feature and is not turned on by default. To turn this feature on, one should:

Enable it features by setting OS environment variables before running `clusterctl init`, e.g.:

```Sh
export EXP_CLUSTER_RESOURCE_SET=true
clusterctl init --infrastructure gcp
```

Or, on existing management clusters, modify CAPI controller manager deployment which will restart all controllers with requested features.

```Sh
kubectl edit -n capi-system deployment.apps/capi-controller-manager
```

```
// Enable/disable available feautures by modifying Args below.
    Args:
      --leader-elect
      --feature-gates=MachinePool=true,ClusterResourceSet=true

```

Similarly, to **validate** if a particular feature is enabled, see cluster-api-provider deployment arguments by:

```sh
kubectl describe -n capi-system deployment.apps/capi-controller-manager
```



refer to this for more information: https://cluster-api.sigs.k8s.io/tasks/experimental-features/experimental-features.html



### Secret resources missing

At first, I copied the out put of the command `k get secrets cm-adapter-serving-certs -o yaml` and paste it to our static yaml configuration. It looks like:

```Yaml
apiVersion: v1
data:
  tls.crt: 8twe0age==
  tls.key: 0tLS0tCg==
kind: Secret
metadata:
  creationTimestamp: "2022-08-05T09:26:24Z"
  name: cm-adapter-serving-certs
  namespace: custom-metrics
  resourceVersion: "459"
  uid: 7b21d94f-f38f-4a73-86ad-c3da3f64ed6b
type: kubernetes.io/tls
```

However, this secret won't appear after cluster is provisioned. I solve this problem by deleting the `creationTimeStamp`, `resourceVersion` and the `uid` metadata in the definition. (Don't ask me why)

