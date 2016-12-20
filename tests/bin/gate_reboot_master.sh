#!/bin/bash -xe

WORKSPACE="$1"
LOGS="$2"

NODES=1
cat /etc/nodepool/sub_nodes_private | while read line; do
    NODES=$((NODES+1))
    echo $line
    tar -cvf - . | ssh $USER@$line 'cat > workspace.tar'
    ssh $USER@$line 'sudo reboot & exit'
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
