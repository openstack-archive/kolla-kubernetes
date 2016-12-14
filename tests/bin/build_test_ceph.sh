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

kollakube res create bootstrap ceph-bootstrap-initial-mon

$DIR/tools/pull_containers.sh kolla
$DIR/tools/wait_for_pods.sh kolla

$DIR/tools/setup-ceph-secrets.sh
kollakube res delete bootstrap ceph-bootstrap-initial-mon
kollakube res create pod ceph-mon

$DIR/tools/wait_for_pods.sh kolla

helm install kolla/ceph-bootstrap-osd-job --version 3.0.0-1 \
    --namespace kolla \
    --name ceph-osd \
    --debug \
    --set "node=$(hostname -s),osd_number=0,osd_dev=/dev/loop0,osd_part_num=1,osd_journal_dev=/dev/loop0,osd_journal_part_num=2"

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

helm install kolla/ceph-bootstrap-osd-job --version 3.0.0-1 \
    --namespace kolla \
    --name ceph-osd \
    --debug \
    --set "node=$(hostname -s),osd_number=1,osd_dev=/dev/loop1,osd_part_num=1,osd_journal_dev=/dev/loop1,osd_journal_part_num=2"

$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

kollakube res create pod ceph-osd0
kollakube res create pod ceph-osd1

$DIR/tools/wait_for_pods.sh kolla

kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
    "cat /etc/ceph/ceph.conf" > /tmp/$$
kubectl create configmap ceph-conf --namespace=kolla \
    --from-file=ceph.conf=/tmp/$$
rm -f /tmp/$$
