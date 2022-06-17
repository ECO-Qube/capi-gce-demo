# Walk through

1. deploy a cluster with multiple nodes. If doing it locally, you can use k3d:

   ```sh
   k3d cluster create telementry-scheduling --agents 3
   ```

   

2.  install Node Exporter and Prometheus run:

   ```sh
   cd telemetry-aware-scheduling
   kubectl create namespace monitoring
   kubens monitoring
   helm install node-exporter deploy/charts/prometheus_node_exporter_helm_chart/
   helm install prometheus deploy/charts/prometheus_helm_chart/
   ```

   

3. Create the secret for the Prometheus adapter and install it:

   Information on how to generate correctly signed certs in kubernetes can be found [here](https://github.com/kubernetes-sigs/apiserver-builder-alpha/blob/master/docs/concepts/auth.md).

   ```sh
   kubectl create namespace custom-metrics
   kubectl -n custom-metrics create secret tls cm-adapter-serving-certs --cert=serving-ca.crt --key=serving-ca.key
   helm install prometheus-adapter deploy/charts/prometheus_custom_metrics_helm_chart/
   ```

   The Prometheus adapter may take some time to come online - but once it does running:
   ``kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | grep nodes | jq .``

   should return a number of metrics that are being collected by prometheus node exporter, scraped by prometheus and passed to the Kubernetes Metrics API by the Prometheus Adapter.

4. Providing the metrics:

   With our health metric the file at /tmp/node-metrics/test.prom (inside the worknode) should look like:

   ````node_health_metric 0````

   Any change in the value in the file will be read by the prometheus node exporter, and will propagate through the metrics pipeline and made accessible to TAS. 

   - To set the health metric on remote nodes we can use: 

     ```sh
     echo 'node_health_metric ' <METRIC VALUE> | ssh <USER@NODE_NAME> -T "cat > /node-metrics/text.prom"
     ```

     

   - A shell script called [set-health](../deploy/health-metric-demo/set-health.sh) is in the [deploy/health-metric-demo](../deploy/health-metric-demo) folder. It takes two arguments, the first being USER@NODENAME and the second a number value to set the health metric. 

     To set health metric to 1 on node "myfirstnode" with user blue:

     ```sh
     ./deploy/health-metric-demo/set-health blue@myfirstnode 1
     ```

     

   - Also you can log into the node and modify the file directly (, which is what I am doing now, because the former two options don't work for me)

   In order to be certain the raw metrics are available look at a specific endpoint output from the above command e.g.
   ``kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/nodes/*/health_metric" | jq .``

   Where "health_metric" is the specific metric looked at. The output should be a json object with names an metrics info for each node in the cluster.

5. Create the secret for the scheduling extender and start it:

   ```sh
   kubens default
   kubectl -n default create secret tls extender-secret --cert extender-ca.crt --key extender-ca.key 
   kubectl apply -f deploy/
   ```

   

6. Create the TASPolicy:

   ```sh
   kubectl apply -f deploy/health-metric-demo/health-policy.yaml 
   ```

   

7. Deploy a test workload:

   ```sh
   kubectl apply -f deploy/health-metric-demo/demo-pod.yaml
   ```

   

8. (To Be Fixed) Since the resource telemetry/scheduling doesn't automatically appear, I work around by adding it manually:

   ```sh
   kubectl proxy --port=8080 & 
   curl --header "Content-Type: application/json-patch+json" \
   --request PATCH \
   --data '[{"op": "add", "path": "/status/capacity/telemetry~1scheduling", "value": "1"}]' \
   https://localhost:8080/api/v1/nodes/k3d-telementry-scheduling-agent-1/status
   # to kill the proxy on macos, run the following:
   pkill -9 -f "kubectl proxy"
   ```

   

