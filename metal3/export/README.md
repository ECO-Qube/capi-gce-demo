# Basic Metal3 setup

## Setup minikube with vbmc and the Metal3 stack

```bash
# Install virt-install
sudo apt install virtinst

## Minikube setup with libvirt and PXE boot
minikube start --driver=kvm2
# Get he IP address of minikube in the default network
# This is the IP address of the interface of the default network (where the BMHs are).
MINIKUBE_ETH1_IP="$(minikube ssh -- ip -f inet addr show eth1 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')"
minikube stop
# Edit the network to have <bootp file=http://MINIKUBE_ETH1_IP:6180/boot.ipxe/> (under network.ip.dhcp)
# <network connections='2'>
#   <name>default</name>
#   ...
#   <ip address='192.168.122.1' netmask='255.255.255.0'>
#     <dhcp>
#       <range start='192.168.122.2' end='192.168.122.254'/>
#       <bootp file='http://MINIKUBE_ETH1_IP:6180/boot.ipxe'/>
#     </dhcp>
#   </ip>
# </network>
virsh net-destroy default
echo "Add this to the network:"
echo "<bootp file=http://${MINIKUBE_ETH1_IP}:6180/boot.ipxe/>"
virsh net-edit default
virsh net-start default
# Start minikube again
minikube start

## VBMC with ssh connection to libvirt on the host
# TODO: Ensure host has sshd running
minikube ssh -- ssh-keygen -t ed25519 -f /home/docker/.ssh/id_ed25519 -N '' -q
PUBLIC_KEY="$(minikube ssh -- cat .ssh/id_ed25519.pub)"
echo "${PUBLIC_KEY}" >> ~/.ssh/authorized_keys
kubectl apply -f vbmc.yaml

## Initialize Metal3
clusterctl init --infrastructure metal3
# Set correct IP (eth1) in configmaps and certificates
kustomize build ironic/overlays/basic-auth_tls | sed "s/MINIKUBE_IP/${MINIKUBE_ETH1_IP}/g" | kubectl apply -f -
kustomize build baremetal-operator/overlays/basic-auth_tls | sed "s/MINIKUBE_IP/${MINIKUBE_ETH1_IP}/g" | kubectl apply -f -

# TODO:
# - Persistent cache for Ironic. Mount from host to minikube to container?
#   - Seems like it is not possible to use a folder mounted with `minikube mount`.
#   - Currently just mounting /opt/minikube from the minikube VM in the ironic container.
# - Cleanup: Remove entry from authorized_keys and delete VMs

## Create BMH backed by libvirt VM
./create_bmh.sh <name> <vbmc_port>
```

## Adding libvirt backed BareMetalHosts

```bash
## Create BMH backed by libvirt VM
./create_bmh.sh <name> <vbmc_port>

# Example
./create_bmh.sh host-0 16230
./create_bmh.sh host-1 16231
# After this you should see the bmhs go through registering, inspecting and become available
# ❯ kubectl get bmh
# NAME     STATE       CONSUMER   ONLINE   ERROR   AGE
# host-0   available              true             58m
# host-1   available              true             41m
```

## Provisioning a BareMetalHost

```bash
# Download Ubuntu cloud image
mkdir images
pushd images
wget -O MD5SUMS https://cloud-images.ubuntu.com/jammy/current/MD5SUMS
wget -O jammy-server-cloudimg-amd64.vmdk https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.vmdk
md5sum --check --ignore-missing MD5SUMS
MD5SUM="$(grep "jammy-server-cloudimg-amd64.vmdk" MD5SUMS | cut -d ' ' -f 1)"
popd

# Run image server
docker run --rm --name image-server -d -p 80:8080 -v "$(pwd)/images:/usr/share/nginx/html" nginxinc/nginx-unprivileged

# Get server IP from BMH point of view
SERVER_IP="$(virsh net-dumpxml default | sed -En "s/.*ip address='([0-9.]+)'.*/\1/p")"

# Create user-data
# It should be a secret with data.value and data.format.
# data.format=cloud-config
# data.value is the cloud config content
cat <<'EOF' > user-data.yaml
#cloud-config
users:
  - name: ubuntu
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    # generate with mkpasswd --method=SHA-512 --rounds=4096
    # nerdvendor
    passwd: $6$rounds=4096$EhcyaSgedVn6D9Qm$WTqrBEESsX6Qe0huYzEy0i13xEfLecPGGB184HvkiFm4SNxLq3WeVE0AA4.hWQz8CXkxqb7J05I6DErQ6qvvi1
EOF
kubectl create secret generic user-data --from-file=value=user-data.yaml --from-literal=format=cloud-config

# Test provisioning a BMH
kubectl patch bmh host-0 --type=merge --patch-file=/dev/stdin <<EOF
spec:
  image:
    url: "http://${SERVER_IP}/jammy-server-cloudimg-amd64.vmdk"
    checksum: "${MD5SUM}"
    format: vmdk
  userData:
    name: user-data
    namespace: default
EOF

echo "Wait for it to provision. After this you should be able to login to the console in virt-manager"
echo "using username 'ubuntu' and password 'nerdvendor'."
```

## Creating a workload cluster

```bash

# NOTE: Add ssh key for debugging below (in CTRLPLANE_KUBEADM_EXTRA_CONFIG and WORKERS_KUBEADM_EXTRA_CONFIG)!

# Download cluster-template
CLUSTER_TEMPLATE=/tmp/cluster-template.yaml
# https://github.com/metal3-io/cluster-api-provider-metal3/blob/main/examples/clusterctl-templates/clusterctl-cluster.yaml
CLUSTER_TEMPLATE_URL="https://raw.githubusercontent.com/metal3-io/cluster-api-provider-metal3/main/examples/clusterctl-templates/clusterctl-cluster.yaml"
wget -O "${CLUSTER_TEMPLATE}" "${CLUSTER_TEMPLATE_URL}"

# export CLUSTER_APIENDPOINT_HOST="${MINIKUBE_ETH1_IP}"
export CLUSTER_APIENDPOINT_HOST="192.168.122.199"
export CLUSTER_APIENDPOINT_PORT="6443"
export CTLPLANE_KUBEADM_EXTRA_CONFIG='
    users:
      - name: ubuntu
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        sshAuthorizedKeys:
          # Add/replace ssh key here
          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3XsjgwkAkxd5aioPiBws7O5nx5ofcR4TvAIOvSQ9Ce
    preKubeadmCommands:
      - /usr/local/bin/install-container-runtime.sh
      - /usr/local/bin/install-kubernetes.sh
    files:
      - path: /usr/local/bin/install-container-runtime.sh
        owner: root:root
        permissions: "0755"
        content: |
          #!/usr/bin/env bash
          apt-get update
          apt-get install -y ca-certificates curl gnupg lsb-release
          mkdir -m 0755 -p /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
          apt-get update
          apt-get install -y containerd.io
          containerd config default > /etc/containerd/config.toml
          systemctl restart containerd
      - path: /usr/local/bin/install-kubernetes.sh
        owner: root:root
        permissions: "0755"
        content: |
          #!/usr/bin/env bash

          sysctl --system
          systemctl restart systemd-modules-load.service

          curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
          echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
          apt-get update
          apt-get install -y kubelet kubeadm kubectl
          apt-mark hold kubelet kubeadm kubectl
      - path: /etc/sysctl.d/99-kubernetes-cri.conf
        owner: root:root
        permissions: "0644"
        content: |
          net.bridge.bridge-nf-call-iptables = 1
          net.ipv4.ip_forward = 1
          net.bridge.bridge-nf-call-ip6tables = 1
      - path: /etc/modules-load.d/k8s.conf
        owner: root:root
        permissions: "0644"
        content: |
          br_netfilter'
# Cri-o
# export CTLPLANE_KUBEADM_EXTRA_CONFIG='
#     preKubeadmCommands:
#       - /usr/local/bin/install-container-runtime.sh
#       - /usr/local/bin/install-kubernetes.sh
#     files:
#       - path: /usr/local/bin/install-container-runtime.sh
#         owner: root:root
#         permissions: "0755"
#         content: |
#           #!/usr/bin/env bash
#           export OS=xUbuntu_22.04
#           export VERSION=1.26

#           apt-get update
#           apt-get install -y apt-transport-https ca-certificates curl

#           echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
#           echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list

#           mkdir -p /usr/share/keyrings
#           curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
#           curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

#           apt-get update
#           apt-get install -y cri-o cri-o-runc
#       - path: /usr/local/bin/install-kubernetes.sh
#         owner: root:root
#         permissions: "0755"
#         content: |
#           #!/usr/bin/env bash

#           sysctl --system
#           systemctl restart systemd-modules-load.service

#           curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
#           echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
#           apt-get update
#           apt-get install -y kubelet kubeadm kubectl
#           apt-mark hold kubelet kubeadm kubectl
#       - path: /etc/sysctl.d/99-kubernetes-cri.conf
#         owner: root:root
#         permissions: "0644"
#         content: |
#           net.bridge.bridge-nf-call-iptables = 1
#           net.ipv4.ip_forward = 1
#           net.bridge.bridge-nf-call-ip6tables = 1
#       - path: /etc/modules-load.d/k8s.conf
#         owner: root:root
#         permissions: "0644"
#         content: |
#           br_netfilter'
export IMAGE_CHECKSUM="${MD5SUM}"
export IMAGE_CHECKSUM_TYPE="md5"
export IMAGE_FORMAT="vmdk"
export IMAGE_URL="http://${SERVER_IP}/jammy-server-cloudimg-amd64.vmdk"
export KUBERNETES_VERSION="v1.26.1"
export WORKERS_KUBEADM_EXTRA_CONFIG='
      preKubeadmCommands:
        - /usr/local/bin/install-container-runtime.sh
        - /usr/local/bin/install-kubernetes.sh
      files:
        - path: /usr/local/bin/install-container-runtime.sh
          owner: root:root
          permissions: "0755"
          content: |
            #!/usr/bin/env bash
            export OS=xUbuntu_22.04
            export VERSION=1.26

            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl

            echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
            echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list

            mkdir -p /usr/share/keyrings
            curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
            curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

            apt-get update
            apt-get install -y cri-o cri-o-runc
        - path: /usr/local/bin/install-kubernetes.sh
          owner: root:root
          permissions: "0755"
          content: |
            #!/usr/bin/env bash

            sysctl --system
            systemctl restart systemd-modules-load.service

            curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
            echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
            apt-get update
            apt-get install -y kubelet kubeadm kubectl
            apt-mark hold kubelet kubeadm kubectl
        - path: /etc/sysctl.d/99-kubernetes-cri.conf
          owner: root:root
          permissions: "0644"
          content: |
            net.bridge.bridge-nf-call-iptables = 1
            net.ipv4.ip_forward = 1
            net.bridge.bridge-nf-call-ip6tables = 1
        - path: /etc/modules-load.d/k8s.conf
          owner: root:root
          permissions: "0644"
          content: |
            br_netfilter'

clusterctl generate cluster my-cluster \
  --from "${CLUSTER_TEMPLATE}" \
  --target-namespace default | kubectl apply -f -
```
