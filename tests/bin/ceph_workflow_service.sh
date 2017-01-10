#!/bin/bash -xe

VERSION=0.4.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/common_workflow_config.sh"

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface
}

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
    echo "    keystone:"
    echo "      all:"
    echo "        admin_port_external: true"
    echo "        dns_name: $IP"
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

helm install kolla/nova-api-svc --version $VERSION \
    --namespace kolla --name nova-api-svc \
    --set "element_name=nova,port_external=true,external_vip=$IP"

helm install kolla/nova-metadata-svc --version $VERSION \
    --namespace kolla --name nova-metadata-svc \
    --set "element_name=nova"

helm install kolla/nova-novncproxy-svc --version $VERSION \
    --namespace kolla --name nova-novncproxy-svc --set element_name=nova

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/keystone --version $VERSION \
    --namespace kolla --name keystone --set "$common_vars,element_name=keystone" \
    --values <(helm_entrypoint_general $1)

$DIR/tools/wait_for_pods.sh kolla

helm install kolla/openvswitch --version $VERSION \
  --namespace kolla --name openvswitch --values  <(helm_entrypoint_general $1)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res create bootstrap openvswitch-set-external-ip

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla


$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

helm install kolla/nova-create-keystone-user-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-user --set "$common_vars"

kollakube res create bootstrap \
    nova-create-keystone-endpoint-public

$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap \
    nova-create-keystone-endpoint-public

for x in nova; do
    helm delete --purge $x-create-keystone-user
done


kollakube res create bootstrap nova-create-keystone-endpoint-internal \
    nova-create-keystone-endpoint-admin

for x in nova nova-api; do
    helm install kolla/$x-create-db-job --version $VERSION \
        --set $common_vars,element_name=$x --namespace kolla \
        --name $x-create-db
done

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in nova-api; do
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

for x in nova nova-api; do
    helm delete --purge $x-create-db
done

for x in nova-api; do
    helm delete --purge $x-manage-db
done

kollakube res delete bootstrap \
    nova-create-keystone-endpoint-internal \
    nova-create-keystone-endpoint-admin \

helm install kolla/cinder-volume-ceph-statefulset --version $VERSION \
    --set "$common_vars,element_name=cinder" --namespace kolla \
    --name cinder-volume-ceph-statefulset

helm install kolla/cinder-control --version $VERSION \
    --namespace kolla --name cinder --set "$common_vars,element_name=cinder" \
    --values <(helm_entrypoint_general $1)

helm install kolla/glance --version $VERSION \
    --namespace kolla --name glance --set "$common_vars,element_name=glance" \
    --values <(helm_entrypoint_general $1)

helm install kolla/neutron --version $VERSION \
    --namespace kolla --name neutron --values  <(helm_entrypoint_general $1)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

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

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

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
