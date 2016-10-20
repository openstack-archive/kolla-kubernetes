#!/bin/bash -xe

[ "x$4" == "xiscsi" ] && echo "iscsi support pending..." && exit 0

trap 'tests/bin/gate_capture_logs.sh "$?"' ERR

mkdir -p $WORKSPACE/logs/
env > $WORKSPACE/logs/env

sudo iptables-save > $WORKSPACE/logs/iptables-before.txt
tests/bin/fix_gate_iptables.sh

virtualenv .venv
. .venv/bin/activate

git clone https://github.com/openstack/kolla.git
sudo ln -s `pwd`/kolla/etc/kolla /etc/kolla
sudo ln -s `pwd`/kolla /usr/share/kolla
sudo ln -s `pwd`/etc/kolla-kubernetes /etc/kolla-kubernetes

if [ -f /etc/redhat-release ]; then
    sudo yum install -y crudini jq sshpass
else
    sudo apt-get update
    sudo apt-get install -y crudini jq sshpass
fi
pushd kolla;
pip install pip --upgrade
pip install "ansible<2.1"
pip install "python-openstackclient"
pip install "python-neutronclient"
pip install -r requirements.txt
pip install pyyaml
popd
pip install -r requirements.txt
pip install .

tests/bin/setup_config.sh "$2"

tests/bin/setup_gate_loopback.sh

tools/setup_kubernetes.sh master

if [ "x$4" == "xceph-multi" ]; then
    cat /etc/nodepool/sub_nodes_private | while read line; do
        echo $line
        NODE=$(ssh $line hostname)
        echo $line $NODE | sudo tee -a /etc/hosts
        scp tools/setup_kubernetes.sh $line:
        scp /usr/bin/kubectl $line:kubectl
        ssh $line sudo mv kubectl /usr/bin/
        ssh $line bash setup_kubernetes.sh slave "$(cat /etc/kubernetes/token.txt)" "$(cat /etc/kubernetes/ip.txt)"
        kubectl label node $NODE kolla_compute=true
    done
fi

kubectl taint nodes --all dedicated-

NODE=$(hostname -s)
kubectl label node $NODE kolla_controller=true

if [ "x$4" != "xceph-multi" ]; then
    kubectl label node $NODE kolla_compute=true
fi

tests/bin/setup_canal.sh

kubectl create namespace kolla
tools/secret-generator.py create

TOOLBOX=$(kollakube tmpl bootstrap neutron-create-db -o json | jq -r '.spec.template.spec.containers[0].image')
sudo docker pull $TOOLBOX > /dev/null
timeout 240s tools/setup-resolv-conf.sh

tests/bin/build_test_ceph.sh

kollakube res create pod ceph-admin ceph-rbd
tools/wait_for_pods.sh kolla

str="ceph -w"
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash -c "$str" \
    > $WORKSPACE/logs/ceph.log &

for x in kollavolumes images volumes vms; do
    kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool create $x 64; ceph osd pool set $x size 1; ceph osd pool set $x min_size 1"
done
kubectl exec ceph-admin -c main --namespace=kolla -- /bin/bash \
    -c "ceph osd pool delete rbd rbd --yes-i-really-really-mean-it"

tools/setup_simple_ceph_users.sh
tools/setup_rbd_volumes.sh --yes-i-really-really-mean-it

tests/bin/ceph_workflow.sh
. ~/keystonerc_admin

kubectl get pods --namespace=kolla

tests/bin/basic_tests.sh
