#!/bin/bash -xe

VERSION=0.5.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/common_workflow_config.sh"
. "$DIR/tests/bin/common_ceph_config.sh"

tunnel_interface=docker0
if [ "x$1" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $1}')
    tunnel_interface=$interface
fi

base_distro="$2"
gate_job="$1"
function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface
}

function ceph_config {
    common_ceph_config $gate_job
}

common_vars="kube_logger=false,base_distro=$base_distro"

for x in mariadb rabbitmq glance helm-repo; do
    helm install kolla/$x-pv --version $VERSION \
        --name $x-pv --values <(general_config) --values <(ceph_config)
    helm install kolla/$x-pvc --version $VERSION --namespace kolla \
        --name $x-pvc --values <(general_config) --values <(ceph_config)
done

helm install kolla/helm-repo-svc --version $VERSION \
    --namespace kolla --name helm-repo-svc --set element_name=helm-repo \
    --values <(general_config) --values <(ceph_config)

helm install kolla/helm-repo-deployment --version $VERSION \
    --namespace kolla --name helm-repo-deployment --set "element_name=helm-repo" \
    --values <(general_config) --values <(ceph_config)

helm install kolla/memcached-svc --version $VERSION \
    --namespace kolla --name memcached-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/mariadb-svc --version $VERSION \
    --namespace kolla --name mariadb-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/rabbitmq-svc --version $VERSION \
    --namespace kolla --name rabbitmq-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/keystone-admin-svc --version $VERSION \
    --namespace kolla --name keystone-admin-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/keystone-public-svc --version $VERSION \
    --namespace kolla --name keystone-public-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/keystone-internal-svc --version $VERSION \
    --namespace kolla --name keystone-internal-svc \
    --values <(general_config) --values <(ceph_config)

[ "x$1" != "xexternal-ovs" ] &&
    helm install kolla/openvswitch-ovsdb-daemonset --version $VERSION \
      --set "$common_vars,type=network,selector_key=kolla_controller" \
      --namespace kolla --name openvswitch-ovsdb-network &&
    helm install kolla/openvswitch-vswitchd-daemonset --version $VERSION \
      --set $common_vars,type=network,selector_key=kolla_controller \
      --namespace kolla --name openvswitch-vswitchd-network

kollakube res create bootstrap openvswitch-set-external-ip

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/glance-api-svc --version $VERSION \
    --namespace kolla --name glance-api-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-registry-svc --version $VERSION \
    --namespace kolla --name glance-registry-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-server-svc --version $VERSION \
    --namespace kolla --name neutron-server-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-api-svc --version $VERSION \
    --namespace kolla --name cinder-api-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-api-svc --version $VERSION \
    --namespace kolla --name nova-api-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-metadata-svc --version $VERSION \
    --namespace kolla --name nova-metadata-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-novncproxy-svc --version $VERSION \
    --namespace kolla --name nova-novncproxy-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/horizon-svc --version $VERSION \
    --namespace kolla --name horizon-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/heat-api-svc --version $VERSION \
    --namespace kolla --name heat-api-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/heat-cfn-api-svc --version $VERSION \
    --namespace kolla --name heat-cfn-api-svc \
    --values <(general_config) --values <(ceph_config)

helm install kolla/mariadb-init-element-job --debug --version $VERSION \
    --namespace kolla --name mariadb-init-element-job \
    --values <(general_config) --values <(ceph_config)

helm install kolla/rabbitmq-init-element-job --debug --version $VERSION \
    --namespace kolla --name rabbitmq-init-element-job \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in mariadb rabbitmq; do
    helm delete $x-init-element-job --purge
done

helm install kolla/mariadb-statefulset --debug --version $VERSION \
    --namespace kolla --name mariadb-statefulset \
    --values <(general_config) --values <(ceph_config)

helm install kolla/memcached-deployment --debug --version $VERSION \
    --namespace kolla --name memcached-deployment \
    --values <(general_config) --values <(ceph_config)

helm install kolla/rabbitmq-statefulset --debug --version $VERSION \
    --namespace kolla --name rabbitmq-statefulset \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/keystone-create-db-job --version $VERSION \
    --namespace kolla \
    --name keystone-create-db \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm delete keystone-create-db

helm install kolla/keystone-manage-db-job --version $VERSION \
    --namespace kolla \
    --name keystone-manage-db \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm delete keystone-manage-db

helm install kolla/keystone-create-endpoints-job --version $VERSION \
    --namespace kolla \
    --name keystone-create-endpoints-job \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/keystone-api-deployment --version $VERSION \
    --namespace kolla \
    --name keystone \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/build_local_admin_keystonerc.sh
. ~/keystonerc_admin

helm install kolla/neutron-create-keystone-service-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-service \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-create-keystone-service-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-service \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-service-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-service \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-servicev2-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-servicev2 \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-user-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-user \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-create-keystone-user-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-user \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-create-keystone-user-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-user \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-create-keystone-service-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-service \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-create-keystone-user-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-user \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-public \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-endpoint-publicv2-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-publicv2 \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-endpoint-public \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-endpoint-public \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-create-keystone-endpoint-public-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-endpoint-public \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-endpoint-internal \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name neutron-create-keystone-endpoint-admin \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/wait_for_pods.sh kolla

for x in cinder glance neutron nova; do
    helm delete --purge $x-create-keystone-user
done

helm install kolla/glance-create-db-job --version $VERSION \
    --namespace kolla --name glance-create-db \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-manage-db-job --version $VERSION \
    --namespace kolla --name glance-manage-db \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-db-job --version $VERSION \
    --namespace kolla \
    --name cinder-create-db \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-manage-db-job --version $VERSION \
    --namespace kolla \
    --name cinder-manage-db \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-internal \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-endpoint-internalv2-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-internalv2 \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-admin \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-create-keystone-endpoint-adminv2-job --version $VERSION \
    --namespace kolla --name cinder-create-keystone-endpoint-adminv2 \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-endpoint-internal \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name glance-create-keystone-endpoint-admin \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-create-keystone-endpoint-internal-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-endpoint-internal \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-create-keystone-endpoint-admin-job --version $VERSION \
    --namespace kolla --name nova-create-keystone-endpoint-admin \
    --values <(general_config) --values <(ceph_config)

for x in nova nova-api neutron; do
    helm install kolla/$x-create-db-job --version $VERSION \
        --namespace kolla \
        --name $x-create-db \
        --values <(general_config) --values <(ceph_config)
done

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

for x in nova-api neutron; do
    helm install kolla/$x-manage-db-job --version $VERSION \
        --namespace kolla \
        --name $x-manage-db \
        --values <(general_config) --values <(ceph_config)
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

for x in glance neutron cinder nova; do
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
    --namespace kolla --name cinder-volume-ceph-statefulset \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-api-deployment --version $VERSION \
    --namespace kolla --name cinder-api \
    --values <(general_config) --values <(ceph_config)

helm install kolla/cinder-scheduler-statefulset --version $VERSION \
    --namespace kolla --name cinder-scheduler \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-api-deployment --version $VERSION \
    --namespace kolla --name glance-api-deployment \
    --values <(general_config) --values <(ceph_config)

helm install kolla/glance-registry-deployment --version $VERSION \
    --namespace kolla --name glance-registry \
    --values <(general_config) --values <(ceph_config)

helm ls

for x in nova-api nova-novncproxy; do
    helm install kolla/$x-deployment --version $VERSION \
      --namespace kolla --name $x \
      --values <(general_config) --values <(ceph_config)
done

for x in nova-conductor nova-scheduler nova-consoleauth; do
    helm install kolla/$x-statefulset --version $VERSION \
      --namespace kolla --name $x \
      --values <(general_config) --values <(ceph_config)
done

helm install kolla/horizon-deployment --version $VERSION \
    --namespace kolla --name horizon-deployment \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-server-deployment --version $VERSION \
    --namespace kolla --name neutron-server \
    --values <(general_config) --values <(ceph_config)

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

helm install kolla/neutron-dhcp-agent-daemonset --version $VERSION \
    --namespace kolla --name neutron-dhcp-agent-daemonset \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-metadata-agent-daemonset --version $VERSION \
    --set "$common_vars,type=network" \
    --namespace kolla --name neutron-metadata-agent-network \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-l3-agent-daemonset --version $VERSION \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-l3-agent-network \
    --values <(general_config) --values <(ceph_config)

helm install kolla/neutron-openvswitch-agent-daemonset --version $VERSION \
    --set "$common_vars,type=network,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-openvswitch-agent-network \
    --values <(general_config) --values <(ceph_config)

[ "x$1" == "xceph-multi" ] &&
    helm install kolla/openvswitch-ovsdb-daemonset --version $VERSION \
    --set "$common_vars,type=compute,selector_key=kolla_compute" \
    --namespace kolla --name openvswitch-ovsdb-compute \
    --values <(general_config) --values <(ceph_config) &&
    helm install kolla/neutron-openvswitch-agent-daemonset --version $VERSION \
    --set "$common_vars,type=compute,selector_key=kolla_compute,tunnel_interface=$tunnel_interface" \
    --namespace kolla --name neutron-openvswitch-agent-compute \
    --values <(general_config) --values <(ceph_config) &&
    helm install kolla/openvswitch-vswitchd-daemonset --version $VERSION \
    --set $common_vars,type=compute,selector_key=kolla_compute \
    --namespace kolla --name openvswitch-vswitchd-compute \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-libvirt-daemonset --version $VERSION \
    --namespace kolla --name nova-libvirt-daemonset \
    --values <(general_config) --values <(ceph_config)

helm install kolla/nova-compute-daemonset --version $VERSION \
    --namespace kolla --name nova-compute-daemonset \
    --values <(general_config) --values <(ceph_config)

#kollakube res create pod keepalived

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

kollakube res delete bootstrap openvswitch-set-external-ip

$DIR/tools/wait_for_pods.sh kolla
