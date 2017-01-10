#!/bin/bash -xe

BRANCH="$6"

export BASE_DISTRO=$2
export INSTALL_TYPE=$3

trap 'tests/bin/gate_capture_logs.sh "$?"' ERR

mkdir -p $WORKSPACE/logs/
env > $WORKSPACE/logs/env

sudo iptables-save > $WORKSPACE/logs/iptables-before.txt
tests/bin/fix_gate_iptables.sh

if [ "x$2" == "xubuntu" ]; then
    sudo apt-get update
    sudo apt-get install lvm2
    sudo apt-get remove -y open-iscsi
    sudo apt-get install -y bridge-utils
    (echo server:; echo "  interface: 172.19.0.1"; echo "  access-control: 0.0.0.0/0 allow") | \
        sudo /bin/bash -c "cat > /etc/unbound/unbound.conf.d/kubernetes.conf"
else
    sudo yum clean all
    sudo yum remove -y iscsi-initiator-utils
    sudo yum install -y bridge-utils
    sudo yum install -y lvm2
    (echo server:; echo "  interface: 172.19.0.1"; echo "  access-control: 0.0.0.0/0 allow") | \
        sudo /bin/bash -c "cat > /etc/unbound/conf.d/kubernetes.conf"
fi
sudo brctl addbr dns0
sudo ifconfig dns0 172.19.0.1 netmask 255.255.255.0
sudo systemctl restart unbound
sudo systemctl status unbound
sudo netstat -pnl
sudo sed -i "s/127\.0\.0\.1/172.19.0.1/" /etc/resolv.conf
sudo cat /etc/resolv.conf

virtualenv .venv
. .venv/bin/activate

cat > /tmp/clonemap <<"EOF"
clonemap:
 - name: openstack/kolla
   dest: kolla
EOF

[ -x /usr/zuul-env/bin/zuul-cloner ] && \
/usr/zuul-env/bin/zuul-cloner -m /tmp/clonemap --workspace `pwd` \
    --branch master --cache-dir /opt/git git://git.openstack.org \
    openstack/kolla-ansible && true
[ ! -d kolla-ansible ] && git clone https://github.com/openstack/kolla-ansible.git

###NOTE: (sbezverk) Temp workaround to the issue with the gate
pushd kolla-ansible;
git checkout 4.0.0.0b2
popd

sudo ln -s `pwd`/kolla-ansible/etc/kolla /etc/kolla
sudo ln -s `pwd`/kolla-ansible /usr/share/kolla
sudo ln -s `pwd`/etc/kolla-kubernetes /etc/kolla-kubernetes

if [ -f /etc/redhat-release ]; then
    sudo yum install -y crudini jq sshpass
else
    sudo apt-get update
    sudo apt-get install -y crudini jq sshpass
fi
pushd kolla-ansible;
pip install pip --upgrade
pip install "ansible<2.1"
pip install "python-openstackclient"
pip install "python-neutronclient"
pip install "python-cinderclient"
pip install -r requirements.txt
pip install pyyaml
popd
pip install -r requirements.txt
pip install .

tests/bin/setup_config_iscsi.sh "$2" "$4" "$BRANCH"

tests/bin/setup_gate_loopback_lvm.sh

tools/setup_kubernetes.sh master $BASE_DISTRO $INSTALL_TYPE

kubectl taint nodes --all dedicated-

# Turn up kube-proxy logging
# kubectl -n kube-system get ds -l 'component=kube-proxy-amd64' -o json \
#   | sed 's/--v=4/--v=9/' \
#   | kubectl apply -f - && kubectl -n kube-system delete pods -l 'component=kube-proxy-amd64'


NODE=$(hostname -s)
kubectl label node $NODE kolla_controller=true kolla_compute=true kolla_storage=true

tests/bin/setup_canal.sh

tools/setup_helm.sh

tools/helm_build_all.sh ~/.helm/repository/kolla
helm repo remove kollabuild
tools/helm_buildrepo.sh ~/.helm/repository/kolla 10192 kolla &
helm update
helm search

kubectl create namespace kolla
tools/secret-generator.py create

TOOLBOX=$(kollakube tmpl bootstrap neutron-create-db -o json | jq -r '.spec.template.spec.containers[0].image')
sudo docker pull $TOOLBOX > /dev/null
timeout 240s tools/setup-resolv-conf.sh

echo "Starting iscsi workflow..."
tests/bin/iscsi_workflow.sh "$4" "$2" "$BRANCH"
. ~/keystonerc_admin

kubectl get pods --namespace=kolla

cinder service-list >> $WORKSPACE/logs/cinder_service_list.txt

sudo pvs >> $WORKSPACE/logs/pvs.txt

sudo vgs >> $WORKSPACE/logs/vgs.txt

sudo lvs >> $WORKSPACE/logs/lvs.txt

tests/bin/basic_tests.sh
