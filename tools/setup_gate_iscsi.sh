#!/bin/bash -xe

PACKAGE_VERSION=0.4.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$7"
PIPELINE="$8"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
. "$DIR/tests/bin/common_entrypoint_config.sh"

trap 'tests/bin/gate_capture_logs.sh "$?"' ERR

mkdir -p $WORKSPACE/logs/
env > $WORKSPACE/logs/env

# Setting up iptables
setup_iptables

# Installating required software packages
setup_packages $BRANCH $CONFIG

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

echo "Starting iscsi workflow..."
tests/bin/iscsi_workflow.sh "$4" "$2" "$BRANCH"
. ~/keystonerc_admin

kubectl get pods --namespace=kolla

cinder service-list >> $WORKSPACE/logs/cinder_service_list.txt

sudo pvs >> $WORKSPACE/logs/pvs.txt

sudo vgs >> $WORKSPACE/logs/vgs.txt

sudo lvs >> $WORKSPACE/logs/lvs.txt

tests/bin/basic_tests.sh
tests/bin/cleanup_tests.sh
tests/bin/build_docker_images.sh $WORKSPACE/logs $DISTRO $TYPE $CONFIG $BRANCH $PIPELINE
