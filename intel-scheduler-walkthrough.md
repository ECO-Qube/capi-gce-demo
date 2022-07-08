# Intel Scheduler Demo Walk Through

1. Deploy a cluster with multiple nodes. If doing it locally, you can use minikube:
   > Note that k3d will be more tricky because it doesn't run the kubernetes scheduler in a pod
   
   ```sh
   minikube start --nodes 3 
   ```


2. Configure Scheduler
   The provided shell [script](https://github.com/intel/platform-aware-scheduling/blob/master/telemetry-aware-scheduling/deploy/extender-configuration/configure-scheduler.sh) which meant to config the scheduler cannot work on minikube cluster or the cluster created by Cluster API. Depending on the kubernetes version you are using, the way to config the cluster varies.

   > Additionally, if using Minikube, make sure to copy the `$HOME/.minikube/ca.crt` and `$HOME/.minikube/ca.key` file from your machine to the master node, put them to path `/etc/kubernetes/pki/ca.crt` and `/etc/kubernetes/pki/ca.key`, because originally minikube cluster doesn't have them in place. 

   - image version earilier than v1.22   

      - First, run the following command on your machine: 

         ```sh
         kubectl apply -f deploy/extender-configuration/scheduler-extender-configmap.yaml
         kubectl apply -f deploy/extender-configuration/configmap-getter.yaml
         kubectl get clusterrolebinding -A | grep scheduler-config-map # chedk if there already exists a clusterrolebinding, if so, don't create a duplicated one
         kubectl create clusterrolebinding scheduler-config-map --clusterrole=configmapgetter --user=system:kube-scheduler
         ```

      - Then, on the masternode, run the following to configure the `kube-scheduler.yaml` file:
      
         ```
         sed -e "/    - kube-scheduler/a\\
         - --policy-configmap=scheduler-extender-policy\n    - --policy-configmap-namespace=kube-system" "/etc/kubernetes/manifests/kube-scheduler.yaml" -i
         ```

   - image version v1.22 and later
      - First, replace "XVERSIONX" with "v1beta2" in the file `deploy/extender-configuration/scheduler-config.yaml`
      - Next, copy the `scheduler-config.yaml` file to the master node, put it to the expected path, say `/etc/kubernetes/scheduler-config.yaml`, we will use this path later
      - Finally, on the masternode, run the following to configure the `kube-scheduler.yaml` file:

         ```sh
         export MANIFEST_FILE=/etc/kubernetes/manifests/kube-scheduler.yaml
         export scheduler_config_destination_path=/etc/kubernetes/scheduler-config.yaml
         sed -e "/    - kube-scheduler/a\\
         - --config=$scheduler_config_destination_path" "$MANIFEST_FILE" -i
         sed -e "/    volumeMounts:/a\\
         - mountPath: $scheduler_config_destination_path\n      name: schedulerconfig\n      readOnly: true" "$MANIFEST_FILE" -i
         sed -e "/  volumes:/a\\
         - hostPath:\n      path: $scheduler_config_destination_path\n    name: schedulerconfig" "$MANIFEST_FILE" -i
         ```
   After modifying the `kube-scheduler.yaml` file, kubelet should detect the changes and update the scheduler automatically. However, sometimes have to delete the scheduler pod manually so that the modification can take effects.

   
3. Install Node Exporter and Prometheus run:
   
   ```sh
   cd telemetry-aware-scheduling
   kubectl create namespace monitoring
   kubens monitoring
   helm install node-exporter deploy/charts/prometheus_node_exporter_helm_chart/
   helm install prometheus deploy/charts/prometheus_helm_chart/
   ```

   

4. Create the secret for the Prometheus adapter and install it:

   Information on how to generate correctly signed certs in kubernetes can be found [here](https://github.com/kubernetes-sigs/apiserver-builder-alpha/blob/master/docs/concepts/auth.md).

   ```sh
   kubectl create namespace custom-metrics
   kubens custom-metrics
   kubectl -n custom-metrics create secret tls cm-adapter-serving-certs --cert=serving-ca.crt --key=serving-ca.key
   helm install prometheus-adapter deploy/charts/prometheus_custom_metrics_helm_chart/
   ```

   The Prometheus adapter may take some time to come online - but once it does running:
   ``kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | grep nodes | jq .``

   should return a number of metrics that are being collected by prometheus node exporter, scraped by prometheus and passed to the Kubernetes Metrics API by the Prometheus Adapter.

5. Providing the metrics:

   With our health metric the file at /tmp/node-metrics/test.prom (inside the worknode) should look like:

   ````node_cpu_diff 0````

   Any change in the value in the file will be read by the prometheus node exporter, and will propagate through the metrics pipeline and made accessible to TAS. 

   - To set the health metric on remote nodes we can use: 

     ```sh
     echo 'node_cpu_diff ' <METRIC VALUE> | ssh <USER@NODE_NAME> -T "cat > /node-metrics/text.prom"
     ```

     

   - A shell script called [set-health](../deploy/health-metric-demo/set-health.sh) is in the [deploy/health-metric-demo](../deploy/health-metric-demo) folder. It takes two arguments, the first being USER@NODENAME and the second a number value to set the health metric. 

     To set health metric to 1 on node "myfirstnode" with user blue:

     ```sh
     ./deploy/health-metric-demo/set-health blue@myfirstnode 1
     ```

     

   - Also you can log into the node and modify the file directly (which is what I am doing now, because the former two options aren't working for me)

   In order to be certain the raw metrics are available look at a specific endpoint output from the above command e.g.
   ``kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/nodes/*/cpu_diff" | jq .``

   Where "cpu_diff" is the specific metric looked at. The output should be a json object with names an metrics info for each node in the cluster.

6. Create the secret for the scheduling extender and start it:

   ```sh
   kubens default
   kubectl -n default create secret tls extender-secret --cert extender-ca.crt --key extender-ca.key 
   kubectl apply -f deploy/
   ```

   

7. Create the TASPolicy:

   ```sh
   kubectl apply -f deploy/health-metric-demo/health-policy.yaml 
   ```

   

8. Deploy a test workload:

   ```sh
   kubectl apply -f deploy/health-metric-demo/demo-pod.yaml
   ```


9. To test the descheduler
   - First clone the repo:
      ```
      git clone git@github.com:kubernetes-sigs/descheduler.git
      cd descheduler
      ```
   -  Next, modify the descheduler configmap `kubernetes/base/configmap.yaml` according to the `deploy/health-metric-demo/descheduler-policy.yaml`
      ```
      ---
      apiVersion: v1
      kind: ConfigMap
      metadata:
      name: descheduler-policy-configmap
      namespace: kube-system
      data:
      policy.yaml: |
         apiVersion: "descheduler/v1alpha1"
         kind: "DeschedulerPolicy"
         strategies:
            "RemovePodsViolatingNodeAffinity":
            enabled: true
            params:
               nodeAffinityType:
                  - "requiredDuringSchedulingIgnoredDuringExecution"
               namespaces:
                  include:
                  - "default"
               nodeFit: false
      ```

   -  Apply configmap and rbac, run the descheduler:
      ```
      kubectl apply -f kubernetes/base/configmap.yaml    
      kubectl apply -f kubernetes/base/rbac.yaml
      kubectl apply -f kubernetes/deployment/deployment.yaml    
      ```



10. (To Be Fixed) The descheduler currently has a bug that the "nodeFit: false" flag is not working. This is preventing the descheduler from evicting jobs from nodes. To work around, add this customized resource to every nodes manually:

      ```sh
      kubectl proxy --port=8080 & 
      curl --header "Content-Type: application/json-patch+json" \
      --request PATCH \
      --data '[{"op": "add", "path": "/status/capacity/telemetry~1scheduling", "value": "111"}]' \
      https://localhost:8080/api/v1/nodes/minikube-m02/status
      # to kill the proxy (on MacOS), run the following:
      pkill -9 -f "kubectl proxy"
      ```
      see this [issue](https://github.com/intel/platform-aware-scheduling/issues/90) for more details


   

