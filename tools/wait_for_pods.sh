#!/bin/bash -e
# Default wait timeout is 180 seconds
set +x
end=$(date +%s)
if [ x$2 != "x" ]; then
 end=$((end + $2))
else
 end=$((end + 180))
fi
while true; do
    kubectl get pods --namespace=$1 -o json | jq -r \
        '.items[].status.phase' | grep Pending > /dev/null && \
        PENDING=True || PENDING=False
    query='.items[]|select(.status.phase=="Running")'
    query="$query|.status.containerStatuses[].ready"
    kubectl get pods --namespace=$1 -o json | jq -r "$query" | \
        grep false > /dev/null && READY="False" || READY="True"
    kubectl get jobs -o json --namespace=$1 | jq -r \
        '.items[] | .spec.completions == .status.succeeded' | \
        grep false > /dev/null && JOBR="False" || JOBR="True"
    [ $PENDING == "False" -a $READY == "True" -a $JOBR == "True" ] && \
        break || true
    sleep 1
    now=$(date +%s)
    [ $now -gt $end ] && echo containers failed to start. && \
        kubectl get pods --namespace $1 && exit -1
done
set -x
