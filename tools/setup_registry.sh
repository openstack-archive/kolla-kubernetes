#!/bin/bash -e
#
#  Passed parameters: $1 - Distro, $2 - Type,
#                     $3 - Branch
#
Distro="$1"
Type="$2"
Branch="$3"
VERSION=0.7.0-1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

echo "Deploying registry for: $Distro - $Type - $Branch"
helm install kolla/registry-deployment --version $VERSION --debug \
             --namespace kolla --name registry \
             --set initial_load=true --set node_port=30401 \
             --set distro=$Distro --set type=$Type

$DIR/wait_for_pods.sh kolla 900

echo "Registry with images for: $Distro - $Type - $Branch is running..."
