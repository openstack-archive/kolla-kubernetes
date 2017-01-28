#!/bin/bash -e
set +x
end=$(date +%s)
end=$((end + 300))
pod=$(kubectl get pods --namespace=$1 | grep Terminating | awk '{print $1}')
if [ x$pod != 'x' ]; then
   kubectl get pods $pod --namespace=$1 -o json
fi
while true; do
    kubectl get pods --namespace=$1 | grep Terminating > /dev/null && \
        TERMINATING=True || TERMINATING=False
    [ $TERMINATING == "False" ] && \
        break || true
    sleep 1
    now=$(date +%s)
    echo 'Waitng for pod to terminate: $now'
    [ $now -gt $end ] && echo containers failed to terminate. && \
        kubectl get pods --namespace $1 && exit -1
done
set -x
