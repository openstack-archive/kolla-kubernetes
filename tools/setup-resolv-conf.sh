#!/bin/bash -e

YUM_CMD=$(which yum)
APT_GET_CMD=$(which apt-get)

if [[ ! -z $YUM_CMD ]]; then
    yum install jq
 elif [[ ! -z $APT_GET_CMD ]]; then
    apt-get install jq
 else
    echo "error can't install jq package"
    exit 1;
fi

NAMESPACE=$(kolla-kubernetes resource-template create bootstrap neutron-create-db -o json | jq -r '.metadata.namespace')
TOOLBOX=$(kolla-kubernetes resource-template create bootstrap neutron-create-db -o json | jq -r '.spec.template.spec.containers[0].image')

function finish {
    kubectl run -i --rm fetchresolv --restart=Never --namespace=$NAMESPACE --image=$TOOLBOX -- /bin/bash -c 'cat /etc/resolv.conf' | egrep '^search|^nameserver|^options' > /tmp/$$
    kubectl create configmap resolv-conf --from-file=resolv.conf=/tmp/$$ --namespace $NAMESPACE
    rm -f /tmp/$$
}

if [ "x$1" == "x--partial-async" ]; then
    finish &
else
    finish
fi
