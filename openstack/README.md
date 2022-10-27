# Setting up Cluster API on OpenStack

## Building the image

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

At the end of the process, a QCOW2 image will be generated. We must upload that to OpenStack. The GUI does not work so we
will use the CLI tool.

First download the CLI tool

```bash
sudo pip3 install python-openstackclient
```

then we log in by using the `admin-rc.sh` script that can be download from the dashboard. Just go to the very top-right
part of the screen, click on `admin` and then click on OpenStack RC File to download the mentioned script. Run the
script

```bash
source admin-openrc.sh
```

now we can use the CLI tool. Go into the output directory where your image was placed after (should be
under `openstack-images/<image_name>`) and run the following:

```bash
openstack image create --disk-format qcow2 --container-format bare --public --file ./ubuntu-2004-kube-v1.25.0 ubuntu-2004-kube-v1.25.0
```

## Provision openstack clusters

We need to set the environment variables for `clusterctl`. First log into the OpenStack installation
e.g. `ssh sesame@192.168.10.153`. Copy `/etc/openstack/clouds.yaml` into your local machine and run the following:

> Note you can also download the `clouds.yaml` file from the GUI `API access > Download OpenStack RC File > OpenStack clouds.yaml file`

Check that the `clouds.yaml` file has a field `password` specified under `auth`. If not, add it and set it to the password.
Then run the following:

```bash
wget https://raw.githubusercontent.com/kubernetes-sigs/cluster-api-provider-openstack/master/templates/env.rc -O /tmp/env.rc
source /tmp/env.rc <path/to/clouds.yaml> <cloud>
```

where cloud is the key under `clouds` in `clouds.yaml`, example `openstack`. The script will set some environment variables related to authentication.

Apart from the script, set the following OpenStack environment variables:

- Note that the DNS server can be obtained by looking at `/etc/resolv.conf`.
- Note you can list the machine flavors with `openstack flavor list`.
- Note the SSH pair can be created in the GUI or by
  running `openstack keypair create [--public-key <file> | --private-key <file>] <name>`.
- Note you can find the external network id in the GUI under `Network > Networks > public > Overview (ID)`
```bash
# The list of nameservers for OpenStack Subnet being created.
# Set this value when you need create a new network/subnet while the access through DNS is required.
export OPENSTACK_DNS_NAMESERVERS=8.8.8.8
export OPENSTACK_FAILURE_DOMAIN=nova
export OPENSTACK_CONTROL_PLANE_MACHINE_FLAVOR=ds4G
export OPENSTACK_NODE_MACHINE_FLAVOR=ds4G
export OPENSTACK_IMAGE_NAME=ubuntu-2004-kube-v1.25.0
export OPENSTACK_SSH_KEY_NAME=admin
export OPENSTACK_EXTERNAL_NETWORK_ID=8e5055bc-be3d-4074-b1ce-6048ce7229a8

export EXP_CLUSTER_RESOURCE_SET=true
```

then generate the config:

```bash
kind create cluster --config=bootstrap-kind-config.yaml
clusterctl init --infrastructur e openstack
clusterctl generate cluster ecoqube-mgmt --flavor without-lb \
  --kubernetes-version=v1.25.0 \
  --control-plane-machine-count=1 \
  --worker-machine-count=1 \
  > ecoqube-mgmt.yaml
```

Note you should add the necessary resources to your cluster to provision automatically
CNI and TAS. See [this](https://github.com/intel/platform-aware-scheduling/pull/108/commits/74a191bd5d1e38a341e5985b32e5772b0a2cd1fc?short_path=e3d5bb4#diff-e3d5bb48b8a6f470573e8ca75c54e054629c6991a26c05a767ef7bc95a9ee9fb)
for a guide on how to automate TAS installation. You don't need to
generate those; make use of the existing `ecoqube-mgmt.yaml` manifests file.

```bash
kubectl apply -f ecoqube-mgmt.yaml
```

Wait until the control plane is up and running using the following command:
`watch -n 1 kubectl get kubeadmcontrolplane`, then get kubeconfig:

> Note that both INITIALIZED API SERVER and API SERVER AVAILABLE must be true. Wait up to 10 minutes.

```bash
clusterctl get kubeconfig ecoqube-mgmt > ecoqube-mgmt.kubeconfig
```

## Use `openstack` CLI tool

Go to Horizon, top right on the navbar there is a button with your username. Download the OpenStack RC File, then
run `source <youruser-openrc.sh>` and input the admin password.

## Error pulling gcr.k8s.io

Replace value in `imageRegistry` in `KubeadmControlPlane` with `registry.k8s.io`.