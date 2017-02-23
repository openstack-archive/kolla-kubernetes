#!/bin/bash -xe
#
# Passed parameters $1 - Config, $2 - Distro, $3 - Branch
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
VERSION=0.6.0-1
IP=172.18.0.1
tunnel_interface=docker0
base_distro="$2"
branch=$3
config=$1

. "$DIR/tests/bin/deploy_iscsi_common.sh"
. "$DIR/tests/bin/deploy_ironic.sh"

#
# Deploying common iscsi components
#
deploy_iscsi_common  $IP $base_distro $tunnel_interface $branch $config

#
# Deploying ironic 
#
deploy_ironic  $IP $base_distro $tunnel_interface $branch $config
