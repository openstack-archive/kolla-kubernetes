#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

. tools/helm_versions.sh 

curl "$HELM_URL" | sudo tar --strip-components 1 -C /usr/bin linux-amd64/helm -zxf -
if [ ! -e ~/.kube/config ]; then
    mkdir -p ~/.kube
    sudo cat /etc/kubernetes/kubelet.conf > ~/.kube/config
fi

#
# Overriding current helm binary with debug version
# debug version will create a stack trace by using panic
sudo curl -L https://raw.githubusercontent.com/jascott1/bins/master/helm/history_panic/_dist/linux-amd64/helm \
          -o /usr/bin/helm
sudo chmod +x /usr/bin/helm

$DIR/pull_containers.sh kube-system
$DIR/wait_for_pods.sh kube-system

helm init
