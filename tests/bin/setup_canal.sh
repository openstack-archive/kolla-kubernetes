#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

url="https://raw.githubusercontent.com/projectcalico/canal/master"
url="$url/k8s-install/1.6/canal.yaml"

curl "$url" -o /tmp/canal.yaml

url="https://raw.githubusercontent.com/projectcalico/canal/master"
url="$url/k8s-install/1.6/rbac.yaml"

curl "$url" -o /tmp/rbac.yaml

kubectl create -f /tmp/rbac.yaml

#
# Instead of hardcoding cluster cidr, let's get it from
# controller manager manifest.
#
cluster_cidr=$(sudo grep cluster-cidr /etc/kubernetes/manifests/kube-controller-manager.yaml || true)
cluster_cidr=${cluster_cidr##*=}

#
# NOTE(sbezverk) Temporary workaround to canal.yaml bug. It is
# missing net-conf.json file. The code will add it if it does not exist.
#
network_conf=$(grep net-conf.json /tmp/canal.yaml || true)
if [ "x$network_conf" == "x" ]; then
   sed -i '/masquerade:/a\
  net-conf.json: |\
    {\
      "Network": "'$cluster_cidr'",\
      "Backend": {\
        "Type": "vxlan"\
      }\
    }' /tmp/canal.yaml
else
   sed -i 's@"Network":.*"@"Network": "'$cluster_cidr'"@' /tmp/canal.yaml
fi

kubectl create -f /tmp/canal.yaml

$DIR/tools/pull_containers.sh kube-system
$DIR/tools/wait_for_pods.sh kube-system 240
