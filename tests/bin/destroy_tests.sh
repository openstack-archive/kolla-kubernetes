#!/bin/bash -xe

# Destroy kolla-kubernetes deployment and validate kolla-kubernetes is
# indeed destroyed

echo "a"
. .venv/bin/activate
echo "b"
ansible-playbook -e ansible_python_interpreter=/usr/bin/python ansible/destroy.yml
echo "c"
. .venv/bin/deactivate
echo "d"

# Validate the deployment was indeed deleted
echo "e"
NAMESPACED_OBJECTS=`kubectl get all -n kolla -o name | wc -l`
echo "f"
LABELED_NODE_OBJECTS=`kubectl get nodes -o name --show-labels | grep kolla | wc -l`
echo "g"
PV_OBJECTS=`kubectl get pv | wc -l`
echo "h"

# If namespaced objects still exist, exit with failure
if [ $NAMESPACED_OBJECTS -eq 0 ]; then
echo "i"
    exit 1
fi

# If labeled nodes still exist, exit with failure
if [ $LABELED_NODE_OBJECTS -eq 0 ]; then
echo "j"
    exit 1
fi

# If PVs exist, exit with failure
if [ $PV_OBJECTS -eq 0 ]; then
echo "k"
    exit 1
fi
echo "l"
