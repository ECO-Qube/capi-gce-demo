kubectl create configmap calico-configmap --from-file=original-manifests/calico.yaml -o yaml --dry-run=client > calico-configmap.yaml
kubectl create configmap custom-metrics-configmap --from-file=original-manifests/custom-metrics-apiserver.yaml -o yaml --dry-run=client > custom-metrics-configmap.yaml
kubectl create configmap custom-metrics-tls-secret-configmap --from-file=original-manifests/custom-metrics-tls-secret.yaml -o yaml --dry-run=client > custom-metrics-tls-secret-configmap.yaml
kubectl create configmap prometheus-configmap --from-file=original-manifests/prometheus.yaml -o yaml --dry-run=client > prometheus-configmap.yaml
kubectl create configmap prometheus-node-exporter-configmap --from-file=original-manifests/prometheus-node-exporter.yaml -o yaml --dry-run=client > prometheus-node-exporter-configmap.yaml
kubectl create configmap scheduler-extender-configmap --from-file=original-manifests/extender.yaml -o yaml --dry-run=client > scheduler-extender-configmap.yaml
kubectl create configmap tas-tls-secret-configmap --from-file=original-manifests/tas-tls-secret.yaml -o yaml --dry-run=client > tas-tls-secret-configmap.yaml
kubectl create configmap tas-configmap --from-file=original-manifests/tas.yaml -o yaml --dry-run=client > tas-configmap.yaml