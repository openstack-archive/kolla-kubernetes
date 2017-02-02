#!/bin/bash -xe

VERSION=0.5.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/iscsi_entrypoint_config.sh"

function entrypoint_config {
    iscsi_entrypoint_config $IP $base_distro $tunnel_interface
}

tunnel_interface=docker0
base_distro="$2"

echo "Not yet implemented. Exiting ..."

exit 1
