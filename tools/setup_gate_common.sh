#!/bin/bash -xe

function install_wget {
    DISTRO="$1"
    if [ "$DISTRO" == "centos" -o "$DISTRO" == "oraclelinux" ]; then
        sudo yum -y install wget
    else
        sudo apt-get -y install wget
   fi
}

function prepare_images {
    DISTRO="$1"
    TYPE="$2"
    CONFIG="$3"
    BRANCH="$4"
    PIPELINE="$5"
    if [ "x$PIPELINE" != "xperiodic" ]; then
        C=$CONFIG
        if [ "x$CONFIG" == "xexternal-ovs" -o "x$CONFIG" == "xceph-multi" -o \
            "x$CONFIG" == "xhelm-entrypoint" -o "x$CONFIG" == "xhelm-operator" \
            ]; then
            C="ceph"
        fi
    fi
    mkdir -p $WORKSPACE/DOWNLOAD_CONTAINERS
    BASE_URL=http://tarballs.openstack.org/kolla-kubernetes/gate/containers

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
          "$WORKSPACE/DOWNLOAD_CONTAINERS/kubernetes.tar.bz2" \
        "$BASE_URL/kubernetes.tar.bz2"

    # NOTE(sdake): Obtain lists of containers
    wget -q -c -O \
        "$WORKSPACE/DOWNLOAD_CONTAINERS/$FILENAME-containers.txt" \
        "$BASE_URL/$FILENAME-containers.txt"
    wget -q -c -O \
        "$WORKSPACE/DOWNLOAD_CONTAINERS/kubernetes-containers.txt" \
        "$BASE_URL/kubernetes-containers.txt"
}

function setup_iptables {
sudo iptables-save > $WORKSPACE/logs/iptables-before.txt
tests/bin/fix_gate_iptables.sh
}

function setup_packages {
DISTRO=$1
CONFIG=$2
if [ "x$DISTRO" == "xubuntu" ]; then
    sudo apt-get update
    if [ "x$CONFIG" == "xiscsi" -o "x$CONFIG" == "xhelm-compute-kit" ]; then
       sudo apt-get install lvm2
    fi
    sudo apt-get remove -y open-iscsi
    sudo apt-get install -y bridge-utils
    (echo server:; echo "  interface: 172.19.0.1"; echo "  access-control: 0.0.0.0/0 allow") | \
        sudo /bin/bash -c "cat > /etc/unbound/unbound.conf.d/kubernetes.conf"
else
    sudo yum clean all
    if [ "x$CONFIG" == "xiscsi" -o "x$CONFIG" == "xhelm-compute-kit" ]; then
       sudo yum remove -y iscsi-initiator-utils
    fi
    sudo yum install -y bridge-utils
    sudo yum install -y lvm2
    (echo server:; echo "  interface: 172.19.0.1"; echo "  access-control: 0.0.0.0/0 allow") | \
        sudo /bin/bash -c "cat > /etc/unbound/conf.d/kubernetes.conf"
fi
}

function setup_bridge {
sudo brctl addbr dns0
sudo ifconfig dns0 172.19.0.1 netmask 255.255.255.0
sudo systemctl restart unbound
sudo systemctl status unbound
sudo netstat -pnl
sudo sed -i "s/127\.0\.0\.1/172.19.0.1/" /etc/resolv.conf
sudo cat /etc/resolv.conf
}

function setup_kolla {
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
pip install "python-cinderclient"
pip install -r requirements.txt
pip install pyyaml
popd
pip install -r requirements.txt
pip install .
}

function setup_helm_common {
tools/setup_helm.sh

tools/helm_build_all.sh ~/.helm/repository/kolla
helm repo remove kollabuild
tools/helm_buildrepo.sh ~/.helm/repository/kolla 10192 kolla &
helm update
helm search
}

function setup_namespace_secrets {
kubectl create namespace kolla
tools/secret-generator.py create
}

function setup_resolv_conf_common {
tools/setup-resolv-conf.sh kolla
}
