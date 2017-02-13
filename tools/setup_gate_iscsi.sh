#!/bin/bash -xe

PACKAGE_VERSION=0.5.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$6"
PIPELINE="$7"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"
. "$DIR/setup_gate_common.sh"

# Setting up iptables
setup_iptables

# Installating required software packages
setup_packages $DISTRO $CONFIG

# Setting up an interface and a bridge
setup_bridge

# Setting up virt env, kolla-ansible and kolla-kubernetes
setup_kolla

tests/bin/setup_config_iscsi.sh "$2" "$4" "$BRANCH"

tests/bin/setup_gate_loopback_lvm.sh

tools/setup_kubernetes.sh master

kubectl taint nodes --all dedicated-

NODE=$(hostname -s)
kubectl label node $NODE kolla_controller=true kolla_compute=true kolla_storage=true

tests/bin/setup_canal.sh

# Setting up Helm
setup_helm_common

# Setting up namespace and secret
setup_namespace_secrets

# Setting up resolv.conf workaround 
setup_resolv_conf_common

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

if [ "x$4" == "xhelm-compute-kit" ]; then
    tests/bin/deploy_compute_kit.sh "$4" "$2" "$BRANCH"
else
    tests/bin/iscsi_workflow.sh "$4" "$2" "$BRANCH"
fi

. ~/keystonerc_admin

sudo pvs >> $WORKSPACE/logs/pvs.txt

sudo vgs >> $WORKSPACE/logs/vgs.txt

sudo lvs >> $WORKSPACE/logs/lvs.txt

cinder service-list >> $WORKSPACE/logs/cinder_service_list.txt

tests/bin/basic_tests.sh
tests/bin/build_docker_images.sh $WORKSPACE/logs $DISTRO $TYPE $CONFIG $BRANCH $PIPELINE
