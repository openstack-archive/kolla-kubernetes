#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

. tools/helm_versions.sh 

#curl "$HELM_URL" | sudo tar --strip-components 1 -C /usr/bin linux-amd64/helm -zxf -
sudo curl -o /usr/bin/helm https://raw.githubusercontent.com/jascott1/bins/master/helm/nethost/_dist/linux-amd64/helm
sudo chmod +x /usr/bin/helm
if [ ! -e ~/.kube/config ]; then
    mkdir -p ~/.kube
    sudo cat /etc/kubernetes/kubelet.conf > ~/.kube/config
fi

$DIR/pull_containers.sh kube-system
$DIR/wait_for_pods.sh kube-system

helm init --host-net
