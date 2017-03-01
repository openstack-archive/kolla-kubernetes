#!/bin/bash
[ ! -d ../kolla-ansible ] && pushd .. && git clone https://github.com/openstack/kolla-ansible && pip install -U kolla-ansible/ && popd
grep api_interface_address ../kolla-ansible/etc/kolla/globals.yml || echo api_interface_address: "0.0.0.0" >> /etc/kolla/globals.yml
grep tunnel_interface_address ../kolla-ansible/etc/kolla/globals.yml || echo tunnel_interface_address: "0.0.0.0" >> /etc/kolla/globals.yml
grep orchestration_engine ../kolla-ansbile/etc/kolla/globals.yml || echo orchestration_engine: KUBERNETES >> /etc/kolla/globals.yml
#sudo yum install -y golang-bin || sudo apt-get install -y golang
#tools/build_helm_templates.sh
set -x
mkdir -p ~/.helm/plugins/template
curl -L -o /tmp/helm-template.tar.gz https://github.com/technosophos/helm-template/releases/download/2.2.2%2B1/helm-template-linux-2.2.2.1.tgz
curl -L -o /tmp/helm.tar.gz https://storage.googleapis.com/kubernetes-helm/helm-v2.2.2-linux-amd64.tar.gz
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
