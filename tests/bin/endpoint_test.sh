#!/bin/bash -e

# This bash exits 0> during a failure and 0 during success.  Possible
# error conditions include:
# * failure to curl the AuthToken from OpenStack
# * failure to find the endpoints in the curled result
# * syntax error in awk
# * copying the logs fails for some reason

function endpoints_dump_and_fail {
    cat /tmp/$$.1
    exit 1
}

OS_TOKEN=$(openstack token issue -f value -c id)
curl -H "X-Auth-Token:$OS_TOKEN" $OS_AUTH_URL/endpoints -o /tmp/$$
jq -r '.endpoints[] | .service_id' /tmp/$$ | sort | uniq -c > /tmp/$$.1
awk '{if($1 != 3){exit 1}}' /tmp/$$.1 || endpoints_dump_and_fail

# If the workspace isn't set (because this is the dev env),  unconditionally
# exit 0
if [ "x$WORKSPACE" == "x" ]; then
    exit 0
fi

# Copy the endpoint informational logs if the logs dir exists
[ -d $WORKSPACE/logs ] && cp /tmp/$$ $WORKSPACE/logs/endpoints.txt
[ -d $WORKSPACE/logs ] && cp /tmp/$$.1 $WORKSPACE/logs/endpoints1.txt
