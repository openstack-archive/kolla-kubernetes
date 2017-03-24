#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"
[ ! -d ../kolla ] && pushd .. && git clone https://github.com/openstack/kolla-ansible && mv kolla-ansible kolla && popd
grep api_interface_address ../kolla/etc/kolla/globals.yml || echo api_interface_address: "0.0.0.0" >> ../kolla/etc/kolla/globals.yml
grep tunnel_interface_address ../kolla/etc/kolla/globals.yml || echo tunnel_interface_address: "0.0.0.0" >> ../kolla/etc/kolla/globals.yml
grep orchestration_engine ../kolla/etc/kolla/globals.yml || echo orchestration_engine: KUBERNETES >> ../kolla/etc/kolla/globals.yml
#sudo yum install -y golang-bin || sudo apt-get install -y golang
#tools/build_helm_templates.sh
set -x
. tools/helm_versions.sh
mkdir -p ~/.helm/plugins/template
curl -L -o /tmp/helm-template.tar.gz "$HELM_TEMPLATE_URL"
curl -L -o /tmp/helm.tar.gz "$HELM_URL"
mkdir -p ~/bin
tar --strip-components 1 -C ~/bin linux-amd64/helm -zxf /tmp/helm.tar.gz
tar -C ~/.helm/plugins/template/ -zxf /tmp/helm-template.tar.gz
export PATH=$PATH:~/bin
export HOME=$(cd ~; pwd)
export HELMDIR=$(pwd)/helm
export HELMBIN=$HOME/bin/helm
export HELM_HOME=$HOME/.helm/
export REPODIR=/tmp/repo.$$
helm init -c
helm template || true
tools/helm_build_all.sh /tmp/repo.$$
python setup.py test --slowest --testr-args="$1"
