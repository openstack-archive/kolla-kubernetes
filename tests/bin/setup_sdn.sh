#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

url_canal="https://raw.githubusercontent.com/projectcalico/canal/master"
url_canal="$url_canal/k8s-install/1.7/canal.yaml"

url_canal_rbac="https://raw.githubusercontent.com/projectcalico/canal/master"
url_canal_rbac="$url_canal_rbac/k8s-install/1.7/rbac.yaml"

url_flannel="https://raw.githubusercontent.com/coreos/flannel"
url_flannel="$url_flannel/v0.9.1/Documentation/kube-flannel.yml"

url_flannel_rbac="https://raw.githubusercontent.com/coreos/flannel/master"
url_flannel_rbac="$url_flannel_rbac/Documentation/k8s-manifests/kube-flannel-rbac.yml"

if [[ "$(uname -m)" == "x86_64" ]]; then
    url=$url_canal
    url_rbac=$url_canal_rbac
else
    url=$url_flannel
    url_rbac=$url_flannel_rbac
fi

curl "$url" -o /tmp/sdn.yaml
curl "$url_rbac" -o /tmp/rbac.yaml

kubectl create -f /tmp/rbac.yaml

#
# Instead of hardcoding cluster cidr, let's get it from
# controller manager manifest.
#
cluster_cidr=$(sudo grep cluster-cidr /etc/kubernetes/manifests/kube-controller-manager.yaml || true)
cluster_cidr=${cluster_cidr##*=}
sed -i 's@"Network":.*"@"Network": "'$cluster_cidr'"@' /tmp/sdn.yaml

kubectl create -f /tmp/sdn.yaml

$DIR/tools/pull_containers.sh kube-system
$DIR/tools/wait_for_pods.sh kube-system 240
