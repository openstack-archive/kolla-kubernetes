#!/bin/bash -e

function endpoints_dump_and_fail {
    cat /tmp/$$.1
    exit -1
}

OS_TOKEN=$(openstack token issue -f value -c id)
curl -H "X-Auth-Token:$OS_TOKEN" $OS_AUTH_URL/endpoints -o /tmp/$$
jq -r '.endpoints[] | .service_id' /tmp/$$ | sort | uniq -c > /tmp/$$.1
awk '{if($1 != 3){exit -1}}' /tmp/$$.1 || endpoints_dump_and_fail
cp /tmp/$$ $WORKSPACE/logs/endpoints.txt
cp /tmp/$$.1 $WORKSPACE/logs/endpoints1.txt

. ~/keystonerc_admin
#openstack endpoint list > $WORKSPACE/logs/endpoints2.txt
#openstack service list > $WORKSPACE/logs/endpoints3.txt
#openstack catalog list > $WORKSPACE/logs/endpoints4.txt
