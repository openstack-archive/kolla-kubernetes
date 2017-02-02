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

for x in horizon nova cinder glance neutron openvswitch memcached \
         rabbitmq keystone mariadb; do
   helm ls | grep $x | awk {'print $1'} | xargs helm delete --purge || true
done

$DIR/tools/wait_for_pods_termination.sh kolla

kubectl get pods -n kolla
kubectl get svc -n kolla

helm install kolla/compute-kit-0.4.0 --version $VERSION \
    --namespace kolla --name compute-kit-0.4.0 \
    --values <(entrypoint_config)

$DIR/tools/wait_for_pods.sh kolla 600
