#!/bin/bash -xe

WORKSPACE="$1"
LOGS="$2"

function log_kube_start_failure {
    set +e
    mkdir -p "$LOGS/container"
    ssh "$1" sudo sed -i "s/^SELINUX=.*/SELINUX=disabled" /etc/sysconfig/selinux
    ssh "$1" uptime > "$LOGS/uptime.txt"
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

mkdir -p "$LOGS"
NODES=1
cat /etc/nodepool/sub_nodes_private | while read line; do
    NODES=$((NODES+1))
    echo $line
    tar -cf - * .git | ssh $USER@$line 'mkdir -p workspace; cd workspace; tar -xvf -'
    set -e
    ssh $USER@$line 'cd workspace; WORKSPACE=`pwd` tools/setup_gate.sh deploy centos binary ceph centos-7 shell'
    RES=$?
    echo Done testing.
    if [ $RES -ne 0 ]; then
        scp -r $USER@$line:workspace/logs/* $WORKSPACE/logs/
        exit $RES
    fi
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
    set -e
done
