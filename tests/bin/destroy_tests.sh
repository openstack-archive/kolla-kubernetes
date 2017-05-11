#!/bin/bash -xe
mkdir $WORKSPACE/logs/prometheus/

# Validate the deployment was indeed deleted
NAMESPACED_OBJECTS=`kubectl get all -n kolla -o name | wc -l`
LABELED_NODE_OBJECTS=`kubectl get nodes -o name --show-labels | grep kolla | wc -l`
PV_OBJECTS=`kubectl get pv | wc -l`

# If namespaced objects still exist, exit with failure
if [ $NAMESPACED_OBJECTS -eq 0 ]; then
    exit 1
fi

# If labeled nodes still exist, exit with failure
if [ $LABELED_NODE_OBJECTS -eq 0 ]; then
    exit 1
fi

# If PVs (which have no label) still exist, exit with failure
if [ $PV_OBJECTS -eq 0 ]; then
    exit 1
fi
