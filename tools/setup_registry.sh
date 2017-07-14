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

pwd
ls -al
helm search
helm ls

helm install kolla/registry-deployment --version $VERSION --debug \
             --namespace kolla --name registry \
             --set initial_load=true --set node_port=30401 \
             --set distro=$Distro --set type=$Type --set branch=$Branch

$DIR/tools/wait_for_pods.sh kolla 600

echo "Registry with images for: $Distro - $Type - $Branch is running..."
