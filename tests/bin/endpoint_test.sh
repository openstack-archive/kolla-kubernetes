#!/bin/bash -e

function endpoints_dump_and_fail {
    cat /tmp/$$.1
    exit -1
}

OS_TOKEN=$(openstack token issue -f value -c id)
curl -H "X-Auth-Token:$OS_TOKEN" $OS_AUTH_URL/endpoints -o /tmp/$$
jq -r '.endpoints[] | .service_id' /tmp/$$ | sort | uniq -c > /tmp/$$.1
awk '{if($1 != 3){exit -1}}' /tmp/$$.1 || endpoints_dump_and_fail
[ -d $WORKSPACE/logs ] && cp /tmp/$$ $WORKSPACE/logs/endpoints.txt
[ -d $WORKSPACE/logs ] && cp /tmp/$$.1 $WORKSPACE/logs/endpoints1.txt
