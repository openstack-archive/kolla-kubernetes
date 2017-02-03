#!/bin/bash -xe

VERSION=0.5.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=${3:-172.18.0.1}

. "$DIR/tests/bin/common_workflow_config.sh"
. "$DIR/tests/bin/common_ceph_config.sh"

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface
}

function ceph_config {
    common_ceph_config $1
}

function entry_point_config {
    general_config
    ceph_config
}

tunnel_interface=${4:-docker0}
if [ "x$1" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
    # if this is being run remotely the netstat will fail,
    # so fallback to the passed in interface name
    if [ ! -z "$interface" ]; then
        tunnel_interface=$interface
    fi
fi

base_distro="$2"

common_vars="kube_logger=false,base_distro=$base_distro"

helm install kolla/mariadb --version $VERSION \
    --namespace kolla --name mariadb --set "$common_vars,element_name=mariadb" \
    --values <(entry_point_config $1)

helm install kolla/memcached --version $VERSION \
    --namespace kolla --name memcached \
    --set "$common_vars,element_name=memcached" \
    --values <(entry_point_config $1)

helm install kolla/rabbitmq --version $VERSION \
    --namespace kolla --name rabbitmq --set "$common_vars" \
    --values <(entry_point_config $1)

$DIR/tools/wait_for_pods.py mariadb,memcached,rabbitmq running,succeeded

helm install kolla/keystone --version $VERSION \
    --namespace kolla --name keystone --set "$common_vars,element_name=keystone" \
    --values <(entry_point_config $1)

$DIR/tools/wait_for_pods.py keystone running,succeeded

helm install kolla/openvswitch --version $VERSION \
  --namespace kolla --name openvswitch --values  <(entry_point_config $1)

$DIR/tools/wait_for_pods.py openvswitch running

kollakube res create bootstrap openvswitch-set-external-ip

$DIR/tools/wait_for_pods.py openvswitch-set-external succeeded

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

[ -d "$WORKSPACE/logs" ] &&
kubectl get jobs -o json > $WORKSPACE/logs/jobs-after-bootstrap.json \
    --namespace=kolla || true

$DIR/tests/bin/endpoint_test.sh

[ -d "$WORKSPACE/logs" ] && openstack catalog list > \
    $WORKSPACE/logs/openstack-catalog-after-bootstrap.json || true

helm install kolla/cinder-volume-ceph-statefulset --version $VERSION \
    --set "$common_vars,element_name=cinder" --namespace kolla \
    --name cinder-volume-ceph-statefulset

helm install kolla/cinder-control --version $VERSION \
    --namespace kolla --name cinder --set "$common_vars,element_name=cinder" \
    --values <(entry_point_config $1)

helm install kolla/glance --version $VERSION \
    --namespace kolla --name glance --set "$common_vars,element_name=glance" \
    --values <(entry_point_config $1)

helm install kolla/neutron --version $VERSION \
    --namespace kolla --name neutron --values  <(entry_point_config $1)

$DIR/tools/wait_for_pods.py cinder,glance,neutron running,succeeded

helm ls

helm install kolla/nova-control --version $VERSION  --namespace kolla \
    --name nova-control --set "$common_vars,element_name=nova" \
    --values <(entry_point_config $1)

helm install kolla/nova-compute --version $VERSION  --namespace kolla \
    --name nova-compute --set "$common_vars,element_name=nova" \
    --values <(entry_point_config $1)

helm install kolla/horizon --version $VERSION \
    --namespace kolla --name horizon \
    --set "$common_vars,element_name=horizon" \
    --values <(entry_point_config $1)

#kollakube res create pod keepalived

$DIR/tools/wait_for_pods.py nova,horizon running,succeeded

kollakube res delete bootstrap openvswitch-set-external-ip
