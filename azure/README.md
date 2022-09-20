### Setting up Cluster API on Azure

https://capz.sigs.k8s.io/topics/getting-started.html

Install Azure CLI.

Login and list all subscriptions:

```
az login
az account list -o table
```

Export the subscription id:

```
export AZURE_SUBSCRIPTION_ID="3f5d6a8e-fdba-4e22-a791-9976d32e9ca7"
```

Save the previous commands here:

```
export AZURE_TENANT_ID="<Tenant>"
export AZURE_CLIENT_ID="<AppId>"
export AZURE_CLIENT_SECRET='<Password>'
export AZURE_LOCATION="eastus" # this should be an Azure region that your subscription has quota for.
```

```
export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"
```

```
export AZURE_CLUSTER_IDENTITY_SECRET_NAME="cluster-identity-secret"
export CLUSTER_IDENTITY_NAME="cluster-identity"
export AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE="default"
```

Create a cluster

```
kind create cluster --config bootstrap-kind-config.yaml
kubectl cluster-info
```

Create a secret and init infrastructure

```
kubectl create secret generic "${AZURE_CLUSTER_IDENTITY_SECRET_NAME}" --from-literal=clientSecret="${AZURE_CLIENT_SECRET}"
clusterctl init --infrastructure azure
```

```
export AZURE_CONTROL_PLANE_MACHINE_TYPE="Standard_D2s_v3"
export AZURE_NODE_MACHINE_TYPE="Standard_D2s_v3"
export AZURE_RESOURCE_GROUP="scheduling-dev"
```

```
clusterctl generate cluster scheduling-dev-mgmt \
  --kubernetes-version v1.23.6 \
  --control-plane-machine-count=1 \
  --worker-machine-count=1 \
  > scheduling-dev-mgmt.yaml
```

Apply config:

```
kubectl apply -f scheduling-dev-mgmt.yaml
```

The rest of the tutorial is the same as for GCP after applying CAPI's resources.