#!/bin/bash -xe

WORKSPACE="$1"
LOGS="$2"

NODES=1
cat /etc/nodepool/sub_nodes_private | while read line; do
    NODES=$((NODES+1))
    echo $line
    tar -cf - * | ssh $USER@$line 'mkdir -p workspace; cd workspace; tar -xvf -'
    set -e
    ssh $USER@$line 'WORKSPACE=`pwd` tools/setup_gate.sh deploy centos binary ceph centos-7 shell'
    RES=$?
    if [ $RES -ne 0 ]; then
        scp -r $USER@$line:workspace/logs/* $WORKSPACE/logs/
        exit $RES
    fi
    set +e
    ssh $USER@$line 'sudo reboot & exit'
    sleep 30
    set +e
    START=$(date '+%s')
    while true; do
        ssh $USER@$line hostname
        [ $? -eq 0 ] && break
        NOW=$(date '+%s')
        sleep 5
        # 5 min wait.
        [ $NOW -ge $((START + 300)) ] && echo "Node didn't come back." && exit -1
    done
    set -e
done
