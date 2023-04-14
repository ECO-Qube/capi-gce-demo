# Setting up Cluster API on metal3

## Overall steps

1. Create user account in the BMC of the desired management cluster node.
2. Install Kubernetes (if testing, go for Minikube for a single-node cluster)
3. Install Baremetal Operator (which will in turn deploy Ironic)
4. Initialize the cluster as a CAPM3 provider with clusterctl
5. Follow the usual clusterctl guide
6. Create a BareMetalHost resource per each physical node and apply it to the cluster along with Secrets and ConfigMaps.
    1. Can check using `kubectl get bmh -n metal3` and wait until “ready” is displayed.
    2. Scale up the MachineDeployment resource to see the new bare-metal host joining the cluster.

WIP: 

- https://www.notion.so/helioag/Kubeadm-installation-Master-preparation-for-Metal3-5b07f73e12244d9c813af7985eed1f8e
- https://www.notion.so/helioag/Metal3-Blockheating-Deployment-Notes-bc0b3fffb4c64deab70084cb9fb9c656

Backup in case of catastrophic loss of data: https://drive.google.com/file/d/1BKP1lYEvugM8Xps5ZCYod6zsN0WjIYdD/view?usp=share_link