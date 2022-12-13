# Enable the experimental Cluster topology feature.
export CLUSTER_TOPOLOGY=true

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
kind create cluster --config kind-cluster-with-extramounts.yaml
clusterctl init --infrastructure docker

clusterctl generate cluster capi-quickstart --flavor development \
  --kubernetes-version v1.25.3 \
  --control-plane-machine-count=3 \
  --worker-machine-count=3 \
  > capi-quickstart.yaml

kubectl apply -f capi-quickstart.yaml
watch -n 1 kubectl get kubeadmcontrolplane
