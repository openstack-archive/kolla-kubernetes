#!/bin/bash -xe

echo Upgrading test ceph.

VERSION=0.7.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP="$3"
base_distro="$2"
gate_job="$1"
tunnel_interface="$4"
branch="$5"

. "$DIR/tests/bin/common_workflow_config.sh"

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface $branch
}

function ceph_config {
  echo "node: $(hostname -s)"
  echo "storage_interface: $tunnel_interface"
  echo "initial_member: $(hostname -s)"
  echo "initial_mon: $(hostname -s)"
  echo "ceph:"
  echo "  monitors:"
  echo "  - $IP"
}

general_config > /tmp/general_config.yaml
ceph_config > /tmp/ceph_config.yaml

helm upgrade test-ceph-mon-daemonset kollanew/test-ceph-mon-daemonset --version $VERSION \
    --namespace kolla \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

helm upgrade ceph-osds0 kollanew/test-ceph-osd-pod --version $VERSION \
    --namespace kolla \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml \
    --set index=0
helm upgrade ceph-osds1 kollanew/test-ceph-osd-pod --version $VERSION \
    --namespace kolla \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml \
    --set index=1

$DIR/tools/wait_for_pods.sh kolla

kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
    "ceph -s"
