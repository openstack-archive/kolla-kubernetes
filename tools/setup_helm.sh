#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

HELM_VERSION=2.1.3

curl http://storage.googleapis.com/kubernetes-helm/helm-v$HELM_VERSION-linux-amd64.tar.gz | sudo tar --strip-components 1 -C /usr/bin linux-amd64/helm -zxf -
mkdir -p ~/.kube
sudo cat /etc/kubernetes/kubelet.conf > ~/.kube/config

$DIR/pull_containers.sh kube-system
$DIR/wait_for_pods.sh kube-system

helm init
