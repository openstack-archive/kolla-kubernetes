#!/bin/bash -xe

function setup_iptables {
sudo iptables-save > $WORKSPACE/logs/iptables-before.txt
tests/bin/fix_gate_iptables.sh
}

function setup_packages {
DISTRO=$1
CONFIG=$2
if [ "x$DISTRO" == "xubuntu" ]; then
    sudo apt-get update
    sudo apt-get install lvm2
    sudo apt-get remove -y open-iscsi
    sudo apt-get install -y bridge-utils tftp
    (echo server:; echo "  interface: 172.19.0.1"; echo "  access-control: 0.0.0.0/0 allow") | \
        sudo /bin/bash -c "cat > /etc/unbound/unbound.conf.d/kubernetes.conf"
else
    sudo yum clean all
    sudo yum-config-manager --enable epel
    sudo yum remove -y iscsi-initiator-utils
    sudo yum install -y bridge-utils tftp
    sudo yum install -y lvm2
    (echo server:; echo "  interface: 172.19.0.1"; echo "  access-control: 0.0.0.0/0 allow") | \
        sudo /bin/bash -c "cat > /etc/unbound/conf.d/kubernetes.conf"
fi
}

function setup_bridge {
sudo brctl addbr dns0
sudo ifconfig dns0 172.19.0.1 netmask 255.255.255.0
sudo brctl addbr net2
sudo ifconfig net2 172.22.0.1 netmask 255.255.255.0
sudo modprobe br_netfilter || true
sudo sh -c 'echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables'
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
 - name: openstack/kolla-ansible
   dest: kolla-ansible
EOF

# Change directories to /home/jenkins/workspace
cd ..

# Install main repositories
sudo pip install pip --upgrade
sudo pip install ansible


[ -x /usr/zuul-env/bin/zuul-cloner ] && \
/usr/zuul-env/bin/zuul-cloner -m /tmp/clonemap --workspace `pwd` \
    --branch master --cache-dir /opt/git git://git.openstack.org \
    openstack/kolla-ansible && true
[ ! -d kolla-ansible ] && git clone https://github.com/openstack/kolla-ansible.git

# $WORKSPACE here is the checked out kolla-kubernetes repostiory
sudo pip install kolla-ansible/ $WORKSPACE/

cd $WORKSPACE

if [ -f /etc/redhat-release ]; then
    sudo yum install -y crudini jq sshpass bzip2
else
    sudo apt-get update
    sudo apt-get install -y crudini jq sshpass bzip2
fi

sudo pip install pyyaml
sudo pip install selenium
sudo pip install python-neutronclient
sudo pip install python-openstackclient

sudo cp -aR /usr/share/kolla-ansible/etc_examples/kolla /etc
sudo cp -aR etc/kolla-kubernetes /etc
sudo mkdir -p /etc/kolla/config

# NOTE (sbezverk) Added as a workaround since kolla-ansible master had
# use_neutron config option removed. Next 4 lines can be removed after
# kolla_kubernetes stop using mitake 2.0.X images.
sudo bash -c 'cat << EOF > /etc/kolla/config/nova.conf
[DEFAULT]
use_neutron = True
EOF'
if [ "x$2" == "xironic" ]; then
sudo bash -c 'cat << EOF >> /etc/kolla/config/nova.conf
scheduler_default_filters = AggregateInstanceExtraSpecsFilter,RetryFilter,AvailabilityZoneFilter,RamFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter
ram_allocation_ratio = 1.0
reserved_host_memory_mb = 0
EOF'
sudo bash -c 'cat << EOF >> /etc/kolla/config/ironic.conf
[neutron]
cleaning_network = ironic-cleaning-net
EOF'
sudo bash -c 'cat << EOF >> /etc/kolla/config/ironic.conf
[pxe]
tftp_server = undefined
pxe_append_params = nofb nomodeset vga=normal console=tty0 console=ttyS0,115200n8
EOF'
fi
}

function setup_helm_common {
tools/setup_helm.sh

# FIXME removing stable repo as dep up gets refreshed way too frequently
# before helm 2.3.x. https://github.com/kubernetes/helm/pull/2021
helm repo remove stable

tools/helm_build_all.sh ~/.helm/repository/kolla
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
