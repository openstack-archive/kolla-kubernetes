#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

tunnel_interface=docker0
if [ "x$1" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
    tunnel_interface=$interface
fi

base_distro="$2"

common_vars="enable_kube_logger=false,kolla_base_distro=$base_distro"

kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume keepalived;

kollakube res create secret nova-libvirt

for x in mariadb rabbitmq; do
    kollakube res create pv $x
    kollakube res create pvc $x
done

kollakube res create svc mariadb memcached keystone-admin keystone-public \
    nova-api glance-api glance-registry \
    neutron-server nova-metadata nova-novncproxy horizon cinder-api

helm install kolla/rabbitmq-svc --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-svc --set name=rabbitmq

kollakube res create bootstrap mariadb-bootstrap

helm install kolla/rabbitmq-job --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-job --set name=rabbitmq

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap mariadb-bootstrap

[ -d "$WORKSPACE/logs" ] &&
kubectl get jobs --namespace=kolla >> $WORKSPACE/logs/rabbitmq-debug.log

helm ls | grep rabbitmq-job | awk '{print "helm delete "$1}' | sh -l

kollakube res create pod mariadb memcached

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

[ -d "$WORKSPACE/logs" ] && 
kubectl get pods --namespace=kolla >> $WORKSPACE/logs/rabbitmq-debug.log

helm install kolla/rabbitmq-pod --debug --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-pod --set "$common_vars,name=rabbitmq"

[ -d "$WORKSPACE/logs" ] &&
kubectl get petset --namespace=kolla >> $WORKSPACE/logs/rabbitmq-debug.log

[ -d "$WORKSPACE/logs" ] &&
kubectl describe petset rabbitmq --namespace=kolla >> $WORKSPACE/logs/rabbitmq-debug.log

kollakube resource create bootstrap keystone-create-db keystone-endpoints \
    keystone-manage-db

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube resource delete bootstrap keystone-create-db keystone-endpoints \
    keystone-manage-db

kollakube res create pod keystone

$DIR/tools/wait_for_pods.sh kolla

kollakube res create bootstrap nova-create-keystone-user \
    glance-create-keystone-user cinder-create-keystone-user \
    neutron-create-keystone-user \
    nova-create-keystone-endpoint-public \
    glance-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-publicv2 \
    neutron-create-keystone-endpoint-public

$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap nova-create-keystone-user \
    glance-create-keystone-user cinder-create-keystone-user \
    neutron-create-keystone-user \
    nova-create-keystone-endpoint-public \
    glance-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-public \
    cinder-create-keystone-endpoint-publicv2 \
    neutron-create-keystone-endpoint-public

kollakube res create bootstrap glance-create-db glance-manage-db \
    nova-create-api-db nova-create-db neutron-create-db neutron-manage-db \
    cinder-create-db cinder-manage-db \
    nova-create-keystone-endpoint-internal \
    glance-create-keystone-endpoint-internal \
    cinder-create-keystone-endpoint-internal \
    cinder-create-keystone-endpoint-internalv2 \
    neutron-create-keystone-endpoint-internal \
    nova-create-keystone-endpoint-admin \
    glance-create-keystone-endpoint-admin \
    cinder-create-keystone-endpoint-admin \
    cinder-create-keystone-endpoint-adminv2 \
    neutron-create-keystone-endpoint-admin

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

[ -d "$WORKSPACE/logs" ] &&
kubectl get jobs -o json > $WORKSPACE/logs/jobs-after-bootstrap.json \
    --namespace=kolla || true

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

$DIR/tests/bin/endpoint_test.sh

[ -d "$WORKSPACE/logs" ] && openstack catalog list > \
    $WORKSPACE/logs/openstack-catalog-after-bootstrap.json || true

kollakube res delete bootstrap glance-create-db glance-manage-db \
    nova-create-api-db nova-create-db neutron-create-db neutron-manage-db \
    cinder-create-db cinder-manage-db \
    nova-create-keystone-endpoint-internal \
    glance-create-keystone-endpoint-internal \
    cinder-create-keystone-endpoint-internal \
    cinder-create-keystone-endpoint-internalv2 \
    neutron-create-keystone-endpoint-internal \
    nova-create-keystone-endpoint-admin \
    glance-create-keystone-endpoint-admin \
    cinder-create-keystone-endpoint-admin \
    cinder-create-keystone-endpoint-adminv2 \
    neutron-create-keystone-endpoint-admin

kollakube res create pod nova-api nova-conductor nova-scheduler glance-api \
    glance-registry horizon nova-consoleauth nova-novncproxy \
    cinder-api cinder-scheduler cinder-volume-ceph

helm ls

helm install kolla/neutron-server --version 3.0.0-1 \
    --set "$common_vars" \
    --namespace kolla --name neutron-server

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res create pod neutron-dhcp-agent neutron-metadata-agent-network

helm install kolla/neutron-l3-agent --version 3.0.0-1 \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-l3-agent-network

helm install kolla/neutron-openvswitch-agent --version 3.0.0-1 \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-openvswitch-agent-network

[ "x$1" != "xexternal-ovs" ] &&
    helm install kolla/openvswitch-ovsdb --version 3.0.0-1 \
    --set "$common_vars,type=network,selector_key=kolla_controller" \
    --namespace kolla --name openvswitch-ovsdb-network &&
    helm install kolla/openvswitch-vswitchd --version 3.0.0-1 \
    --set enable_kube_logger=false,type=network,selector_key=kolla_controller \
    --namespace kolla --name openvswitch-vswitchd-network

[ "x$1" == "xceph-multi" ] &&
    helm install kolla/openvswitch-ovsdb --version 3.0.0-1 \
    --set "$common_vars,type=compute,selector_key=kolla_compute" \
    --namespace kolla --name openvswitch-ovsdb-compute &&
    helm install kolla/neutron-openvswitch-agent --version 3.0.0-1 \
    --set "$common_vars,type=compute,selector_key=kolla_compute,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-openvswitch-agent-compute &&
    helm install kolla/openvswitch-vswitchd --version 3.0.0-1 \
    --set enable_kube_logger=false,type=compute,selector_key=kolla_compute \
    --namespace kolla --name openvswitch-vswitchd-compute

kollakube res create bootstrap openvswitch-set-external-ip
kollakube res create pod nova-libvirt
kollakube res create pod nova-compute
#kollakube res create pod keepalived

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap openvswitch-set-external-ip

$DIR/tools/wait_for_pods.sh kolla
