kubectl create configmap calico-configmap --from-file=resource-original-definition/calico.yaml -o yaml --dry-run=client > calico-configmap.yaml
kubectl create configmap custom-metrics-configmap --from-file=resource-original-definition/custom-metrics-apiserver.yaml -o yaml --dry-run=client > custom-metrics-configmap.yaml
kubectl create configmap prometheus-configmap --from-file=resource-original-definition/prometheus.yaml -o yaml --dry-run=client > prometheus-configmap.yaml
kubectl create configmap prometheus-node-exporter-configmap --from-file=resource-original-definition/prometheus-node-exporter.yaml -o yaml --dry-run=client > prometheus-node-exporter-configmap.yaml
kubectl create configmap scheduler-extender-configmap --from-file=resource-original-definition/extender.yaml -o yaml --dry-run=client > scheduler-extender-configmap.yaml
