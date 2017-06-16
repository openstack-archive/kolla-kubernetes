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
    sudo apt-get install lvm2 iproute2
    sudo apt-get remove -y open-iscsi
    sudo apt-get install -y bridge-utils tftp
    (echo server:; echo "  interface: 172.19.0.1"; echo "  access-control: 0.0.0.0/0 allow") | \
        sudo /bin/bash -c "cat > /etc/unbound/unbound.conf.d/kubernetes.conf"
else
    sudo yum clean all
    sudo yum-config-manager --enable epel
    sudo yum remove -y iscsi-initiator-utils
    sudo yum install -y bridge-utils tftp
    sudo yum install -y lvm2 iproute
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
 - name: openstack/kolla
   dest: kolla
EOF

sudo cp -aR `pwd`/etc/kolla-kubernetes /etc/kolla-kubernetes
sudo cp -aR `pwd`/etc/kolla /etc/kolla
sudo mkdir -p /etc/kolla/config

if [ -f /etc/redhat-release ]; then
    sudo yum install -y crudini jq sshpass bzip2
else
    sudo apt-get update
    sudo apt-get install -y crudini jq sshpass bzip2
fi

pip install pip --upgrade
pip install "ansible"
pip install "python-cinderclient==1.11.0"
pip install "python-openstackclient"
pip install "python-novaclient"
pip install "python-neutronclient"
pip install "selenium"
pip install -r requirements.txt
pip install pyyaml
pip install .

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

tools/helm_build_all.sh ~/.helm/repository/kolla
tools/helm_buildrepo.sh ~/.helm/repository/kolla 10192 kolla &
helm update
helm search
}

function setup_namespace_secrets {
kubectl create namespace kolla
tools/secret-generator.py create
}
