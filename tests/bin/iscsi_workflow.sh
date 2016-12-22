#!/bin/bash -xe

function lvmbackend_values {
    echo "lvm_backends:"
    echo "  - '172.18.0.1': 'cinder-volumes'"
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/setup_helm_entrypint_config.sh"

tunnel_interface=docker0

base_distro="$2"

common_vars="ceph_backend=false,enable_kube_logger=false,kolla_base_distro=$base_distro"

kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume iscsid tgtd keepalived;

kollakube res create secret nova-libvirt

for x in mariadb rabbitmq glance; do
    helm install kolla/$x-pv --version 3.0.0-1 \
        --name $x-pv --set "element_name=$x,storage_provider=host"
    helm install kolla/$x-pvc --version 3.0.0-1 --namespace kolla \
        --name $x-pvc --set "element_name=$x,storage_provider=host"
done

helm install kolla/memcached-svc --version 3.0.0-1 \
    --namespace kolla --name memcached-svc --set element_name=memcached

helm install kolla/mariadb-svc --version 3.0.0-1 \
    --namespace kolla --name mariadb-svc --set element_name=mariadb

helm install kolla/rabbitmq-svc --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-svc --set element_name=rabbitmq

helm install kolla/keystone-admin-svc --version 3.0.0-1 \
    --namespace kolla --name keystone-admin-svc \
    --set "element_name=keystone-admin"

helm install kolla/keystone-public-svc --version 3.0.0-1 \
    --namespace kolla --name keystone-public-svc \
    --set "element_name=keystone-public,element_port_external=true,kolla_kubernetes_external_vip=$IP"

helm install kolla/keystone-internal-svc --version 3.0.0-1 \
    --namespace kolla --name keystone-internal-svc \
    --set "element_name=keystone-internal"

helm install kolla/glance-api-svc --version 3.0.0-1 \
    --namespace kolla --name glance-api-svc \
    --set "element_port_external=true,kolla_kubernetes_external_vip=$IP"

helm install kolla/glance-registry-svc --version 3.0.0-1 \
    --namespace kolla --name glance-registry-svc

helm install kolla/neutron-server-svc --version 3.0.0-1 \
    --namespace kolla --name neutron-server-svc \
    --set "element_port_external=true,kolla_kubernetes_external_vip=$IP"

helm install kolla/cinder-api-svc --version 3.0.0-1 \
    --namespace kolla --name cinder-api-svc \
    --set "element_name=cinder,element_port_external=true,kolla_kubernetes_external_vip=$IP"

helm install kolla/nova-api-svc --version 3.0.0-1 \
    --namespace kolla --name nova-api-svc \
    --set "element_name=nova,element_port_external=true,kolla_kubernetes_external_vip=$IP"

helm install kolla/nova-metadata-svc --version 3.0.0-1 \
    --namespace kolla --name nova-metadata-svc \
    --set "element_name=nova"

helm install kolla/nova-novncproxy-svc --version 3.0.0-1 \
    --namespace kolla --name nova-novncproxy-svc --set element_name=nova

helm install kolla/horizon-svc --version 3.0.0-1 \
    --namespace kolla --name horizon-svc --set element_name=horizon

helm install kolla/mariadb-init-element --version 3.0.0-1 \
    --namespace kolla --name mariadb-init-element \
    --set "$common_vars,element_name=mariadb"

helm install kolla/rabbitmq-init-element --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-init-element \
    --set "element_name=rabbitmq,rabbitmq_cluster_cookie=67"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in mariadb rabbitmq; do
    helm delete $x-init-element --purge
done

helm install kolla/mariadb-pod --version 3.0.0-1 \
    --namespace kolla --name mariadb-pod --set "$common_vars,element_name=mariadb"

helm install kolla/memcached --version 3.0.0-1 \
    --set "enable_kube_logger=false,element_name=memcached" \
    --namespace kolla --name memcached

helm install kolla/rabbitmq-pod --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-pod --set "$common_vars,element_name=rabbitmq"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install --debug kolla/keystone-create-db --version 3.0.0-1 \
    --set element_name=keystone \
    --namespace kolla \
    --name keystone-create-db

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm delete keystone-create-db

helm install --debug kolla/keystone-manage-db --version 3.0.0-1 \
    --namespace kolla \
    --name keystone-manage-db

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm delete keystone-manage-db

kollakube template bootstrap keystone-endpoints

helm install --debug kolla/keystone-create-endpoints --version 3.0.0-1 \
    --namespace kolla \
    --set element_name=keystone,public_host=$IP \
    --name keystone-create-endpoints

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install --debug kolla/keystone-api --version 3.0.0-1 \
    --set "$common_vars" \
    --namespace kolla \
    --name keystone

$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

helm install kolla/neutron-create-keystone-service --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-service --set "$common_vars"

helm install kolla/glance-create-keystone-service --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-service --set "$common_vars"

helm install kolla/cinder-create-keystone-service --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-service --set "$common_vars"

helm install kolla/cinder-create-keystone-user --debug --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-user

helm install kolla/glance-create-keystone-user --debug --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-user

helm install kolla/neutron-create-keystone-user --debug --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-user

helm install kolla/nova-create-keystone-service --debug --version 3.0.0-1 \
    --namespace kolla --name nova-create-keystone-service

helm install kolla/nova-create-keystone-user --debug --version 3.0.0-1 \
    --namespace kolla --name nova-create-keystone-user

kollakube res create bootstrap \
    cinder-create-keystone-endpoint-publicv2

helm install kolla/cinder-create-keystone-endpoint-public --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-public --set "$common_vars,kolla_kubernetes_external_vip=172.18.0.1"

helm install kolla/glance-create-keystone-endpoint-public --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-endpoint-public --set "$common_vars,kolla_kubernetes_external_vip=172.18.0.1"

helm install kolla/nova-create-keystone-endpoint-public --version 3.0.0-1 \
    --namespace kolla --name nova-create-keystone-endpoint-public --set "$common_vars,kolla_kubernetes_external_vip=172.18.0.1"

helm install kolla/neutron-create-keystone-endpoint-public --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-endpoint-public --set "$common_vars,kolla_kubernetes_external_vip=172.18.0.1"
helm install kolla/neutron-create-keystone-endpoint-internal --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-endpoint-internal --set "$common_vars"
helm install kolla/neutron-create-keystone-endpoint-admin --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-endpoint-admin --set "$common_vars"

$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap \
    cinder-create-keystone-endpoint-publicv2

for x in cinder glance neutron nova; do
    helm delete --purge $x-create-keystone-user
done

helm install kolla/glance-create-db --version 3.0.0-1 \
    --namespace kolla --name glance-create-db --set "$common_vars"

helm install kolla/glance-manage-db --version 3.0.0-1 \
    --namespace kolla --name glance-manage-db --set "$common_vars"

helm install kolla/cinder-create-db --version 3.0.0-1 \
    --set "element_name=cinder,image_tag=3.0.1" \
    --namespace kolla \
    --name cinder-create-db

helm install kolla/cinder-manage-db --version 3.0.0-1 \
    --set "element_name=cinder,image_tag=3.0.1" \
    --namespace kolla \
    --name cinder-manage-db

kollakube res create bootstrap \
    cinder-create-keystone-endpoint-internalv2 \
    cinder-create-keystone-endpoint-adminv2

helm install kolla/cinder-create-keystone-endpoint-internal --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-admin --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-admin --set "$common_vars"

helm install kolla/glance-create-keystone-endpoint-internal --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/glance-create-keystone-endpoint-admin --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-endpoint-admin --set "$common_vars"

helm install kolla/nova-create-keystone-endpoint-internal --version 3.0.0-1 \
    --namespace kolla --name nova-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/nova-create-keystone-endpoint-admin --version 3.0.0-1 \
    --namespace kolla --name nova-create-keystone-endpoint-admin --set "$common_vars"

for x in nova nova-api neutron; do
    helm install kolla/$x-create-db --version 3.0.0-1 \
        --set element_name=$x --namespace kolla \
        --name $x-create-db
done

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in nova-api neutron; do
    helm install kolla/$x-manage-db --version 3.0.0-1 \
        --set element_name=$x --namespace kolla \
        --name $x-manage-db
done

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

[ -d "$WORKSPACE/logs" ] &&
kubectl get jobs -o json > $WORKSPACE/logs/jobs-after-bootstrap.json \
    --namespace=kolla || true

$DIR/tests/bin/endpoint_test.sh

[ -d "$WORKSPACE/logs" ] && openstack catalog list > \
    $WORKSPACE/logs/openstack-catalog-after-bootstrap.json || true

for x in nova nova-api cinder neutron glance; do
    helm delete --purge $x-create-db
done

for x in nova-api cinder neutron glance; do
    helm delete --purge $x-manage-db
done

kollakube res delete bootstrap \
    cinder-create-keystone-endpoint-internalv2 \
    cinder-create-keystone-endpoint-adminv2

for x in glance neutron cinder nova; do
    helm delete --purge $x-create-keystone-service
    helm delete --purge $x-create-keystone-endpoint-public
    helm delete --purge $x-create-keystone-endpoint-internal
    helm delete --purge $x-create-keystone-endpoint-admin
done

helm install kolla/cinder-volume-lvm --debug --version 3.0.0-1 \
    --set "$common_vars,element_name=cinder-volume" --namespace kolla \
    --name cinder-volume-lvm --values <(lvmbackend_values)

helm install kolla/cinder-api --version 3.0.0-1 \
    --set "$common_vars,image_tag=3.0.1" --namespace kolla \
    --name cinder-api

helm install kolla/cinder-scheduler --version 3.0.0-1 \
    --set "$common_vars,element_name=cinder-scheduler,image_tag=3.0.1" \
    --namespace kolla --name cinder-scheduler

helm install kolla/glance-api --version 3.0.0-1 \
    --set "$common_vars" \
    --namespace kolla --name glance-api

helm install kolla/glance-registry --version 3.0.0-1 \
    --set "$common_vars" --namespace kolla \
    --name glance-registry

helm ls

for x in nova-api nova-conductor nova-scheduler nova-consoleauth \
    nova-novncproxy; do
    helm install kolla/$x --version 3.0.0-1 \
      --set "$common_vars,element_name=$x" \
      --namespace kolla --name $x
done

helm install kolla/horizon-api --version 3.0.0-1 \
    --set "$common_vars,element_name=horizon" \
    --namespace kolla --name horizon-api

helm install kolla/neutron-server --version 3.0.0-1 \
    --set "$common_vars" \
    --namespace kolla --name neutron-server

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/neutron-dhcp-agent --version 3.0.0-1 \
    --set "$common_vars,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-dhcp-agent

helm install kolla/neutron-metadata-agent --version 3.0.0-1 \
    --set "$common_vars,type=network" \
    --namespace kolla --name neutron-metadata-agent-network

helm install kolla/neutron-l3-agent --version 3.0.0-1 \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-l3-agent-network

helm install kolla/neutron-openvswitch-agent --version 3.0.0-1 \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-openvswitch-agent-network

helm install kolla/openvswitch-ovsdb --version 3.0.0-1 \
    --set "$common_vars,type=network,selector_key=kolla_controller" \
    --namespace kolla --name openvswitch-ovsdb-network

helm install kolla/openvswitch-vswitchd --version 3.0.0-1 \
    --set enable_kube_logger=false,type=network,selector_key=kolla_controller \
    --namespace kolla --name openvswitch-vswitchd-network

kollakube res create bootstrap openvswitch-set-external-ip

helm install kolla/nova-libvirt --version 3.0.0-1 \
    --set "$common_vars,element_name=nova-libvirt,libvirt_ceph=false" \
    --namespace kolla --name nova-libvirt

helm install kolla/nova-compute --version 3.0.0-1 \
    --set "$common_vars,tunnel_interface=$tunnel_interface,element_name=nova-compute,nova_ceph=false" \
    --namespace kolla --name nova-compute

helm install kolla/iscsid --version 3.0.0-1 --debug\
    --set "$common_vars,element_name=iscsid" \
    --namespace kolla --name iscsid

helm install kolla/tgtd --version 3.0.0-1 --debug\
    --set "$common_vars,element_name=tgtd" \
    --namespace kolla --name tgtd

#kollakube res create pod keepalived

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap openvswitch-set-external-ip
