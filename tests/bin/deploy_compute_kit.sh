#!/bin/bash -xe

VERSION=0.5.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
IP=172.18.0.1

. "$DIR/tests/bin/common_workflow_config.sh"
. "$DIR/tests/bin/common_iscsi_config.sh"

function general_config {
    common_workflow_config $IP $base_distro $tunnel_interface

function entrypoint_config {
    general_config
    common_iscsi_config
}

tunnel_interface=docker0
base_distro="$2"

echo "Not yet implemented. Exiting ..."

exit 1
