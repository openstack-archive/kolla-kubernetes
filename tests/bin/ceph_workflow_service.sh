#!/bin/bash -xe

VERSION=0.5.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/common_workflow_config.sh"
. "$DIR/tests/bin/common_ceph_config.sh"

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface
}

function ceph_config {
    common_ceph_config $job 
}

tunnel_interface=docker0
if [ "x$1" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
    tunnel_interface=$interface
fi

base_distro="$2"
job="$1"

common_vars="kube_logger=false,base_distro=$base_distro"

helm install kolla/mariadb --version $VERSION \
    --namespace kolla --name mariadb \
    --values <(general_config) --values <(ceph_config)

helm install kolla/memcached --version $VERSION \
    --namespace kolla --name memcached \
    --values <(general_config) --values <(ceph_config)

helm install kolla/rabbitmq --version $VERSION \
    --namespace kolla --name rabbitmq \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/keystone --version $VERSION \
    --namespace kolla --name keystone \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/openvswitch --version $VERSION \
  --namespace kolla --name openvswitch \
  --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res create bootstrap openvswitch-set-external-ip

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla


$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

[ -d "$WORKSPACE/logs" ] &&
kubectl get jobs -o json > $WORKSPACE/logs/jobs-after-bootstrap.json \
    --namespace=kolla || true

$DIR/tests/bin/endpoint_test.sh

[ -d "$WORKSPACE/logs" ] && openstack catalog list > \
    $WORKSPACE/logs/openstack-catalog-after-bootstrap.json || true

helm install kolla/cinder-volume-ceph-statefulset --version $VERSION \
    --namespace kolla --name cinder-volume-ceph-statefulset \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-control --version $VERSION \
    --namespace kolla --name cinder \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance --version $VERSION \
    --namespace kolla --name glance \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron --version $VERSION \
    --namespace kolla --name neutron \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm ls

helm install kolla/nova-control --version $VERSION  --namespace kolla \
    --name nova-control \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-compute --version $VERSION  --namespace kolla \
    --name nova-compute \
    --values <(general_config) --values <(ceph_config)

helm install kolla/horizon --version $VERSION \
    --namespace kolla --name horizon \
    --values <(general_config) --values <(ceph_config)

#kollakube res create pod keepalived

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap openvswitch-set-external-ip

$DIR/tools/wait_for_pods.sh kolla
