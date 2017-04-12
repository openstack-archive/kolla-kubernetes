#!/bin/bash -e

NAMESPACE=$1

function finish {
DNS_IP=`kubectl get svc --namespace=kube-system -l k8s-app=kube-dns -o \
        jsonpath='{.items[*].spec.clusterIP}'`
DOMAIN_NAME=$(kubectl get pod --namespace=kube-system -l k8s-app=kube-dns -o \
   jsonpath={..args} | grep "\-\-domain=" | awk -F '=' '{print $2}' | awk '{print $1}')
DOMAIN_NAME=${DOMAIN_NAME%%.}
cat > /tmp/$$ <<EOF
search $NAMESPACE.svc.$DOMAIN_NAME svc.$DOMAIN_NAME $DOMAIN_NAME
nameserver $DNS_IP
options ndots:5
EOF

kubectl create configmap resolv-conf --from-file=resolv.conf=/tmp/$$ --namespace $NAMESPACE
rm -f /tmp/$$
}

if [ "x$1" == "x--partial-async" ]; then
    finish &
else
    finish
fi
