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

function kollakube_gate_debug {
    CMD=$@
    echo "***GATE_REVERSE_DEBUG***: START: kollakube $@"
    kollakube template $@
    echo "***GATE_REVERSE_DEBUG***: END: kollakube $@"
    kollakube res create $@
}
function dump_config {
    echo "***GATE_REVERSE_DEBUG***: Dumping config: $1"
    cat $1
    echo "***GATE_REVERSE_DEBUG***: Dumping config: $1"
}

dump_config /etc/kolla-kubernetes/kolla-kubernetes.yml
dump_config /etc/kolla-kubernetes/service_resources.yml

kollakube_gate_debug configmap ceph-mon ceph-osd

kollakube_gate_debug bootstrap ceph-bootstrap-initial-mon

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/setup-ceph-secrets.sh
kollakube res delete bootstrap ceph-bootstrap-initial-mon
kollakube_gate_debug pod ceph-mon

$DIR/tools/wait_for_pods.sh kolla

kollakube_gate_debug pod ceph-bootstrap-osd0
$DIR/tools/pull_containers.sh kolla

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

kollakube_gate_debug pod ceph-bootstrap-osd1

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

kollakube res delete pod ceph-bootstrap-osd0
kollakube res delete pod ceph-bootstrap-osd1
kollakube_gate_debug pod ceph-osd0
kollakube_gate_debug pod ceph-osd1

$DIR/tools/wait_for_pods.sh kolla

kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
    "cat /etc/ceph/ceph.conf" > /tmp/$$
kubectl create configmap ceph-conf --namespace=kolla \
    --from-file=ceph.conf=/tmp/$$
rm -f /tmp/$$
