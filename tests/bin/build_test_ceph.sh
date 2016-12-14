#!/bin/bash -xe

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

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

helm install kolla/test-ceph-init-mon-job --version 0.5.0-1 \
    --namespace kolla \
    --name test-ceph-init-mon-job \
    --set "node=$(hostname -s),storage_interface=docker0"

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/setup-ceph-secrets.sh
kollakube res create pod ceph-mon

$DIR/tools/wait_for_pods.sh kolla

kollakube res create pod ceph-bootstrap-osd0
$DIR/tools/pull_containers.sh kolla

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

kollakube res create pod ceph-bootstrap-osd1

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

kollakube res delete pod ceph-bootstrap-osd0
kollakube res delete pod ceph-bootstrap-osd1
kollakube res create pod ceph-osd0
kollakube res create pod ceph-osd1

$DIR/tools/wait_for_pods.sh kolla

kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
    "cat /etc/ceph/ceph.conf" > /tmp/$$
kubectl create configmap ceph-conf --namespace=kolla \
    --from-file=ceph.conf=/tmp/$$
rm -f /tmp/$$
