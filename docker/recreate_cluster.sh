# Enable the experimental Cluster topology feature.
export CLUSTER_TOPOLOGY=true
# Enable ClusterResourceSet experimental feature
export EXP_CLUSTER_RESOURCE_SET=true

cat > kind-cluster-with-extramounts.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
    - hostPath: /var/run/docker.sock
      containerPath: /var/run/docker.sock
EOF

kind delete cluster
# Clean up docker containers of nodes
docker ps --filter name="ecoqube*" -aq | xargs docker stop | xargs docker rm
kind create cluster --config kind-cluster-with-extramounts.yaml --image kindest/node:v1.26.3 && clusterctl init --infrastructure docker

# USE EXISTING ONE
  #clusterctl generate cluster capi-quickstart --flavor development \
  #  --kubernetes-version v1.25.0 \
  #  --control-plane-machine-count=1 \
  #  --worker-machine-count=3 \
  #  > capi-quickstart.yaml
kubectl apply -f 'capi-resource-set/manifests/*-configmap.yaml'
sleep 5
kubectl apply -f clusterresourcesets.yaml
sleep 5
kubectl apply -f ecoqube-dev.yaml
sleep 5
kubectl apply -f ecoqube-dev-cluster.yaml

#until watch -n 1 kubectl get kubeadmcontrolplane
# TODO: To fix (there should be two "true" in the output eventually)
#until watch -n 1 kubectl get kubeadmcontrolplane  | grep -m 1 "INITIALIZED"; do sleep 1 ; done

clusterctl get kubeconfig ecoqube-dev > ecoqube-dev.kubeconfig
# note now you need to copy-paste the kubeconfig as it is in the backend before executing the sed command below
# in charts/target-exporter/ecoqube-dev.kubeconfig
# cp /home/criscola/IdeaProjects/helio/cluster-api-infrastructure/docker/ecoqube-dev.kubeconfig /home/criscola/IdeaProjects/helio/target-exporter/charts/target-exporter/ecoqube-dev.kubeconfig
# note: seems like sed command not needed anymore?
sed -i -e "s/server:.*/server: https:\/\/$(docker port ecoqube-dev-lb 6443/tcp | sed "s/0.0.0.0/127.0.0.1/")/g" ./ecoqube-dev.kubeconfig
# then update node names k get nodes and copy-paste to config.yaml in target-exporter
# then port-forward prometheus e.g. kubectl port-forward -n monitoring prometheus-deployment-74c5c98775-466pl 9090:9090
#