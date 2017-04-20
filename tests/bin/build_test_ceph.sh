#!/bin/bash -xe

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

function wait_for_ceph_bootstrap {
    set +x
    end=$(date +%s)
    end=$((end + 120))
    while true; do
        kubectl get pods --namespace=$1 | grep ceph-bootstrap-osd && \
            PENDING=True || PENDING=False
        [ $PENDING == "False" ] && break
        sleep 1
        now=$(date +%s)
        [ $now -gt $end ] && echo containers failed to start. && \
            kubectl get pods --namespace $1 && exit -1
    done
}

kollakube res create configmap ceph-mon ceph-osd

helm install kolla/test-ceph-init-mon-job --version $VERSION \
    --namespace kolla \
    --name test-ceph-init-mon-job \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/setup-ceph-secrets.sh

helm install kolla/test-ceph-mon-daemonset --version $VERSION \
    --namespace kolla \
    --name test-ceph-mon-daemonset \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml

$DIR/tools/wait_for_pods.sh kolla

helm install kolla/test-ceph-init-osd-job --version $VERSION \
    --namespace kolla \
    --name test-ceph-init-osd0-job \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml \
    --set index=0

$DIR/tools/pull_containers.sh kolla

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

helm install kolla/test-ceph-init-osd-job --version $VERSION \
    --namespace kolla \
    --name test-ceph-init-osd1-job \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml \
    --set index=1

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

helm delete --purge test-ceph-init-osd0-job
helm delete --purge test-ceph-init-osd1-job

helm install kolla/test-ceph-osd-pod --version $VERSION \
    --namespace kolla \
    --name ceph-osds0 \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml \
    --set index=0
helm install kolla/test-ceph-osd-pod --version $VERSION \
    --namespace kolla \
    --name ceph-osds1 \
    --values /tmp/general_config.yaml \
    --values /tmp/ceph_config.yaml \
    --set index=1

$DIR/tools/wait_for_pods.sh kolla

kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
    "cat /etc/ceph/ceph.conf" > /tmp/$$
kubectl create configmap ceph-conf --namespace=kolla \
    --from-file=ceph.conf=/tmp/$$
rm -f /tmp/$$
