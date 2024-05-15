![image-3](https://user-images.githubusercontent.com/100677511/170439941-58810f43-b437-41e5-9976-899b60cf1e5e.png)

# WAN-Acceleration Enabler

# Scenario-B

Edge to traffic hub tunnel where inter micro-service communication across edges that attached to same traffic hub.

![scenarioB](/images/scenarioB.png)

In this tutorial, we will guide you step-by-step through the installation and implementation of the **WAN-Acceleration Enabler in Scenario B**. This scenario involves two edge nodes connected via WAN network obtaining and communicating their connections through a hub server acting as as an intermediary between them. 

For this example we have three virtual machines hosted within a server virtualization environment. The properties of each virtual machine are listed below.

| **Name** | **Operating System** | **CPUs** | **RAM** | **Network interface**    | **Master IP**   |
|----------|----------------------|----------|---------|--------------------------|-----------------|
| Edge1    | Linux Ubuntu 20.04   | 4        | 8GB     | ens18 - 192.168.250.0/24 | 192.168.250.157 |
| Edge2    | Linux Ubuntu 20.04   | 4        | 8GB     | ens18 - 192.168.250.0/24 | 192.168.250.218 |
| Hub      | Linux Ubuntu 20.04   | 4        | 8GB     | ens18 - 192.168.250.0/24 | 192.168.250.174 |

> **Note**: This tutorial was made on *Linux Ubuntu 20.04* for *Kubernetes 1.23.3-00*

## Installation process
---------------

For each virtual machine, the installation of this enabler is completely similar, it will only be neccesary to **look at the notes** added below of each step. Step by step is explained below.

### Installation of k8s cluster environment
-------------------------------------------

**1. Install prerequirements**

```
swapoff -a
sudo apt-get install ebtables ethtool
sudo apt-get update -y
#Install docker
sudo apt-get install -y curl 
sudo apt-get install -y docker.io
sudo docker version
```

**2. Install kubeadm**

```
K8S_VERSION=1.23.3-00
sudo apt-get update && sudo apt-get install -y apt-transport-https
sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - 
add-apt-repository "deb https://apt.kubernetes.io/ kubernetes-xenial main"
sudo apt-get update -y
echo "Installing Kubernetes Packages ..."
sudo apt-get install -y kubelet=${K8S_VERSION} kubeadm=${K8S_VERSION} kubectl=${K8S_VERSION}
cat << EOF | sudo tee -a /etc/default/kubelet
KUBELET_EXTRA_ARGS="--cgroup-driver=cgroupfs"
EOF
sudo apt-mark hold kubelet kubeadm kubectl
```

**3. Init kubeadm**

```
sudo swapoff -a
sudo sed -i.bak '/.*none.*swap/s/^\(.*\)$/#\1/g' /etc/fstab
sudo kubeadm init --pod-network-cidr=10.210.0.0/16 --apiserver-advertise-address=<master_ip_address>
sleep 5
```

> **Note**: Change *<master_ip_address>* to the IP assigned in the network interface to each virtual machine.

**4. Init kubernetes**

```
K8S_MANIFEST_DIR="/etc/kubernetes/manifests"
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**5. Install helm**

```
HELM_VERSION="v3.7.2"
curl https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz --output helm-${HELM_VERSION}.tar.gz
tar -zxvf helm-${HELM_VERSION}.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
rm -r linux-amd64
rm helm-${HELM_VERSION}.tar.gz
```

**6. Install cert-manager**

```
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml
```

**7. Taint and label the node**
```
K8S_MASTER=$(kubectl get nodes | awk '$3~/master/'| awk '{print $1}')
kubectl taint node $K8S_MASTER node-role.kubernetes.io/master-
kubectl taint node $K8S_MASTER node-role.kubernetes.io/master:NoSchedule-
kubectl label --overwrite node $K8S_MASTER ovn4nfv-k8s-plugin=ovn-control-plane
```

After these steps, we will be able to successfully install kubernetes and helm ready to work with **CNI Calico**.

### Installation of network environment
---------------------------------------

For the network configuration, WAN-Acceleration enabler need integrate Multus CNI with Calico as default network.

Please locate your directory to `/PATH/wan-acceleration/deployment/prerequisites/crds`

**1. Deploy the Calico and Multus CNI in the kubeadm master**

```
kubectl apply -f calico.yaml
kubectl apply -f multus-daemonset.yaml
```

**2. Deploy Nodus components**

In this example, we are using pod CIDR as `10.210.0.0/16`. The Calico will automatically detect the CIDR based on the running configuration. Since calico network going to the primary network in our case, ovn4nfv subnet should be a different network. Make sure you change the *<OVN_SUBNET>* and *<OVN_GATEWAYIP>* in `ovn4nfv-k8s-plugin.yaml`. In this example, we customize the ovn network as follows.

```
data:
  OVN_SUBNET: "10.154.142.0/18"
  OVN_GATEWAYIP: "10.154.142.1/18"
```

Deploy the Nodus components
```
kubectl apply -f ovn-daemonset.yaml
kubectl apply -f ovn4nfv-k8s-plugin.yaml
```

Create a network attachment definition

```
kubectl apply -f multus-net-attach-def-cr.yaml
```

**3. Create networks**

The interfaces will be very important in the future process, for this case we have created two main networks. In the first case, we created a provider interface with range `10.10.70.0/24`. In addition, for each internal configuration, it will be necessary to obtain the name of the master interface to create a *VLAN* that will be in charge of handling WAN communication in the future.

```
vlan:
    vlanId: "100"
    providerInterfaceName: ens18
    logicalInterfaceName: ens18.100
    vlanNodeSelector: all
```

On the other hand, we have created an internal WAN network named *ovn-network* with range `172.16.70.0/24`.

Apply the network configuration:

```
kubectl apply -f ovn-networks.yaml
```

> **Note**: Network configuration must be identical in all configurations.

### Install WAN-Acceleration Enabler via helm chart
---------------------------------------------------

Please locate your directory to `/PATH/wan-acceleration/deployment/helm`

**1. Edit helm chart values**

Once we have the networks already created, we need to **choose the static IP to the CNF**. The following table shows the IPs chosen for this tutorial for each component.

| **Network interface** | **Edge 1**   | **Edge 2**   | **Hub**      |
|-----------------------|--------------|--------------|--------------|
| pnetwork - 172.16.70.0/24              | 172.16.70.41 | 172.16.70.42 | 172.16.70.40 |
| ovn-network - 10.10.70.0/24           | 10.10.70.41  | 10.10.70.42  | 10.10.70.40  |

With this information, change values in `values.yaml` file inside the helm chart configuration.

```
nfn:
    - defaultGateway: false
    interface: net2
    ipAddress: <ovn-network_static_ip>
    name: pnetwork
    separate: ","
    - defaultGateway: false
    interface: net0
    ipAddress: <pnetwork_static_ip>
    name: ovn-network
    separate: ""
```

Also in:

```
publicIpAddress: "<ovn-network_static_ip>"
defaultCIDR:     "10.154.142.0/24" 
providerCIDR:    "10.10.70.0/24"
```


**2. Install WAN-Acceleration Enabler**

```
helm install wan-acceleration wan-acceleration/ --namespace default
```

After installing the helm chart, you should be able to successfully deploy the WAN-acceleration enabler.