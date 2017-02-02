#!/bin/bash -xe

VERSION=0.4.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/common_entrypoint_config.sh"

function entrypoint_config {
    common_entrypoint_config $IP $base_distro $tunnel_interface $1
}

tunnel_interface=docker0
base_distro="$2"

for x in horizon nova cinder glance neutron openvswitch memcached rabbitmq \
         mariadb; do
   helm ls | grep $x | awk {'print $x'} | xargs helm delete --purge || true
done
$DIR/tools/wait_for_pods_termination.sh kolla

helm install kolla/compute-kit --debug --version $VERSION \
    --namespace kolla --name compute-kit \
    --values <(entrypoint_config)
