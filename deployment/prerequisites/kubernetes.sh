#!/bin/bash

function install_prerequirements() {
    swapoff -a
    sudo apt-get install ebtables ethtool
    sudo apt-get update -y
    #Install docker
    sudo apt-get install -y curl 
    sudo apt-get install -y docker.io
    sudo docker version
}

function install_kubeadm() {
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
}

function init_kubeadm() {
    sudo swapoff -a
    sudo sed -i.bak '/.*none.*swap/s/^\(.*\)$/#\1/g' /etc/fstab
    sudo kubeadm init --pod-network-cidr=10.210.0.0/16 --apiserver-advertise-address=<master_ip_address>
    sleep 5
}

function kube_config_dir() {
    K8S_MANIFEST_DIR="/etc/kubernetes/manifests"
    mkdir -p $HOME/.kube
    sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

function install_helm() {
    HELM_VERSION="v3.7.2"
    if ! [[ "$(helm version --short 2>/dev/null)" =~ ^v3.* ]]; then
        # Helm is not installed. Install helm
        echo "Helm3 is not installed, installing ..."
        curl https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz --output helm-${HELM_VERSION}.tar.gz
        tar -zxvf helm-${HELM_VERSION}.tar.gz
        sudo mv linux-amd64/helm /usr/local/bin/helm
        rm -r linux-amd64
        rm helm-${HELM_VERSION}.tar.gz
    else
        echo "Helm3 is already installed. Skipping installation..."
    fi
}

function install_k8s_storageclass() {
    echo "Installing open-iscsi"
    sudo apt-get update -y
    sudo apt-get install open-iscsi
    sudo systemctl enable --now iscsid
    OPENEBS_VERSION="3.1.0"
    echo "Installing OpenEBS"
    helm repo add openebs https://openebs.github.io/charts
    helm repo update
    helm install --create-namespace --namespace openebs openebs openebs/openebs --version ${OPENEBS_VERSION}
    helm ls -n openebs
    local storageclass_timeout=400
    local counter=0
    local storageclass_ready=""
    echo "Waiting for storageclass"
    while (( counter < storageclass_timeout ))
    do
        kubectl get storageclass openebs-hostpath &> /dev/null

        if [ $? -eq 0 ] ; then
            echo "Storageclass available"
            storageclass_ready="y"
            break
        else
            counter=$((counter + 15))
            sleep 15
        fi
    done
    [ -n "$storageclass_ready" ] || FATAL "Storageclass not ready after $storageclass_timeout seconds. Cannot install openebs"
    kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
}

function taint_master_node() {
    K8S_MASTER=$(kubectl get nodes | awk '$3~/master/'| awk '{print $1}')
    kubectl taint node $K8S_MASTER node-role.kubernetes.io/master-
    kubectl taint node $K8S_MASTER node-role.kubernetes.io/master:NoSchedule-
    kubectl label --overwrite node $K8S_MASTER ovn4nfv-k8s-plugin=ovn-control-plane
    sleep 5
}

function install_prometheus(){
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    kubectl create ns monitoring; 
    helm install prometheus-community/kube-prometheus-stack --generate-name --set grafana.service.type=NodePort --set prometheus.service.type=NodePort --set prometheus.prometheusSpec.scrapeInterval="5s" --namespace monitoring
}

function install_cilium(){
    curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz{,.sha256sum}
    sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
    sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
    rm cilium-linux-amd64.tar.gz{,.sha256sum}
    cilium install
}

function install_certmanager(){
    kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml
    nodename=$(kubectl get node -o jsonpath='{.items[0].metadata.name}')
    kubectl taint node $nodename node-role.kubernetes.io/master:NoSchedule-
    kubectl label --overwrite node $nodename ovn4nfv-k8s-plugin=ovn-control-plane
}

function usage() {         
    echo                        # Function: Print a help message.
    echo "usage: $0 [-t types]"
    echo "Must run as root"
    echo "options:"
    echo "  -t      Type of Kubernetes' component (NODE or CLUSTER)"
    exit 1
}
function exit_abnormal() {                         # Function: Exit with error.
  usage
  exit 1
}

while getopts "t:" options; do

  case "${options}" in
    t)
      KUBETYPE=${OPTARG}
      if [ "$KUBETYPE" != "NODE" ] && [ "$KUBETYPE" != "CLUSTER" ]; then
        echo "Error: TYPE must be CLUSTER or NODE"
        exit_abnormal
        exit 1
      fi
      ;;
    :)
      echo "Error: -${OPTARG} requires an argument."
      exit_abnormal               
      ;;
    *)    
      exit_abnormal
      ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  echo "Must run as sudo";
  exit_abnormal
fi

#No options were passed to the script
if [ $OPTIND -eq 1 ]; then 
    echo "No options were passed";
    exit_abnormal
fi

#Depending on the type, the installation changes
if [ "$KUBETYPE" == "NODE" ]; then
    install_prerequirements
    install_kubeadm
else
    install_prerequirements
    install_kubeadm
    install_prerequirements
    install_kubeadm
    init_kubeadm
    kube_config_dir
    taint_master_node
    install_helm
    install_k8s_storageclass
    install_cilium
    install_prometheus
    install_certmanager
fi