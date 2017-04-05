#!/bin/bash -e
# Default wait timeout is 180 seconds
set +x
count=0

for x in etcd kube-apiserver kube-controller-manager kube-proxy kube-scheduler; do
   pod_name=$(kubectl get pod -n kube-system | grep -G ^$x | awk '{print $1}')
   while true; do
     count=$((count+1))
     echo $pod_name
     pod_status=$(kubectl get pod -n kube-system $pod_name -o jsonpath='{.status.phase}')
     if [ "x$pod_status" != "xRunning" ]; then
        if [ $count -gt 180 ]; then
           echo "Kubernetes cluster control plane failed to come up"
           exit -1
        fi
        sleep 1
     else
        break
     fi
   done
done
