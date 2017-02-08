#!/bin/bash -xe

PACKAGE_VERSION=0.5.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$7"
PIPELINE="$8"

# TODO(sdake): install wget via ansible as per kolla-ansible deliverable
#              gating tools in the future
function install_wget {
    # NOTE(sdake) wget is far more reliable than curl
    if [ "$DISTRO == "centos" -o "$DISTRO == "oraclelinux" ]; then
        sudo yum -y install wget
    else
        sudo apt-get -y install wget
   fi
}

function prepare_images {
    if [ "x$PIPELINE" != "xperiodic" ]; then
        C=$CONFIG
        if [ "x$CONFIG" == "xexternal-ovs" -o "x$CONFIG" == "xceph-multi" -o \
            "x$CONFIG" == "xhelm-entrypoint" -o "x$CONFIG" == "xhelm-operator" \
            ]; then
            C="ceph"
        fi
    fi
    mkdir -p $WORKSPACE/DOWNLOAD_CONTAINERS
    BASE_URL=http://tarballs.openstack.org/kolla-kubernetes/gate/containers/

    # TODO(sdake): Cross-repo depends-on is completely broken

    FILENAME="$DISTRO-$TYPE-$BRANCH-$C.tar.bz2"

    # NOTE(sdake): This includes both a set of kubernetes containers
    #              for running kubernetes infrastructure as well as
    #              kolla containers for 2.0.2 and 3.0.2.  master images
    #              are not yet available via this mechanism.

    # NOTE(sdake): Obtain pre-built containers to load into docker
    #              via docker load

    wget -q -c -O \
        "$WORKSPACE/DOWNLOAD_CONTAINERS/$FILENAME" \
        "$BASE_URL/$FILENAME"
    wget -q -c -O \
          "$WORKSPACE/DOWNLOAD_CONTAINERS/kubernetes.tar.gz" \
        "$BASE_URL/containers/kubernetes.tar.gz"

    # NOTE(sdake): Obtain lists of containers
    wget -q -c -O \
        "$WORKSPACE/DOWNLOAD_CONTAINERS/$FILENAME-containers.txt" \
        "$BASE_URL/$FILENAME-containers.txt"
    wget -q -c -O \
        "$WORKSPACE/DOWNLOAD_CONTAINERS/kubernetes-containers.txt" \
        "$BASE_URL/containers/kubernetes-containers.txt"
}

if [ "x$BRANCH" == "xt" ]; then
    echo Version: $BRANCH is not enabled yet.
    exit 0
fi

# NOTE(sdake): This seems disturbing (see note at end of file)
if [ "x$PIPELINE" == "xperiodic" ]; then
    mkdir -p $WORKSPACE/UPLOAD_CONTAINERS
fi

install_wget
prepare_images

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

if [ "x$4" == "xceph-multi" ]; then
    cat /etc/nodepool/sub_nodes_private | while read line; do
        scp -r "$WORKSPACE/DOWNLOAD_CONTAINERS" $line:
    done
fi

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

tools/build_example_yaml.py

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
tests/bin/cleanup_tests.sh

# TODO(sdake): There is still a little bit of logic missing from
#              build_docker_images.sh.  The idea of the *-containers.txt
#              files, such as:
#              http://tarballs.openstack.org/kolla-kubernetes/gate/containers/kubernetes-containers.txt
#              Was to be able to be able to detect when changes to the
#              tarballs were made and avoid extraneous uploads when not
#              needed.  The build_docker_images.sh at the end of the
#              script needs to compare the list of containers for each
#              tarball from DOWNLOAD_CONTAINERS and UPLOAD_CONTAINERS. If
#              they compare the same, then we just delete that
#              tarball/-container.txt from UPLOAD_CONTAINERS and Zuul will
#              skip it.
#              Personal CI is a feature that still needs designing.  Most of
#              this logic could be reused for that case, but will need
#              additional work.

tests/bin/build_docker_images.sh $WORKSPACE/logs $DISTRO $TYPE $CONFIG $BRANCH $PIPELINE

