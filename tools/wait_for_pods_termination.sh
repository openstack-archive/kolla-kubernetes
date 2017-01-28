#!/bin/bash -e
set +x
end=$(date +%s)
end=$((end + 180))
while true; do
    kubectl get pods --namespace=$1 -o json | jq -r \
        '.items[].status.phase' | grep Terminating > /dev/null && \
        TERMINATING=True || TERMINATING=False
    [ $TERMINATING == "False" ] && \
        break || true
    sleep 1
    now=$(date +%s)
    [ $now -gt $end ] && echo containers failed to terminate. && \
        kubectl get pods --namespace $1 && exit -1
done
set -x
