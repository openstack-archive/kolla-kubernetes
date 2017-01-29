#!/bin/bash -xe

PACKAGE_VERSION=0.4.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$7"
PIPELINE="$8"

if [ "x$PIPELINE" == "xperiodic" ]; then
    mkdir -p $WORKSPACE/UPLOAD_CONTAINERS
fi


if [ "x$PIPELINE" != "xperiodic" ]; then
    C=$CONFIG
    if [ "x$CONFIG" == "xexternal-ovs" -o "x$CONFIG" == "xceph-multi" -o "x$CONFIG" == "xhelm-entrypoint" ]; then
        C="ceph"
    fi
    mkdir -p $WORKSPACE/DOWNLOAD_CONTAINERS
    BASE_URL=http://tarballs.openstack.org/kolla-kubernetes/gate/containers/
    FILENAME="$DISTRO-$TYPE-$C"
    FILENAME=$(echo "$FILENAME" | sed 's/-multi//')
    curl -o $WORKSPACE/DOWNLOAD_CONTAINERS/"$FILENAME".tar.bz2 \
        "$BASE_URL/$FILENAME.tar.bz2"
    curl -o $WORKSPACE/DOWNLOAD_CONTAINERS/"$FILENAME"-containers.txt \
        "$BASE_URL/$FILENAME-containers.txt"
    curl -o $WORKSPACE/DOWNLOAD_CONTAINERS/kubernetes.tar.bz2 \
        "$BASE_URL/kubernetes.tar.bz2"
    curl -o $WORKSPACE/DOWNLOAD_CONTAINERS/kubernetes-containers.txt \
        "$BASE_URL/kubernetes-containers.txt"
    ls -l $WORKSPACE/DOWNLOAD_CONTAINERS/
fi

if [ "x$BRANCH" == "xt" ]; then
    echo Version: $BRANCH is not enabled yet.
    exit 0
fi

if [ "x$BRANCH" == "x3" ]; then
    sed -i 's/2\.0\.2/3.0.2/g' helm/all_values.yaml
    sed -i 's/2\.0\.2/3.0.2/g' tests/conf/ceph-all-in-one/kolla_config
fi

if [ "x$4" == "xiscsi" ]; then
    echo "Starting iscsi setup script..."
    tools/setup_gate_iscsi.sh $1 $2 $3 $4 $5 $BRANCH $PIPELINE
    exit 0
fi

if [ "x$4" == "xhelm-operator" ]; then
    echo "helm operator job is not yet implemented..."
    exit 0
fi

trap 'tests/bin/gate_capture_logs.sh "$?"' ERR

mkdir -p $WORKSPACE/logs/
env > $WORKSPACE/logs/env

sudo iptables-save > $WORKSPACE/logs/iptables-before.txt
tests/bin/fix_gate_iptables.sh

if [ "x$2" == "xubuntu" ]; then
    sudo apt-get update
    sudo apt-get remove -y open-iscsi
    sudo apt-get install -y bridge-utils
    (echo server:; echo "  interface: 172.19.0.1"; echo "  access-control: 0.0.0.0/0 allow") | \
        sudo /bin/bash -c "cat > /etc/unbound/unbound.conf.d/kubernetes.conf"
else
    sudo yum clean all
    sudo yum remove -y iscsi-initiator-utils
    sudo yum install -y bridge-utils
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
    sudo yum install -y crudini jq sshpass bzip2
else
    sudo apt-get update
    sudo apt-get install -y crudini jq sshpass bzip2
fi
pushd kolla-ansible;
pip install pip --upgrade
pip install "ansible<2.1"
pip install "python-openstackclient"
pip install "python-neutronclient"
pip install -r requirements.txt
pip install pyyaml
popd
pip install -r requirements.txt
pip install .

if [ "x$4" == "xexternal-ovs" ]; then
    sudo rpm -Uvh https://repos.fedorapeople.org/openstack/openstack-newton/rdo-release-newton-4.noarch.rpm || true
    sudo yum install -y openvswitch
    sudo systemctl start openvswitch
    sudo ovs-vsctl add-br br-ex
fi

tests/bin/setup_config.sh "$2" "$4" "$BRANCH"

tests/bin/setup_gate_loopback.sh

tools/setup_kubernetes.sh master

kubectl taint nodes --all dedicated-

# Turn up kube-proxy logging
# kubectl -n kube-system get ds -l 'component=kube-proxy-amd64' -o json \
#   | sed 's/--v=4/--v=9/' \
#   | kubectl apply -f - && kubectl -n kube-system delete pods -l 'component=kube-proxy-amd64'

if [ "x$4" == "xceph-multi" ]; then
    NODES=1
    cat /etc/nodepool/sub_nodes_private | while read line; do
        NODES=$((NODES+1))
        echo $line
        scp tools/setup_kubernetes.sh $line:
        scp tests/bin/fix_gate_iptables.sh $line:
        scp /usr/bin/kubectl $line:kubectl
        NODENAME=$(ssh -n $line hostname)
        ssh -n $line bash fix_gate_iptables.sh
        ssh -n $line sudo iptables-save > $WORKSPACE/logs/iptables-$line.txt
        ssh -n $line sudo setenforce 0
        if [ "x$2" == "xubuntu" ]; then
           ssh -n $line sudo apt-get -y remove open-iscsi
        else
           ssh -n $line sudo yum remove -y iscsi-initiator-utils
        fi
        ssh -n $line sudo mv kubectl /usr/bin/
        scp -r "$WORKSPACE/DOWNLOAD_CONTAINERS" $line:
        ssh -n $line bash setup_kubernetes.sh slave "$(cat /etc/kubernetes/token.txt)" "$(cat /etc/kubernetes/ip.txt)"
        set +xe
        count=0
        while true; do
          c=$(kubectl get nodes --no-headers=true | wc -l)
          [ $c -ge $NODES ] && break
          count=$((count+1))
          [ $count -gt 30 ] && break
          sleep 1
        done
        [ $count -gt 30 ] && echo Node failed to join. && exit -1
        set -xe
        kubectl get nodes
        kubectl label node $NODENAME kolla_compute=true
    done
fi

NODE=$(hostname -s)
kubectl label node $NODE kolla_controller=true

if [ "x$4" != "xceph-multi" ]; then
    kubectl label node $NODE kolla_compute=true
fi

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

tests/bin/build_test_ceph.sh

helm install kolla/ceph-admin-pod --version $PACKAGE_VERSION \
    --namespace kolla --name ceph-admin-pod --set kube_logger=false

helm install kolla/ceph-rbd-daemonset --version $PACKAGE_VERSION \
    --namespace kolla --name ceph-rbd-daemonset --set kube_logger=false

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
tools/setup_rbd_volumes.sh --yes-i-really-really-mean-it "$BRANCH"

if [ "x$4" == "xhelm-entrypoint" ]; then
   tests/bin/ceph_workflow_service.sh "$4" "$2" "$BRANCH"
else
   tests/bin/ceph_workflow.sh "$4" "$2" "$BRANCH"
fi

. ~/keystonerc_admin
kubectl get pods --namespace=kolla
kubectl get svc --namespace=kolla
tests/bin/basic_tests.sh
tests/bin/build_docker_images.sh $WORKSPACE/logs $DISTRO $TYPE $CONFIG $PIPELINE
