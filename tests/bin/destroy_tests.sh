#!/bin/bash -xe

# Destroy kolla-kubernetes deployment and validate kolla-kubernetes is
# indeed destroyed

. .venv/bin/activate
ansible-playbook -e ansible_python_interpreter=/usr/bin/python ansible/destroy.yml
deactivate

# Validate the deployment was indeed deleted
NAMESPACED_OBJECTS=$(kubectl get all -n kolla -o name --no-headers | wc -l)
LABELED_NODE_OBJECTS=$(kubectl get nodes --show-labels --no-headers | grep kolla | wc -l)
PV_OBJECTS=$(kubectl get pv --no-headers | wc -l)
kubectl get pv --no-headers

# If namespaced objects still exist, exit with failure
if [ $NAMESPACED_OBJECTS -ne 0 ]; then
    exit 1
fi

# If labeled nodes still exist, exit with failure
if [ $LABELED_NODE_OBJECTS -ne 0 ]; then
    exit 1
fi

# If PVs exist, exit with failure
if [ $PV_OBJECTS -ne 0 ]; then
    exit 1
fi
