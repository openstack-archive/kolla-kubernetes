#!/bin/bash -xe
#
# Passed parameters $1 - Config, $2 - Distro, $3 - Branch
#
function general_config {
#
#  Passed parameters: $1 - IP, $2 - base_distro,
#                     $3 - tunnel_interface, $4 - $branch
#
    common_microchart_config $1 $2 $3 $4
}


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
. "$DIR/tests/bin/common_microchart_config.sh"

VERSION=0.7.0-1
IP=172.18.0.1
tunnel_interface=docker0
base_distro="$2"
branch="$3"
config="$1"

general_config $IP $base_distro $tunnel_interface $branch > /etc/kolla/cloud.yaml

function deploy_microcharts {
  cd $DIR/orchestration
  ansible-playbook -e @/etc/kolla/globals.yml -e CONFIG_DIR=/etc/kolla ansible/deploy.yml
}

deploy_microcharts

exit 0
