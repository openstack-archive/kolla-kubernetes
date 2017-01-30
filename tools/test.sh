#!/bin/bash
[ ! -d ../kolla ] && pushd .. && git clone https://github.com/openstack/kolla-ansible && mv kolla-ansible kolla && popd
grep api_interface_address ../kolla/etc/kolla/globals.yml || echo api_interface_address: "0.0.0.0" >> ../kolla/etc/kolla/globals.yml
grep tunnel_interface_address ../kolla/etc/kolla/globals.yml || echo tunnel_interface_address: "0.0.0.0" >> ../kolla/etc/kolla/globals.yml
grep orchestration_engine ../kolla/etc/kolla/globals.yml || echo orchestration_engine: KUBERNETES >> ../kolla/etc/kolla/globals.yml
#sudo yum install -y golang-bin || sudo apt-get install -y golang
#tools/build_helm_templates.sh
mkdir -p ~/.helm/plugins/template
curl -o ~/.helm/plugins/template/tpl http://www.efox.cc/temp/tpl
curl -o ~/.helm/plugins/template/plugin.yaml http://www.efox.cc/temp/plugin.yaml
curl -o /tmp/helm.tar.gz https://storage.googleapis.com/kubernetes-helm/helm-v2.1.3-linux-amd64.tar.gz
mkdir -p ~/bin
chmod +x ~/.helm/plugins/template/~/.helm/plugins/template/tpl
tar --strip-components 1 -C ~/bin linux-amd64/helm -zxf /tmp/helm.tar.gz
export PATH=$PATH:~/bin
helm init -c
helm template || true
python setup.py test --slowest --testr-args="$1"
