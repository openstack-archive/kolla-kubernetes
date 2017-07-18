#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

grep api_interface_address etc/kolla/globals.yml || echo api_interface_address: "0.0.0.0" >> etc/kolla/globals.yml
grep tunnel_interface_address etc/kolla/globals.yml || echo tunnel_interface_address: "0.0.0.0" >> etc/kolla/globals.yml
grep orchestration_engine etc/kolla/globals.yml || echo orchestration_engine: KUBERNETES >> etc/kolla/globals.yml

#sudo yum install -y golang-bin || sudo apt-get install -y golang
#tools/build_helm_templates.sh
set -x
. tools/helm_versions.sh
#FIXME override the helm version to get an unreleased version with template support built in.
HELM_URL="https://github.com/jascott1/bins/raw/master/helm/v2.6%2Be8fb5035/linux-amd64/helm"
curl -L -o ~/bin/helm "$HELM_URL"
#curl -L -o /tmp/helm.tar.gz "$HELM_URL"
mkdir -p ~/bin
#tar --strip-components 1 -C ~/bin linux-amd64/helm -zxf /tmp/helm.tar.gz
export PATH=$PATH:~/bin
export HOME=$(cd ~; pwd)
export HELMDIR=$(pwd)/helm
export HELMBIN=$HOME/bin/helm
export HELM_HOME=$HOME/.helm/
export REPODIR=/tmp/repo.$$
helm init -c
tools/helm_build_all.sh /tmp/repo.$$
python setup.py test --slowest --testr-args="$1"
