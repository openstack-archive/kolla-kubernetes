#!/bin/bash -e
# Default wait timeout is 180 seconds
set +x
count=0

for x in etcd kube-apiserver kube-controller-manager kube-scheduler; do
   echo $x
   kubectl get pod -n kube-system | grep -G ^$x
   pod_name=$(kubectl get pod -n kube-system | grep -G ^$x | awk '{print $1}')
   echo "Pod name: $pod_name"
   while true; do
     count=$((count+1))
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
