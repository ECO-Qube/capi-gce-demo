# Setting up Cluster API on OpenStack

Build image

https://image-builder.sigs.k8s.io/capi/providers/openstack.html

> NOTE you need CPU virtualization enabled in your BIOS settings. Verify with `kvm-ok` if in doubt.

```bash
docker run --name=ubuntu2004 -dit --privileged -v $(pwd)/openstack-images:/home ubuntu:focal
docker exec -it ubuntu2004 /bin/bash
apt update
apt install qemu-kvm libvirt-daemon-system libvirt-clients virtinst cpu-checker libguestfs-tools libosinfo-bin git make python pip ansible unzip
usermod -a -G kvm root
chown root:kvm /dev/kvm
```
exit the container and reenter

```bash
cd /home
git clone https://github.com/kubernetes-sigs/image-builder.git
cd image-builder/images/capi
make deps-qemu
make build-qemu-ubuntu-2004
```

then we need to set the environment variables for `clusterctl`. First log into the OpenStack installation
e.g. `ssh sesame@192.168.10.153`. Copy `/etc/openstack/clouds.yaml` into your local machine and run the following:

> Note you can also download the `clouds.yaml` file from the GUI `API access > Download OpenStack RC File > OpenStack clouds.yaml file`

```bash
wget https://raw.githubusercontent.com/kubernetes-sigs/cluster-api-provider-openstack/master/templates/env.rc -O /tmp/env.rc
source /tmp/env.rc <path/to/clouds.yaml> <cloud>
```

where cloud is for example `devstack-admin`. The script will set some environment variables related to authentication.

Apart from the script, set the following OpenStack environment variables:

- Note that the DNS server can be obtained by looking at `/etc/resolv.conf`.
- Note you can list the machine flavors with `openstack flavor list`.
- Note the SSH pair can be created in the GUI or by running `openstack keypair create [--public-key <file> | --private-key <file>] <name>`.

```bash
# The list of nameservers for OpenStack Subnet being created.
# Set this value when you need create a new network/subnet while the access through DNS is required.
export OPENSTACK_DNS_NAMESERVERS=127.0.0.53
export OPENSTACK_FAILURE_DOMAIN=nova
export OPENSTACK_CONTROL_PLANE_MACHINE_FLAVOR=ds4G
export OPENSTACK_NODE_MACHINE_FLAVOR=ds4G
export OPENSTACK_IMAGE_NAME=ubuntu-2004-kube-v1.22.9
export OPENSTACK_SSH_KEY_NAME=demo
export OPENSTACK_EXTERNAL_NETWORK_ID=4efd71fa-6a5c-4395-a39e-446613e27ab7
```

then generate the config:

```bash
kind create cluster --config=bootstrap-kind-config.yaml
clusterctl init --infrastructure openstack
clusterctl generate cluster capi-quickstart --flavor without-lb \
  --kubernetes-version=v1.22.9 \
  --control-plane-machine-count=1 \
  --worker-machine-count=1 \
  > capi-quickstart-openstack.yaml
kubectl apply -f capi-quickstart-openstack.yaml
```

#### Use `openstack` CLI tool

Go to Horizon, top right on the navbar there is a button with your username. Download the
OpenStack RC File, then run `source <youruser-openrc.sh` and input the admin password.
