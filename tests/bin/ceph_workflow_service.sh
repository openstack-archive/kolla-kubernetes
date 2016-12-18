#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/setup_helm_entrypint_config.sh"

function ceph_values {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      ceph:"
    echo "          monitors:"
    addr=172.17.0.1
    if [ "x$1" == "xceph-multi" ]; then
        addr=$(cat /etc/nodepool/primary_node_private)
    fi
    echo "          - $addr"
}

function helm_entrypoint_mariadb {

for x in mariadb-statefulset mariadb-init-element-job; do
    echo "$x:"
    echo "    kube_logger: false"
    echo "    base_distro: $base_distro"
    echo "    kubernetes_entrypoint: true"
    echo "    kubernetes_entrypoint_image_tag: 3.0.1"
    echo "    element_name: mariadb"
done

    echo "mariadb-pv:"
    echo "   storage_provider: ceph"
    echo "   storage_provider_fstype: xfs"
    echo "   mariadb_volume_size_gb: 10"
    echo "   ceph:"
    echo "      monitors:"
    addr=172.17.0.1
    if [ "x$1" == "xceph-multi" ]; then
        addr=$(cat /etc/nodepool/primary_node_private)
    fi
    echo "          - $addr"
    echo "      pool: kollavolumes"
    echo "      secret_name: ceph-kolla"
    echo "      user: kolla"
    echo "mariadb-pvc:"
    echo "   storage_provider: ceph"
    echo "   storage_provider_fstype: xfs"
    echo "   mariadb_volume_size_gb: 10"

}

tunnel_interface=docker0
if [ "x$1" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
    tunnel_interface=$interface
fi

base_distro="$2"

common_vars="kube_logger=false,base_distro=$base_distro"

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

helm install --debug kolla/mariadb --version 3.0.0-1 \
    --namespace kolla --name mariadb --values <(helm_entrypoint_mariadb $1)

for x in rabbitmq glance; do
    helm install kolla/$x-pv --version 3.0.0-1 \
        --name $x-pv --set "element_name=$x,storage_provider=ceph" \
        --values <(ceph_values $1)
    helm install kolla/$x-pvc --version 3.0.0-1 --namespace kolla \
        --name $x-pvc --set "element_name=$x,storage_provider=ceph"
done

helm install kolla/memcached-svc --version 3.0.0-1 \
    --namespace kolla --name memcached-svc --set element_name=memcached

helm install kolla/rabbitmq-svc --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-svc --set element_name=rabbitmq

helm install kolla/keystone-admin-svc --version 3.0.0-1 \
    --namespace kolla --name keystone-admin-svc \
    --set "element_name=keystone-admin"

helm install kolla/keystone-public-svc --version 3.0.0-1 \
    --namespace kolla --name keystone-public-svc \
    --set "element_name=keystone-public,port_external=true,external_vip=$IP"

helm install kolla/keystone-internal-svc --version 3.0.0-1 \
    --namespace kolla --name keystone-internal-svc \
    --set "element_name=keystone-internal"

helm install kolla/glance-api-svc --version 3.0.0-1 \
    --namespace kolla --name glance-api-svc \
    --set "port_external=true,external_vip=$IP"

helm install kolla/glance-registry-svc --version 3.0.0-1 \
    --namespace kolla --name glance-registry-svc

helm install kolla/neutron-server-svc --version 3.0.0-1 \
    --namespace kolla --name neutron-server-svc \
    --set "port_external=true,external_vip=$IP"

helm install kolla/cinder-api-svc --version 3.0.0-1 \
    --namespace kolla --name cinder-api-svc \
    --set "element_name=cinder,port_external=true,external_vip=$IP"

helm install kolla/nova-api-svc --version 3.0.0-1 \
    --namespace kolla --name nova-api-svc \
    --set "element_name=nova,port_external=true,external_vip=$IP"

helm install kolla/nova-metadata-svc --version 3.0.0-1 \
    --namespace kolla --name nova-metadata-svc \
    --set "element_name=nova"

helm install kolla/nova-novncproxy-svc --version 3.0.0-1 \
    --namespace kolla --name nova-novncproxy-svc --set element_name=nova

helm install kolla/horizon-svc --version 3.0.0-1 \
    --namespace kolla --name horizon-svc --set element_name=horizon

helm install kolla/rabbitmq-init-element-job --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-init-element-job \
    --set "$common_vars,element_name=rabbitmq,cookie=67"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in mariadb rabbitmq; do
    helm delete $x-init-element-job --purge
done

helm install kolla/memcached-deployment --version 3.0.0-1 \
    --set "$common_vars,element_name=memcached" \
    --namespace kolla --name memcached-deployment

helm install kolla/rabbitmq-statefulset --version 3.0.0-1 \
    --namespace kolla --name rabbitmq-statefulset --set "$common_vars,element_name=rabbitmq"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install --debug kolla/keystone-create-db-job --version 3.0.0-1 \
    --set element_name=keystone \
    --namespace kolla \
    --name keystone-create-db \
    --set "$common_vars"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm delete keystone-create-db

helm install --debug kolla/keystone-manage-db-job --version 3.0.0-1 \
    --namespace kolla \
    --name keystone-manage-db \
    --set "$common_vars"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm delete keystone-manage-db

kollakube template bootstrap keystone-endpoints

helm install --debug kolla/keystone-create-endpoints-job --version 3.0.0-1 \
    --namespace kolla \
    --set $common_vars,element_name=keystone,public_host=$IP \
    --name keystone-create-endpoints-job

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install --debug kolla/keystone-api-deployment --version 3.0.0-1 \
    --set "$common_vars" \
    --namespace kolla \
    --name keystone

$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

helm install kolla/neutron-create-keystone-service-job --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-service --set "$common_vars"

helm install kolla/glance-create-keystone-service-job --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-service --set "$common_vars"

helm install kolla/cinder-create-keystone-service-job --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-service --set "$common_vars"

helm install kolla/cinder-create-keystone-servicev2-job --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-servicev2 --set "$common_vars"

helm install kolla/cinder-create-keystone-user-job --debug --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-user --set "$common_vars"

helm install kolla/glance-create-keystone-user-job --debug --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-user --set "$common_vars"

helm install kolla/neutron-create-keystone-user-job --debug --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-user --set "$common_vars"

helm install kolla/nova-create-keystone-user-job --debug --version 3.0.0-1 \
    --namespace kolla --name nova-create-keystone-user --set "$common_vars"

kollakube res create bootstrap \
    nova-create-keystone-endpoint-public

helm install kolla/cinder-create-keystone-endpoint-public-job --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-public --set "$common_vars,external_vip=172.18.0.1"
helm install kolla/cinder-create-keystone-endpoint-publicv2-job --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-publicv2 --set "$common_vars,external_vip=172.18.0.1"

helm install kolla/glance-create-keystone-endpoint-public-job --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-endpoint-public --set "$common_vars,external_vip=172.18.0.1"

helm install kolla/neutron-create-keystone-endpoint-public-job --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-endpoint-public --set "$common_vars,external_vip=172.18.0.1"
helm install kolla/neutron-create-keystone-endpoint-internal-job --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-endpoint-internal --set "$common_vars"
helm install kolla/neutron-create-keystone-endpoint-admin-job --version 3.0.0-1 \
    --namespace kolla --name neutron-create-keystone-endpoint-admin --set "$common_vars"

$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap \
    nova-create-keystone-endpoint-public

for x in cinder glance neutron nova; do
    helm delete --purge $x-create-keystone-user
done

helm install kolla/glance-create-db-job --version 3.0.0-1 \
    --namespace kolla --name glance-create-db --set "$common_vars"

helm install kolla/glance-manage-db-job --version 3.0.0-1 \
    --namespace kolla --name glance-manage-db --set "$common_vars,ceph_backend=true"

helm install kolla/cinder-create-db-job --version 3.0.0-1 \
    --set $common_vars,element_name=cinder \
    --namespace kolla \
    --name cinder-create-db

helm install kolla/cinder-manage-db-job --version 3.0.0-1 \
    --set $common_vars,element_name=cinder \
    --namespace kolla \
    --name cinder-manage-db

kollakube res create bootstrap nova-create-keystone-endpoint-internal \
    nova-create-keystone-endpoint-admin

helm install kolla/cinder-create-keystone-endpoint-internal-job --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-internalv2-job --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-internalv2 --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-admin-job --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-admin --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-adminv2-job --version 3.0.0-1 \
    --namespace kolla --name cinder-create-keystone-endpoint-adminv2 --set "$common_vars"

helm install kolla/glance-create-keystone-endpoint-internal-job --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/glance-create-keystone-endpoint-admin-job --version 3.0.0-1 \
    --namespace kolla --name glance-create-keystone-endpoint-admin --set "$common_vars"

for x in nova nova-api neutron; do
    helm install kolla/$x-create-db-job --version 3.0.0-1 \
        --set $common_vars,element_name=$x --namespace kolla \
        --name $x-create-db
done

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in nova-api neutron; do
    helm install kolla/$x-manage-db-job --version 3.0.0-1 \
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
    nova-create-keystone-endpoint-internal \
    nova-create-keystone-endpoint-admin \

for x in glance neutron cinder; do
    helm delete --purge $x-create-keystone-service
    helm delete --purge $x-create-keystone-endpoint-public
    helm delete --purge $x-create-keystone-endpoint-internal
    helm delete --purge $x-create-keystone-endpoint-admin
done

helm delete --purge cinder-create-keystone-servicev2
helm delete --purge cinder-create-keystone-endpoint-publicv2
helm delete --purge cinder-create-keystone-endpoint-internalv2
helm delete --purge cinder-create-keystone-endpoint-adminv2

helm install kolla/cinder-volume-ceph-statefulset --version 3.0.0-1 \
    --set "$common_vars,element_name=cinder" --namespace kolla \
    --name cinder-volume-ceph-statefulset

helm install kolla/cinder-api-deployment --version 3.0.0-1 \
    --set "$common_vars" --namespace kolla \
    --name cinder-api

helm install kolla/cinder-scheduler-statefulset --version 3.0.0-1 \
    --set "$common_vars,element_name=cinder-scheduler" \
    --namespace kolla --name cinder-scheduler

helm install kolla/glance-api-deployment --version 3.0.0-1 \
    --set "$common_vars,ceph_backend=true" \
    --namespace kolla --name glance-api-deployment

helm install kolla/glance-registry-deployment --version 3.0.0-1 \
    --set "$common_vars" --namespace kolla \
    --name glance-registry

helm ls

for x in nova-api nova-novncproxy; do
    helm install kolla/$x-deployment --version 3.0.0-1 \
      --set "$common_vars,element_name=$x" \
      --namespace kolla --name $x
done

for x in nova-conductor nova-scheduler nova-consoleauth; do
    helm install kolla/$x-statefulset --version 3.0.0-1 \
      --set "$common_vars,element_name=$x" \
      --namespace kolla --name $x
done

helm install kolla/horizon-deployment --version 3.0.0-1 \
    --set "$common_vars,element_name=horizon" \
    --namespace kolla --name horizon-deployment

helm install kolla/neutron-server-deployment --version 3.0.0-1 \
    --set "$common_vars" \
    --namespace kolla --name neutron-server

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/neutron-dhcp-agent-daemonset --version 3.0.0-1 \
    --set "$common_vars,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-dhcp-agent-daemonset

helm install kolla/neutron-metadata-agent-daemonset --version 3.0.0-1 \
    --set "$common_vars,type=network" \
    --namespace kolla --name neutron-metadata-agent-network

helm install kolla/neutron-l3-agent-daemonset --version 3.0.0-1 \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-l3-agent-network

helm install kolla/neutron-openvswitch-agent-daemonset --version 3.0.0-1 \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-openvswitch-agent-network

helm install kolla/openvswitch-ovsdb-daemonset --version 3.0.0-1 \
    --set "$common_vars,type=network,selector_key=kolla_controller" \
    --namespace kolla --name openvswitch-ovsdb-network

helm install kolla/openvswitch-vswitchd-daemonset --version 3.0.0-1 \
    --set $common_vars,type=network,selector_key=kolla_controller \
    --namespace kolla --name openvswitch-vswitchd-network

kollakube res create bootstrap openvswitch-set-external-ip

helm install kolla/nova-libvirt-daemonset --version 3.0.0-1 \
    --set "$common_vars,ceph_backend=true,element_name=nova-libvirt" \
    --namespace kolla --name nova-libvirt-daemonset

helm install kolla/nova-compute-daemonset --version 3.0.0-1 \
    --set "$common_vars,ceph_backend=true,tunnel_interface=$tunnel_interface,element_name=nova-compute" \
    --namespace kolla --name nova-compute-daemonset

#kollakube res create pod keepalived

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap openvswitch-set-external-ip

$DIR/tools/wait_for_pods.sh kolla
