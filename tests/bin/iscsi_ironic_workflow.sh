#!/bin/bash -xe
#
# Passed parameters $1 - Config, $2 - Distro, $3 - Branch
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
VERSION=0.6.0-1
IP=172.18.0.1
tunnel_interface=docker0
base_distro="$2"
branch="$3"
config="$1"

. "$DIR/tests/bin/deploy_iscsi_common.sh"
. "$DIR/tests/bin/deploy_ironic.sh"

function common_iscsi {
   deploy_iscsi_common  $IP $base_distro $tunnel_interface $branch $config
}

function ironic_base {
   deploy_ironic  $IP $base_distro $tunnel_interface $branch $config
}

#
# Deploying common iscsi components
#
common_iscsi

#
# Deploying ironic
#
ironic_base


#
# Placement is not working, debugging it
#
kubectl get svc nova-placement-api -n kolla -o yaml
kubectl describe svc nova-placement-api -n kolla
kubectl get pods -n kolla | grep placement | \
        awk '{print "kubectl get pod -n kolla "$1" -o yaml"}' | sh -l

kubectl get pods -n kolla | grep placement | \
        awk '{print "kubectl describe pod -n kolla "$1}' | sh -l

curl http://`kubectl get svc nova-placement-api --namespace=kolla -o \
    jsonpath='{.spec.externalIPs[0]}'`:8780/

exit 0
