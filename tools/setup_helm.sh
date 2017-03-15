#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

HELM_VERSION=2.2.2

curl http://storage.googleapis.com/kubernetes-helm/helm-v$HELM_VERSION-linux-amd64.tar.gz | sudo tar --strip-components 1 -C /usr/bin linux-amd64/helm -zxf -
if [ ! -e ~/.kube/config ]; then
    mkdir -p ~/.kube
    sudo cat /etc/kubernetes/kubelet.conf > ~/.kube/config
fi

$DIR/pull_containers.sh kube-system
$DIR/wait_for_pods.sh kube-system

helm init
