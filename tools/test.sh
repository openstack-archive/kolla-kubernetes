#!/bin/bash -x
[ ! -d ../kolla ] && pushd .. && git clone https://github.com/openstack/kolla-ansible && mv kolla-ansible kolla && popd
pushd ../kolla;
#git checkout ba023042b29ff2f9b4486d8c3276c62523b95b8a
git diff 6cb4507267e0a368a69c0ba1d02a6e16301ddf43..96185846c30ab6848a7e9aa0e31219f80e70d26b > foo.patch
patch -p1 -R < foo.patch || true #it rejects one. its ok.
popd
grep api_interface_address ../kolla/etc/kolla/globals.yml || echo api_interface_address: "0.0.0.0" >> ../kolla/etc/kolla/globals.yml
grep tunnel_interface_address ../kolla/etc/kolla/globals.yml || echo tunnel_interface_address: "0.0.0.0" >> ../kolla/etc/kolla/globals.yml
grep orchestration_engine ../kolla/etc/kolla/globals.yml || echo orchestration_engine: KUBERNETES >> ../kolla/etc/kolla/globals.yml
#sudo yum install -y golang-bin || sudo apt-get install -y golang
#tools/build_helm_templates.sh
set -x
mkdir -p ~/.helm/plugins/template
curl -L -o /tmp/helm-template.tar.gz https://github.com/technosophos/helm-template/releases/download/2.1.3%2B1/helm-template-linux.tgz
curl -L -o /tmp/helm.tar.gz https://storage.googleapis.com/kubernetes-helm/helm-v2.1.3-linux-amd64.tar.gz
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
