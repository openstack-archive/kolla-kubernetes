#!/bin/bash -xe

PACKAGE_VERSION=0.7.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$6"
PIPELINE="$7"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"
. "$DIR/setup_gate_common.sh"

# Installating required software packages
setup_packages $DISTRO $CONFIG

# Setting up iptables
setup_iptables

# Setting up an interface and a bridge
setup_bridge

# Setting up virt env, kolla-ansible and kolla-kubernetes
setup_kolla $BRANCH $CONFIG

tests/bin/setup_config_iscsi.sh "$2" "$4" "$BRANCH" "$TYPE"

tests/bin/setup_gate_loopback_lvm.sh

tools/setup_kubernetes.sh master

kubectl taint nodes --all=true  node-role.kubernetes.io/master:NoSchedule-

tests/bin/setup_canal.sh

NODE=$(hostname -s)
kubectl label node $NODE kolla_controller=true kolla_compute=true \
                         kolla_storage=true

tools/pull_containers.sh kube-system
tools/wait_for_pods.sh kube-system

tools/test_kube_dns.sh

# Setting up Helm
setup_helm_common

# Setting up namespace and secret
setup_namespace_secrets

kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume iscsid tgtd keepalived \
    placement-api placement-api-haproxy;

if [ "x$4" == "xironic" ]; then
kollakube res create configmap \
    ironic-api ironic-api-haproxy ironic-conductor ironic-conductor-tftp \
    ironic-dnsmasq ironic-inspector ironic-inspector-haproxy \
    ironic-inspector-tftp nova-compute-ironic;
fi

kollakube res create secret nova-libvirt

if [ "x$4" == "xhelm-compute-kit" ]; then
    tests/bin/deploy_compute_kit.sh "$4" "$2" "$BRANCH"
elif [ "x$4" == "xironic" ]; then
    tests/bin/iscsi_ironic_workflow.sh "$4" "$2" "$BRANCH"
elif [ "x$4" == "xhelm-operator" ]; then
    echo "Not yet implemented..." "$4" "$2" "$BRANCH"
else
    tests/bin/iscsi_generic_workflow.sh "$4" "$2" "$BRANCH"
fi

. ~/keystonerc_admin

sudo pvs >> $WORKSPACE/logs/pvs.txt

sudo vgs >> $WORKSPACE/logs/vgs.txt

sudo lvs >> $WORKSPACE/logs/lvs.txt

cinder service-list >> $WORKSPACE/logs/cinder_service_list.txt

tests/bin/basic_tests.sh
tests/bin/horizon_test.sh
tests/bin/prometheus_tests.sh
tests/bin/build_docker_images.sh $WORKSPACE/logs $DISTRO $TYPE $CONFIG $BRANCH $PIPELINE
#
# Workflow specific tests
#
if [ "x$4" == "xironic" ]; then
   tests/bin/ironic_deploy_tests.sh "$4" "$2" "$BRANCH"
fi

exit 0
