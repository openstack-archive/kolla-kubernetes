#!/bin/bash -xe

VERSION=0.5.0-1

function lvmbackend_values {
    echo "lvm_backends:"
    echo "  - '172.18.0.1': 'cinder-volumes'"
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/setup_helm_entrypint_config.sh"

tunnel_interface=docker0

base_distro="$2"

common_vars="ceph_backend=false,kube_logger=false,base_distro=$base_distro"

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
    helm install kolla/$x-pv --version $VERSION \
        --name $x-pv --set "element_name=$x,storage_provider=host"
    helm install kolla/$x-pvc --version $VERSION --namespace kolla \
        --name $x-pvc --set "element_name=$x,storage_provider=host"
done

helm install kolla/memcached-svc --version $VERSION \
    --namespace kolla --name memcached-svc --set element_name=memcached

helm install kolla/mariadb-svc --version $VERSION \
    --namespace kolla --name mariadb-svc --set element_name=mariadb

helm install kolla/rabbitmq-svc --version $VERSION \
    --namespace kolla --name rabbitmq-svc --set element_name=rabbitmq

helm install kolla/keystone-admin-svc --version $VERSION \
    --namespace kolla --name keystone-admin-svc \
    --set "element_name=keystone-admin"

helm install kolla/keystone-public-svc --version $VERSION \
    --namespace kolla --name keystone-public-svc \
    --set "element_name=keystone-public,port_external=true,external_vip=$IP"

helm install kolla/keystone-internal-svc --version $VERSION \
    --namespace kolla --name keystone-internal-svc \
    --set "element_name=keystone-internal"

helm install kolla/glance-api-svc --version $VERSION \
    --namespace kolla --name glance-api-svc \
    --set "port_external=true,external_vip=$IP"

helm install kolla/glance-registry-svc --version $VERSION \
    --namespace kolla --name glance-registry-svc

helm install kolla/neutron-server-svc --version $VERSION \
    --namespace kolla --name neutron-server-svc \
    --set "port_external=true,external_vip=$IP"

helm install kolla/cinder-api-svc --version $VERSION \
    --namespace kolla --name cinder-api-svc \
    --set "element_name=cinder,port_external=true,external_vip=$IP"

helm install kolla/nova-api-svc --version $VERSION \
    --namespace kolla --name nova-api-svc \
    --set "element_name=nova,port_external=true,external_vip=$IP"

helm install kolla/nova-metadata-svc --version $VERSION \
    --namespace kolla --name nova-metadata-svc \
    --set "element_name=nova"

helm install kolla/nova-novncproxy-svc --version $VERSION \
    --namespace kolla --name nova-novncproxy-svc --set element_name=nova

helm install kolla/horizon-svc --version $VERSION \
    --namespace kolla --name horizon-svc --set element_name=horizon

helm install kolla/mariadb-init-element-job --version $VERSION \
    --namespace kolla --name mariadb-init-element-job \
    --set "$common_vars,element_name=mariadb"

helm install kolla/rabbitmq-init-element-job --version $VERSION \
    --namespace kolla --name rabbitmq-init-element-job \
    --set "$common_vars,element_name=rabbitmq,cookie=67"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in mariadb rabbitmq; do
    helm delete $x-init-element-job --purge
done

helm install kolla/mariadb-statefulset --version $VERSION \
    --namespace kolla --name mariadb-statefulset --set "$common_vars,element_name=mariadb"

helm install kolla/memcached-deployment --version $VERSION \
    --set "$common_vars,element_name=memcached" \
    --namespace kolla --name memcached-deployment

helm install kolla/rabbitmq-statefulset --version $VERSION \
    --namespace kolla --name rabbitmq-statefulset --set "$common_vars,element_name=rabbitmq"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install --debug kolla/keystone-create-db-job --version $VERSION \
    --set element_name=keystone \
    --namespace kolla \
    --name keystone-create-db \
    --set "$common_vars"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm delete keystone-create-db

helm install --debug kolla/keystone-manage-db-job --version $VERSION \
    --namespace kolla \
    --name keystone-manage-db \
    --set "$common_vars"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm delete keystone-manage-db

kollakube template bootstrap keystone-endpoints

helm install --debug kolla/keystone-create-endpoints-job --version $VERSION \
    --namespace kolla \
    --set $common_vars,element_name=keystone,public_host=$IP \
    --name keystone-create-endpoints-job

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install --debug kolla/keystone-api-deployment --version $VERSION \
    --set "$common_vars" \
    --namespace kolla \
    --name keystone

$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

helm install kolla/neutron-create-keystone-service-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-service --set "$common_vars"

helm install kolla/glance-create-keystone-service-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-service --set "$common_vars"

helm install kolla/cinder-create-keystone-service-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-service --set "$common_vars"

helm install kolla/cinder-create-keystone-user-job --debug --version $VERSION \
    --namespace kolla --name cinder-create-keystone-user --set "$common_vars"

helm install kolla/glance-create-keystone-user-job --debug --version $VERSION \
    --namespace kolla --name glance-create-keystone-user --set "$common_vars"

helm install kolla/neutron-create-keystone-user-job --debug --version $VERSION \
    --namespace kolla --name neutron-create-keystone-user --set "$common_vars"

helm install kolla/nova-create-keystone-service-job --debug --version $VERSION \
    --namespace kolla --name nova-create-keystone-service --set "$common_vars"

helm install kolla/nova-create-keystone-user-job --debug --version $VERSION \
    --namespace kolla --name nova-create-keystone-user --set "$common_vars"

kollakube res create bootstrap \
    cinder-create-keystone-endpoint-publicv2

helm install kolla/cinder-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-public --set "$common_vars,external_vip=172.18.0.1"

helm install kolla/glance-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-endpoint-public --set "$common_vars,external_vip=172.18.0.1"

helm install kolla/nova-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-endpoint-public --set "$common_vars,external_vip=172.18.0.1"

helm install kolla/neutron-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-endpoint-public --set "$common_vars,external_vip=172.18.0.1"
helm install kolla/neutron-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-endpoint-internal --set "$common_vars"
helm install kolla/neutron-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-endpoint-admin --set "$common_vars"

$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap \
    cinder-create-keystone-endpoint-publicv2

for x in cinder glance neutron nova; do
    helm delete --purge $x-create-keystone-user
done

helm install kolla/glance-create-db-job --version $VERSION \
    --namespace kolla --name glance-create-db --set "$common_vars"

helm install kolla/glance-manage-db-job --version $VERSION \
    --namespace kolla --name glance-manage-db --set "$common_vars"

helm install kolla/cinder-create-db-job --version $VERSION \
    --set "$common_vars,element_name=cinder" \
    --namespace kolla \
    --name cinder-create-db

helm install kolla/cinder-manage-db-job --version $VERSION \
    --set "$common_vars,element_name=cinder,image_tag=3.0.1" \
    --namespace kolla \
    --name cinder-manage-db

kollakube res create bootstrap \
    cinder-create-keystone-endpoint-internalv2 \
    cinder-create-keystone-endpoint-adminv2

helm install kolla/cinder-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-admin --set "$common_vars"

helm install kolla/glance-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/glance-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-endpoint-admin --set "$common_vars"

helm install kolla/nova-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/nova-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-endpoint-admin --set "$common_vars"

for x in nova nova-api neutron; do
    helm install kolla/$x-create-db-job --version $VERSION \
        --set $common_vars,element_name=$x --namespace kolla \
        --name $x-create-db
done

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in nova-api neutron; do
    helm install kolla/$x-manage-db-job --version $VERSION \
        --set $common_vars,element_name=$x --namespace kolla \
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

helm install kolla/cinder-volume-lvm-daemonset --debug --version $VERSION \
    --set "$common_vars,element_name=cinder-volume" --namespace kolla \
    --name cinder-volume-lvm-daemonset --values <(lvmbackend_values)

helm install kolla/cinder-api-deployment --version $VERSION \
    --set "$common_vars,image_tag=3.0.1" --namespace kolla \
    --name cinder-api

helm install kolla/cinder-scheduler-statefulset --version $VERSION \
    --set "$common_vars,element_name=cinder-scheduler,image_tag=3.0.1" \
    --namespace kolla --name cinder-scheduler

helm install kolla/glance-api-deployment --version $VERSION \
    --set "$common_vars" \
    --namespace kolla --name glance-api-deployment

helm install kolla/glance-registry-deployment --version $VERSION \
    --set "$common_vars" --namespace kolla \
    --name glance-registry

helm ls

for x in nova-api nova-novncproxy; do
    helm install kolla/$x-deployment --version $VERSION \
      --set "$common_vars,element_name=$x" \
      --namespace kolla --name $x
done

for x in nova-conductor nova-scheduler nova-consoleauth; do
    helm install kolla/$x-statefulset --version $VERSION \
      --set "$common_vars,element_name=$x" \
      --namespace kolla --name $x
done

helm install kolla/horizon-deployment --version $VERSION \
    --set "$common_vars,element_name=horizon" \
    --namespace kolla --name horizon-deployment

helm install kolla/neutron-server-deployment --version $VERSION \
    --set "$common_vars" \
    --namespace kolla --name neutron-server

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/neutron-dhcp-agent-daemonset --version $VERSION \
    --set "$common_vars,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-dhcp-agent-daemonset

helm install kolla/neutron-metadata-agent-daemonset --version $VERSION \
    --set "$common_vars,type=network" \
    --namespace kolla --name neutron-metadata-agent-network

helm install kolla/neutron-l3-agent-daemonset --version $VERSION \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-l3-agent-network

helm install kolla/neutron-openvswitch-agent-daemonset --version $VERSION \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-openvswitch-agent-network

helm install kolla/openvswitch-ovsdb-daemonset --version $VERSION \
    --set "$common_vars,type=network,selector_key=kolla_controller" \
    --namespace kolla --name openvswitch-ovsdb-network

helm install kolla/openvswitch-vswitchd-daemonset --version $VERSION \
    --set $common_vars,type=network,selector_key=kolla_controller \
    --namespace kolla --name openvswitch-vswitchd-network

kollakube res create bootstrap openvswitch-set-external-ip

helm install kolla/nova-libvirt-daemonset --version $VERSION \
    --set "$common_vars,element_name=nova-libvirt,libvirt_ceph=false" \
    --namespace kolla --name nova-libvirt-daemonset

helm install kolla/nova-compute-daemonset --version $VERSION \
    --set "$common_vars,tunnel_interface=$tunnel_interface,element_name=nova-compute,nova_ceph=false" \
    --namespace kolla --name nova-compute-daemonset

helm install kolla/iscsid-daemonset --version $VERSION --debug\
    --set "$common_vars,element_name=iscsid" \
    --namespace kolla --name iscsid-daemonset

helm install kolla/tgtd-daemonset --version $VERSION --debug\
    --set "$common_vars,element_name=tgtd" \
    --namespace kolla --name tgtd-daemonset

#kollakube res create pod keepalived

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap openvswitch-set-external-ip
