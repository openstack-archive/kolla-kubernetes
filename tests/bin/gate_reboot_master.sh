#!/bin/bash -xe

WORKSPACE="$1"
LOGS="$2"

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
    set +e
    echo Simulating a power failure/reboot
    cat > /tmp/gate.$$.sh <<"EOF"
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
    set -e
    timeout 30 ssh $USER@$line 'sudo systemctl' | true
    timeout 30 ssh $USER@$line 'sudo systemctl status kubelet' | true
    timeout 30 ssh $USER@$line 'sudo systemctl status docker' | true
    timeout 30 ssh $USER@$line 'sudo docker ps -a' | true
    timeout 30 ssh $USER@$line 'kubectl get pods --all-namespaces'
    sleep 60
    timeout 30 ssh $USER@$line 'sudo systemctl status kubelet' | true
    timeout 30 ssh $USER@$line 'sudo systemctl status docker' | true
    timeout 30 ssh $USER@$line 'sudo docker ps -a' | true
    timeout 30 ssh $USER@$line 'kubectl get pods --all-namespaces'
done
