#!/bin/bash -xe

WORKSPACE="$1"
LOGS="$2"
BRANCH="$3"

function log_kube_start_failure {
    set +e
    mkdir -p "$LOGS/container"
    ssh "$1" uptime > "$LOGS/uptime.txt"
    ssh "$1" sudo /sbin/getenforce > "$LOGS/selinux.txt"
    ssh "$1" sudo journalctl -u docker > "$LOGS/docker.txt"
    ssh "$1" sudo journalctl -u kubelet > "$LOGS/kubelet.txt"
    ssh "$1" sudo docker ps -a --no-trunc > "$LOGS/docker-ps.txt"
    ssh "$1" mkdir -p "$LOGS/container/"
    cat > /tmp/$$.script <<"EOF"
mkdir -p /tmp/container/
sudo docker ps -q -a --format "{{.ID}}\t{{.Names}}" | while read line; do
    ID=$(echo $line | awk '{print $1}');
    NAME=$(echo $line | awk '{print $2}');
    sudo docker logs $ID > "/tmp/container/$NAME.txt" 2>&1;
done
EOF
    scp /tmp/$$.script "$1:/tmp/script"
    ssh "$1" 'bash /tmp/script'
    scp -r "$1:/tmp/container/" "$WORKSPACE/logs/"
    ssh "$1" '/bin/hostname' > "$WORKSPACE/logs/hostname-after.txt"
    ssh "$1" '/sbin/ip a' > "$WORKSPACE/logs/ip-after.txt"
    ssh "$1" curl -L http://127.0.0.1:2379/health > "$WORKSPACE/logs/etcd-health.txt"
    true
}

function gate_capture_logs {
    log_kube_start_failure "$1"
    ssh "$1" 'cd workspace; WORKSPACE=`pwd` tests/bin/gate_capture_logs.sh'
    scp -r "$1":workspace/logs/* $WORKSPACE/logs/
}

mkdir -p "$LOGS"
NODES=1
cat /etc/nodepool/sub_nodes_private | while read line; do
    NODES=$((NODES+1))
    echo $line
    tar -cf - * .git | ssh $USER@$line 'mkdir -p workspace; cd workspace; tar -xvf -'
    set -e
    ssh $USER@$line 'cd workspace; WORKSPACE=`pwd` REBOOT_TEST=1 tools/setup_gate.sh deploy centos binary ceph centos-7 shell'" $BRANCH"
    RES=$?
    echo Done testing.
    if [ $RES -ne 0 ]; then
        scp -r $USER@$line:workspace/logs/* $WORKSPACE/logs/
        exit $RES
    fi
    cat > /tmp/$$.script <<"EOF"
sed -i "s/^SELINUX=.*/SELINUX=disabled/" /etc/selinux/config
grep SELINUX /etc/selinux/config
cat > /etc/systemd/system/setup-ceph-loopback.service <<"EOOF"
[Unit]
Description=loopback for ceph
Before=docker.service
Before=kubelet.service
[Service]
Type=forking
RemainAfterExit=yes
TimeoutStartSec=0
ExecStart=/bin/bash -c 'LOOP=$(losetup -f); losetup $LOOP /data/kolla/ceph-osd0.img; partprobe $LOOP; LOOP=$(losetup -f); losetup $LOOP /data/kolla/ceph-osd1.img; partprobe $LOOP'
[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
RequiredBy=kubelet.service
EOOF
systemctl enable setup-ceph-loopback
iptables-save > /etc/sysconfig/iptables
EOF
    scp -r /tmp/$$.script $USER@$line:/tmp/foo.script
    ssh $USER@$line sudo bash /tmp/foo.script
    ssh $USER@$line '/bin/hostname' > "$WORKSPACE/logs/hostname-before.txt"
    ssh $USER@$line '/sbin/ip a' > "$WORKSPACE/logs/ip-before.txt"
    RES=$?
    set +e
    echo Simulating a power failure/reboot
    cat > /tmp/gate.$$.sh <<"EOF"
sync; sync;
echo 1 > //proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
EOF
    timeout 10 scp /tmp/gate.$$.sh $USER@$line:gate.sh
    timeout 10 ssh $USER@$line sudo bash gate.sh
    sleep 30
    echo checking
    set +e
    START=$(date '+%s')
    while true; do
        timeout 60 ssh $USER@$line hostname
        [ $? -eq 0 ] && break
        NOW=$(date '+%s')
        sleep 5
        # 10 min wait.
        [ $NOW -ge $((START + 600)) ] && echo "Node didn't come back." && exit -1
        echo checking again...
    done
    ssh $USER@$line "sudo getenforce" > $LOGS/selinux-middle.txt
    START=$(date '+%s')
    while true; do
        timeout 30 ssh $USER@$line 'kubectl get pods --all-namespaces'
        [ $? -eq 0 ] && break
        NOW=$(date '+%s')
        sleep 5
        # 10 min wait.
        [ $NOW -ge $((START + 600)) ] && echo "Kubernetes didn't come back." && log_kube_start_failure $USER@$line && exit -1
        echo checking again...
    done
    cat > /tmp/gate.$$.sh <<"EOF"
cd ~/workspace
. .venv/bin/activate
. ~/keystonerc_admin
set -x
kubectl delete pod --force ceph-osd0 --namespace kolla
kubectl delete pod --force ceph-osd1 --namespace kolla
kubectl delete pod --force ceph-admin --namespace kolla
kubectl delete pod --force openvswitch-set-external-ip --namespace kolla
sleep 300 #FIXME wait for pods to delete...
kubectl get pods --all-namespaces
kollakube res create bootstrap openvswitch-set-external-ip
kollakube res create pod ceph-osd0
kollakube res create pod ceph-osd1
kollakube res create pod ceph-admin
sleep 300 #FIXME wait for pods to settle after ceph comes back.
str="timeout 6s ceph -s"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str"
ps -eo etime,cmd > ~/workspace/logs/ps-after-ceph.txt
timeout 60s openstack user list
timeout 60s openstack catalog list
timeout 60s openstack image list
timeout 60s openstack volume list
timeout 60s openstack network list
timeout 60s openstack server list
EOF
    scp -r /tmp/gate.$$.sh $USER@$line:/tmp/script
    trap "gate_capture_logs $USER@$line" ERR
    set -e
    ssh $USER@$line 'bash /tmp/script'
done
