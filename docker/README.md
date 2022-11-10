## Setting up Cluster API on Docker 

### Setting up Cluster API on KinD/Docker

From https://cluster-api.sigs.k8s.io/user/quick-start.html

Run the following command to create a kind config file for allowing the Docker provider to access Docker on the host:

```bash
cat > kind-cluster-with-extramounts.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
    - hostPath: /var/run/docker.sock
      containerPath: /var/run/docker.sock
EOF
```

Environment variables to set

```bash
# Enable the experimental Cluster topology feature.
export CLUSTER_TOPOLOGY=true

# Enable ClusterResourceSet experimental feature
export EXP_CLUSTER_RESOURCE_SET=true
```

The Docker provider does not require additional configurations for cluster templates, however things like CIDRs and 
Service Domain name are configurable so check out the quickstart if necessary.

Init the provider:

```bash
clusterctl init --infrastructure docker
```

Generate the cluster YAML configs:

```bash
clusterctl generate cluster capi-quickstart --flavor development \
  --kubernetes-version v1.25.0 \
  --control-plane-machine-count=1 \
  --worker-machine-count=3 \
  > capi-quickstart.yam
```

Modify the yaml with your desired config. When ready:

```bash
kubectl apply -f capi-quickstart.yaml
```

Wait until the control plane is up and running using the following command:

```watch -n 1 kubectl get kubeadmcontrolplane```, then get kubeconfig:

Wait for `INITIALIZED` being set to true. Afterwards, get kubeconfig:

```bash
clusterctl get kubeconfig capi-quickstart > capi-quickstart.kubeconfig
```

Important detail for Linux and macOS users: [you'll need an extra step to get the kubeconfig right](https://cluster-api.sigs.k8s.io/clusterctl/developers.html#additional-notes-for-the-docker-provider). Execute this to point
to the right address for connecting to the cluster, else you'll get a connection refused error:

```bash
# Point the kubeconfig to the exposed port of the load balancer, rather than the inaccessible container IP.
sed -i -e "s/server:.*/server: https:\/\/$(docker port capi-quickstart-lb 6443/tcp | sed "s/0.0.0.0/127.0.0.1/")/g" ./capi-quickstart.kubeconfig
```

Then install CNI solution:

```bash
kubectl --kubeconfig=./capi-quickstart.kubeconfig \
  apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.1/manifests/calico.yaml
```

Check again if control plane is ready (`API SERVER AVAILABLE` should be set to true):

```bash
watch -n 1 kubectl get kubeadmcontrolplane
```

Check nodes for Ready status:

```bash
kubectl --kubeconfig=./capi-quickstart.kubeconfig get nodes
```

