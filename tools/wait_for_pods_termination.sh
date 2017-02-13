#!/bin/bash -e
set +x
end=$(date +%s)
end=$((end + 300))
while true; do
    kubectl get pods --namespace=$1 | grep Terminating > /dev/null && \
        TERMINATING=True || TERMINATING=False
    [ $TERMINATING == "False" ] && \
        break || true
    sleep 1
    now=$(date +%s)
    echo 'Waiting for pod to terminate: ' $now
    [ $now -gt $end ] && echo containers failed to terminate. && \
        kubectl get pods --namespace $1 && exit -1
done
set -x
