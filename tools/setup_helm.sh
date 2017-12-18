#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

# Returns $ARCH, which can be amd64, arm64 and ppc64le
. tools/get_arch.sh
. tools/helm_versions.sh

curl "$HELM_URL" | sudo tar --strip-components 1 -C /usr/bin linux-$ARCH/helm -zxf -
if [ ! -e ~/.kube/config ]; then
    mkdir -p ~/.kube
    sudo cat /etc/kubernetes/kubelet.conf > ~/.kube/config
fi

$DIR/pull_containers.sh kube-system
$DIR/wait_for_pods.sh kube-system

helm init
