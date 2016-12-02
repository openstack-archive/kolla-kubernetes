#!/bin/bash -xe

DIR="$( pwd )"

function wait_for_ceph_bootstrap {
    set +x
    end=$(date +%s)
    end=$((end + 900))
    while true; do
        kubectl get pods --namespace=$1 | grep ceph-bootstrap-osd && \
            PENDING=True || PENDING=False
        [ $PENDING == "False" ] && break
        sleep 1
        now=$(date +%s)
        [ $now -gt $end ] && echo containers failed to start. && \
            kubectl get pods --namespace $1 && echo "I was gonna quit..."
    done
}

kollakube template configmap ceph-mon ceph-osd > /tmp/kube.yaml
kubectl create -f /tmp/kube.yaml


kollakube template bootstrap ceph-bootstrap-initial-mon > /tmp/kube.yaml
sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
kubectl create -f /tmp/kube.yaml


$DIR/tools/wait_for_pods.sh kolla
$DIR/tools/setup-ceph-secrets.sh

kollakube res delete bootstrap ceph-bootstrap-initial-mon
kollakube template pod ceph-mon > /tmp/kube.yaml
sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
kubectl create -f /tmp/kube.yaml
$DIR/tools/wait_for_pods.sh kolla




kollakube template pod ceph-bootstrap-osd0 > /tmp/kube.yaml
sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
kubectl create -f /tmp/kube.yaml
$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

kollakube template pod ceph-bootstrap-osd1 > /tmp/kube.yaml
sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
kubectl create -f /tmp/kube.yaml
$DIR/tools/wait_for_pods.sh kolla
wait_for_ceph_bootstrap kolla

kollakube res delete pod ceph-bootstrap-osd0
kollakube res delete pod ceph-bootstrap-osd1

sed -i "s|^ceph_osd_data_kube2:|ceph_osd_data_dev:|g"  etc/kolla-kubernetes/kolla-kubernetes.yml
sed -i "s|^ceph_osd_journal_kube2:|ceph_osd_journal_dev:|g"  etc/kolla-kubernetes/kolla-kubernetes.yml
sed -i "s|/kube2/loop|/dev/loop|g" etc/kolla-kubernetes/kolla-kubernetes.yml

kollakube template pod ceph-osd0 > /tmp/kube.yaml
sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
kubectl create -f /tmp/kube.yaml

kollakube template pod ceph-osd1 > /tmp/kube.yaml
sed -i "s|kubernetes.io/hostname: kube2|kubernetes.io/hostname: 172.16.35.12|g"  /tmp/kube.yaml
kubectl create -f /tmp/kube.yaml


$DIR/tools/wait_for_pods.sh kolla

kubectl exec ceph-osd0 -c main --namespace=kolla -- /bin/bash -c \
    "cat /etc/ceph/ceph.conf" > /tmp/ceph.conf
kubectl create configmap ceph-conf --namespace=kolla \
    --from-file=ceph.conf=/tmp/ceph.conf



kollakube template pod ceph-admin ceph-rbd > /tmp/kube.yaml
kubectl create -f /tmp/kube.yaml


tools/wait_for_pods.sh kolla

kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "ceph -s"



for x in kollavolumes images volumes vms; do
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool create $x 64; ceph osd pool set $x size 1; ceph osd pool set $x min_size 1"
done
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool delete rbd rbd --yes-i-really-really-mean-it"

tools/setup_simple_ceph_users.sh
tools/setup_rbd_volumes.sh --yes-i-really-really-mean-it

echo "now run: tests/bin/ceph_dev_workflow.sh"
#tests/bin/ceph_dev_workflow.sh
