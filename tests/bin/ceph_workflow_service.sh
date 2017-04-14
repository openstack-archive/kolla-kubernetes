#!/bin/bash -xe

VERSION=0.6.0-1
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
gate_job="$1"
base_distro="$2"
branch="$3"
IP=${4:-172.18.0.1}
tunnel_interface=${5:-docker0}

# Break out devenv behavior since we will use different polling logic
# and we also assume ceph-multi use in the devenv
devenv=false
if [ "x$gate_job" == "xdevenv" ]; then
    devenv=true
    gate_job="ceph-multi"
fi

. "$DIR/tests/bin/common_workflow_config.sh"
. "$DIR/tests/bin/common_ceph_config.sh"

function wait_for_pods {
    if [ "$devenv" = true ]; then
        $DIR/tools/wait_for_pods.py $1 $2 $3
    else
        $DIR/tools/pull_containers.sh $1
        $DIR/tools/wait_for_pods.sh $1
    fi
}

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface $branch
}

function ceph_config {
    common_ceph_config $gate_job $branch
}

if [ "x$gate_job" == "xceph-multi" ]; then
    interface=$(netstat -ie | grep -B1 \
        $(cat /etc/nodepool/primary_node_private) \
        | head -n 1 | awk -F: '{print $gate_job}')
    # if this is being run remotely the netstat will fail,
    # so fallback to the passed in interface name
    if [ ! -z "$interface" ]; then
        tunnel_interface=$interface
    fi
fi

general_config > /tmp/general_config.yaml
ceph_config > /tmp/ceph_config.yaml

common_vars="kube_logger=false,base_distro=$base_distro"

helm install kolla/mariadb --version $VERSION \
    --namespace kolla --name mariadb \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

helm install kolla/memcached --version $VERSION \
    --namespace kolla --name memcached \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

wait_for_pods kolla mariadb,memcached running,succeeded

helm install kolla/rabbitmq --version $VERSION \
    --namespace kolla --name rabbitmq \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

wait_for_pods kolla rabbitmq running,succeeded

helm install kolla/keystone --version $VERSION \
    --namespace kolla --name keystone \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

wait_for_pods kolla keystone running,succeeded

helm install kolla/openvswitch --version $VERSION \
    --namespace kolla --name openvswitch \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

wait_for_pods kolla openvswitch running

helm install kolla/keepalived-daemonset --debug --version $VERSION \
    --namespace kolla --name keepalived-daemonset \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

wait_for_pods kolla openvswitch running

if [ "$devenv" = true ]; then
    $DIR/tools/build_local_admin_keystonerc.sh ext
    . ~/keystonerc_admin
else
    $DIR/tools/build_local_admin_keystonerc.sh
    . ~/keystonerc_admin
fi

[ -d "$WORKSPACE/logs" ] &&
kubectl get jobs -o json > $WORKSPACE/logs/jobs-after-bootstrap.json \
    --namespace=kolla || true

$DIR/tests/bin/endpoint_test.sh

[ -d "$WORKSPACE/logs" ] && openstack catalog list > \
    $WORKSPACE/logs/openstack-catalog-after-bootstrap.json || true

helm install kolla/cinder-volume-ceph-statefulset --version $VERSION \
    --namespace kolla --name cinder-volume-ceph-statefulset \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

helm install kolla/cinder-control --version $VERSION \
    --namespace kolla --name cinder \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

helm install kolla/glance --version $VERSION \
    --namespace kolla --name glance \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

helm install kolla/neutron --version $VERSION \
    --namespace kolla --name neutron \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

sudo docker ps | grep openvswitch
sudo docker exec -tu root $(sudo docker ps | grep openvswitch-vswitchd@ \
                          | awk '{print $1}') ovs-vsctl add-br br-tenants
sudo ifconfig br-tenants up
sudo ifconfig br-tenants $(grep ironic_tftp_server $DIR/helm/all_values.yaml \
                         | awk '{print $2}')/24

helm install kolla/ironic --version $VERSION  --namespace kolla \
    --name ironic \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

wait_for_pods kolla cinder,glance,neutron,ironic running,succeeded

helm ls

helm install kolla/nova-control --version $VERSION  --namespace kolla \
    --name nova-control \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

helm install kolla/nova-compute --version $VERSION  --namespace kolla \
    --name nova-compute \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

helm install kolla/nova-compute-ironic --version $VERSION  --namespace kolla \
    --name nova-compute-ironic \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

helm install kolla/horizon --version $VERSION \
    --namespace kolla --name horizon \
    --values /tmp/general_config.yaml --values /tmp/ceph_config.yaml

#kollakube res create pod keepalived

wait_for_pods kolla nova,horizon running,succeeded
