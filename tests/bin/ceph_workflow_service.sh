#!/bin/bash -xe

VERSION=0.4.0-1

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

function helm_entrypoint_general {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      kube_logger: false"
    echo "      external_vip: $IP"
    echo "      base_distro: $base_distro"
    echo "      tunnel_interface: $tunnel_interface"
    echo "      storage_provider: ceph"
    echo "      storage_provider_fstype: xfs"
    echo "      ceph:"
    echo "         monitors:"
    ### NOTE (sbezverk)  172.17.0.1 is default ip address used by Docker
    addr=172.17.0.1
    if [ "x$1" == "xceph-multi" ]; then
        addr=$(cat /etc/nodepool/primary_node_private)
    fi
    echo "             - $addr"
    echo "         pool: kollavolumes"
    echo "         secret_name: ceph-kolla"
    echo "         user: kolla"
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

helm install kolla/mariadb --version $VERSION \
    --namespace kolla --name mariadb --set "$common_vars,element_name=mariadb" \
    --values <(helm_entrypoint_general $1)

helm install kolla/memcached --version $VERSION \
    --namespace kolla --name memcached \
    --set "$common_vars,element_name=memcached" \
    --values <(helm_entrypoint_general $1)

helm install kolla/rabbitmq --version $VERSION \
    --namespace kolla --name rabbitmq --set "$common_vars" \
    --values <(helm_entrypoint_general $1)

helm install kolla/cinder-api-svc --version $VERSION \
    --namespace kolla --name cinder-api-svc \
    --set "element_name=cinder,port_external=true,external_vip=$IP"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/keystone --version $VERSION \
    --namespace kolla --name keystone --set "$common_vars,element_name=keystone" \
    --values <(helm_entrypoint_general $1)

$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

helm install kolla/cinder-create-keystone-service-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-service --set "$common_vars"

helm install kolla/cinder-create-keystone-servicev2-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-servicev2 --set "$common_vars"

helm install kolla/cinder-create-keystone-user-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-user --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-public --set "$common_vars,external_vip=172.18.0.1"
helm install kolla/cinder-create-keystone-endpoint-publicv2-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-publicv2 --set "$common_vars,external_vip=172.18.0.1"

$DIR/tools/wait_for_pods.sh kolla

for x in cinder; do
    helm delete --purge $x-create-keystone-user
done

helm install kolla/cinder-create-db-job --version $VERSION \
    --set $common_vars,element_name=cinder \
    --namespace kolla \
    --name cinder-create-db

helm install kolla/cinder-manage-db-job --version $VERSION \
    --set $common_vars,element_name=cinder \
    --namespace kolla \
    --name cinder-manage-db

helm install kolla/cinder-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-internal --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-internalv2-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-internalv2 --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-admin --set "$common_vars"

helm install kolla/cinder-create-keystone-endpoint-adminv2-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-adminv2 --set "$common_vars"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

[ -d "$WORKSPACE/logs" ] &&
kubectl get jobs -o json > $WORKSPACE/logs/jobs-after-bootstrap.json \
    --namespace=kolla || true

$DIR/tests/bin/endpoint_test.sh

[ -d "$WORKSPACE/logs" ] && openstack catalog list > \
    $WORKSPACE/logs/openstack-catalog-after-bootstrap.json || true

for x in cinder; do
    helm delete --purge $x-create-db
done

for x in cinder; do
    helm delete --purge $x-manage-db
done

for x in cinder; do
    helm delete --purge $x-create-keystone-service
    helm delete --purge $x-create-keystone-endpoint-public
    helm delete --purge $x-create-keystone-endpoint-internal
    helm delete --purge $x-create-keystone-endpoint-admin
done

helm delete --purge cinder-create-keystone-servicev2
helm delete --purge cinder-create-keystone-endpoint-publicv2
helm delete --purge cinder-create-keystone-endpoint-internalv2
helm delete --purge cinder-create-keystone-endpoint-adminv2

helm install kolla/cinder-volume-ceph-statefulset --version $VERSION \
    --set "$common_vars,element_name=cinder" --namespace kolla \
    --name cinder-volume-ceph-statefulset

helm install kolla/cinder-api-deployment --version $VERSION \
    --set "$common_vars" --namespace kolla \
    --name cinder-api

helm install kolla/cinder-scheduler-statefulset --version $VERSION \
    --set "$common_vars,element_name=cinder-scheduler" \
    --namespace kolla --name cinder-scheduler

helm install kolla/glance --version $VERSION \
    --namespace kolla --name glance --set "$common_vars,element_name=glance" \
    --values <(helm_entrypoint_general $1)

helm install kolla/openvswitch-ovsdb-daemonset --version $VERSION \
--set "$common_vars,type=network,selector_key=kolla_controller" \
--namespace kolla --name openvswitch-ovsdb-network &&
helm install kolla/openvswitch-vswitchd-daemonset --version $VERSION \
--set $common_vars,kube_logger=false,type=network,selector_key=kolla_controller \
--namespace kolla --name openvswitch-vswitchd-network

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res create bootstrap openvswitch-set-external-ip

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/neutron --version $VERSION \
    --namespace kolla --name neutron --values  <(helm_entrypoint_general)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm ls

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/nova-control --version $VERSION  --namespace kolla \
    --name nova-control --set "$common_vars,element_name=nova" \
    --values <(helm_entrypoint_general $1)

helm install kolla/nova-compute --version $VERSION  --namespace kolla \
    --name nova-compute --set "$common_vars,element_name=nova" \
    --values <(helm_entrypoint_general $1)

helm install kolla/horizon --version $VERSION \
    --namespace kolla --name horizon \
    --set "$common_vars,element_name=horizon" \
    --values <(helm_entrypoint_general $1)

#kollakube res create pod keepalived

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap openvswitch-set-external-ip

$DIR/tools/wait_for_pods.sh kolla
