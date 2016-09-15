#!/bin/bash
NAMESPACE=$(kolla-kubernetes resource-template create bootstrap neutron-create-db -o json | jq -r '.metadata.namespace')
TOOLBOX=$(kolla-kubernetes resource-template create bootstrap neutron-create-db -o json | jq -r '.spec.template.spec.containers[0].image')
kubectl run -i --rm fetchresolv --restart=Never --namespace=$NAMESPACE --image=$TOOLBOX -- /bin/bash -c 'cat /etc/resolv.conf' | egrep '^search|^nameserver|^options' > /tmp/$$
kubectl create configmap resolv-conf --from-file=resolv.conf=/tmp/$$ --namespace $NAMESPACE
rm -f /tmp/$$

