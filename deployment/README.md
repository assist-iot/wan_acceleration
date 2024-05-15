![image-3](https://user-images.githubusercontent.com/100677511/170439941-58810f43-b437-41e5-9976-899b60cf1e5e.png)
# Deploy WAN-Acceleration enabler

## Steps to install preconditions software
--------

### Steps to install kubernetes requeriments
--------

Please locate your directory to `/PATH/wan-acceleration/deployment/prerequisites`

**1. Exec kubernetes.sh to install initial configuration**

In file [kubernetes.sh](./kubernetes.sh) change field '<ip_address>' for your private apiserver-advertise-address.

Then, execute the following command:

```
$ ./kubernetes.sh -t CLUSTER
```

### Steps to install network configuration
---------

Please locate your directory to `/PATH/wan-acceleration/deployment/prerequisites/crds`

For the network configuration, the helm charts of CNF and Controller need integrate Multus CNI with Calico as default network

**1. Install network**

- Create daemonsets, ov4nfv plugins and net-attachment definitions.

```
$ kubectl apply -f calico.yaml
$ kubectl apply -f multus-daemonset.yaml
$ kubectl apply -f ovn-daemonset.yaml
$ kubectl apply -f ovn4nfv-k8s-plugin.yaml
$ kubectl apply -f multus-net-attach-def-cr.yaml
```

**2. Apply ovn-networks**

- Create ovn-network and provider-network, e.g.

```
$ kubectl apply -f ovn-networks.yaml
```

## Steps to install WAN-Acceleration Enabler
------

### Installation via helm chart
------

Please locate your directory to `/PATH/wan-acceleration/deployment/helm`

**1.Install WAN-Acceleration Enabler**

```
helm install wan-acceleration wan-acceleration/ --namespace <namespace>
```
