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
    timeout 10 ssh $USER@$line /bin/bash -c 'echo 1 | sudo dd of=/proc/sys/kernel/sysrq bs=2; echo b | sudo dd of=/proc/sysrq-trigger bs=2'
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
    timeout 10 ssh $USER@$line 'sudo systemctl status kubelet' | true
    timeout 10 ssh $USER@$line 'kubectl get pods --all-namespaces'
done
