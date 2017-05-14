#!/bin/bash

## Compilation of Instructions from Kolla Kubernetes Gate
## This is meant to set up Kolla Kubernetes All-In-One for CentOS-7
## Cinder iSCSI backend is used here
## Note that $1 will be the kube proxy IP, $2 will be the tunnel_interface, $3 will be the ext_interface_name, 
## $4 will be the keepalived VIP, $5 will be the subnet size of the keepalived VIP network
## Lastly, $6 will take the value of master or minion (note that it will always be master for AIO)
## Note that keepalive runs on the same subnet as the "management" subnet, i.e. tunnel_interface
## The keepalived VIP should be an unused IP in the "management" subnet
## Run the script as root user

## Ensure that the required parameters are passed in
if [ "$#" -ne 6 ]
then
  echo "Please provide the following Information to the script: 
       \$1 for kube proxy IP,
       \$2 for tunnel_interface,
       \$3 for ext interface, 
       \$4 for keepalived VIP, 
       \$5 for subnet size of management network,
       \$6 for master/minion" 
  exit 1
fi


## Ensure that the specified interface exist and are UP on the system
function check_ifup {
    set -o pipefail # optional.
    /usr/sbin/ip address | grep $1 | grep -q "state UP"
}

function check_eth {
if check_ifup $1;
then
  echo "Interface $1 validated as UP."
else
  echo "Please make sure interface $1 is present and UP before running the script."
  exit 1
fi
}

check_eth $2
check_eth $3


## Setup Host
sudo sed -i 's/enforcing/permissive/g' /etc/selinux/config
sudo yum install -y net-tools wget telnet
sudo yum install -y epel-release
sudo yum install -y python-pip
sudo yum install -y git gcc python-devel libffi-devel openssl-devel crudini jq
sudo pip install -U pip


## Turn off firewalld
sudo systemctl stop firewalld
sudo systemctl disable firewalld


## Install Ansible
sudo yum install -y ansible


## Setup NTP
sudo yum install -y ntp
sudo systemctl enable ntpd.service
sudo systemctl start ntpd.service


## Git Clone Kolla Ansible
cd /opt && git clone http://github.com/openstack/kolla-ansible


## Git Clone Kolla Kubernetes
cd /opt && git clone http://github.com/openstack/kolla-kubernetes


## Install kolla-ansible and kolla-kubernetes
sudo pip install -U /opt/kolla-ansible/ /opt/kolla-kubernetes/


## Copy default Kolla configuration to /etc
cp -aR /usr/share/kolla-ansible/etc_examples/kolla /etc


## Copy default kolla-kubernetes configuration to /etc
cp -aR kolla-kubernetes/etc/kolla-kubernetes /etc


## Set Up Kubernetes

# Assign apiserver-advertise-address
mkdir -p /etc/nodepool/
echo $1 > /etc/nodepool/primary_node_private

cd /opt/kolla-kubernetes && tools/setup_kubernetes.sh $6

sudo yum install -y python-docker-py
sudo systemctl enable docker
sudo systemctl enable kubelet


## Setup Canal
cd /opt/kolla-kubernetes && tests/bin/setup_canal.sh


## Untaint Master
kubectl taint nodes --all=true node-role.kubernetes.io/master:NoSchedule-


## Setup Helm
cd /opt/kolla-kubernetes && tools/setup_helm.sh


## Setup Loopback LVM for Cinder
/opt/kolla-kubernetes/tests/bin/setup_gate_loopback_lvm.sh


## Pip Install OpenStack Client
sudo pip install python-openstackclient
sudo pip install python-neutronclient
sudo pip install python-cinderclient


## Generate Default Passwords
kolla-kubernetes-genpwd


## Create Kolla Namespace
kubectl create namespace kolla


## Label the AIO node as the compute and controller node
kubectl label node $(hostname) kolla_compute=true
kubectl label node $(hostname) kolla_controller=true


## Add required Kolla Kubernetes configuration to the end of /etc/kolla/globals.yml
cat <<EOF > add-to-globals.yml
kolla_install_type: "source"
tempest_image_alt_id: "{{ tempest_image_id }}"
tempest_flavor_ref_alt_id: "{{ tempest_flavor_ref_id }}"

neutron_plugin_agent: "openvswitch"
api_interface_address: 0.0.0.0
tunnel_interface_address: 0.0.0.0
orchestration_engine: KUBERNETES
memcached_servers: "memcached"
keystone_admin_url: "http://keystone-admin:35357/v3"
keystone_internal_url: "http://keystone-internal:5000/v3"
keystone_public_url: "http://keystone-public:5000/v3"
glance_registry_host: "glance-registry"
neutron_host: "neutron"
keystone_database_address: "mariadb"
glance_database_address: "mariadb"
nova_database_address: "mariadb"
nova_api_database_address: "mariadb"
neutron_database_address: "mariadb"
cinder_database_address: "mariadb"
ironic_database_address: "mariadb"
placement_database_address: "mariadb"
rabbitmq_servers: "rabbitmq"
openstack_logging_debug: "True"
enable_haproxy: "no"
enable_heat: "no"
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
enable_cinder_backend_iscsi: "yes"
enable_cinder_backend_rbd: "no"
enable_ceph: "no"
enable_elasticsearch: "no"
enable_kibana: "no"
glance_backend_ceph: "no"
cinder_backend_ceph: "no"
nova_backend_ceph: "no"
EOF
cat ./add-to-globals.yml | sudo tee -a /etc/kolla/globals.yml


## Generate the Kubernetes secrets and register them with Kubernetes
/opt/kolla-kubernetes/tools/secret-generator.py create


## Generate Default Configurations
cd /opt/kolla-kubernetes && ansible-playbook -e ansible_python_interpreter=/usr/bin/python -e @/etc/kolla/globals.yml -e @/etc/kolla/passwords.yml -e CONFIG_DIR=/etc/kolla ansible/site.yml


## Set libvirt type to QEMU
sudo crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
sudo crudini --set /etc/kolla/nova-compute/nova.conf libvirt cpu_mode none
sudo crudini --set /etc/kolla/keystone/keystone.conf cache enabled False


## Create and register Kolla config maps
kollakube res create configmap \
    mariadb keystone horizon rabbitmq memcached nova-api nova-conductor \
    nova-scheduler glance-api-haproxy glance-registry-haproxy glance-api \
    glance-registry neutron-server neutron-dhcp-agent neutron-l3-agent \
    neutron-metadata-agent neutron-openvswitch-agent openvswitch-db-server \
    openvswitch-vswitchd nova-libvirt nova-compute nova-consoleauth \
    nova-novncproxy nova-novncproxy-haproxy neutron-server-haproxy \
    nova-api-haproxy cinder-api cinder-api-haproxy cinder-backup \
    cinder-scheduler cinder-volume iscsid tgtd keepalived \
    placement-api placement-api-haproxy


## Enable resolv.conf workaround
/opt/kolla-kubernetes/tools/setup-resolv-conf.sh kolla


## Build all Helm microcharts, service charts, and metacharts
/opt/kolla-kubernetes/tools/helm_build_all.sh /tmp/


## Create cloud.yml file for the deployment of the charts
cat <<EOF > /opt/cloud.yaml
global:
   kolla:
     all:
       docker_registry: docker.io
       image_tag: "4.0.0"
       kube_logger: false
       external_vip: $1
       base_distro: "centos"
       install_type: "source"
       tunnel_interface: $2
       resolve_conf_net_host_workaround: true
       kolla_kubernetes_external_subnet: $5
       kolla_kubernetes_external_vip: $4
       kube_logger: false
     keepalived:
       all:
         api_interface: br-ex
     keystone:
       all:
         admin_port_external: "true"
         dns_name: $1
       public:
         all:
           port_external: "true"
     rabbitmq:
       all:
         cookie: 67
     glance:
       api:
         all:
           port_external: "true"
     cinder:
       api:
         all:
           port_external: "true"
       volume_lvm:
         all:
           element_name: cinder-volume
         daemonset:
           lvm_backends:
           - $1: 'cinder-volumes'
     ironic:
       conductor:
         daemonset:
           selector_key: "kolla_conductor"
     nova:
       placement_api:
         all:
           port_external: true
       novncproxy:
         all:
           host: $1
           port: 6080
           port_external: true
     openvswitch:
       all:
         add_port: true
         ext_bridge_name: br-ex
         ext_interface_name: $3
         setup_bridge: true
     horizon:
       all:
         port_external: true
EOF


# Set up OVS for the Infrastructure
helm install --debug /opt/kolla-kubernetes/helm/service/openvswitch --namespace kolla --name openvswitch --values /opt/cloud.yaml

while [ `kubectl get pods -n kolla -o wide | grep openvswitch-vswitchd | awk '{print $3}'` != 'Running' ]
do
  sleep 10
done


# Bring up br-ex for keepalived to bind VIP to it

sudo ifconfig br-ex up

helm install --debug /opt/kolla-kubernetes/helm/microservice/keepalived-daemonset --namespace kolla --name keepalived-daemonset --values /opt/cloud.yaml


while [ `kubectl get pods -n kolla -o wide | grep keepalived | awk '{print $3}'` != 'Running' ]
do
  sleep 10
done


## Execute OpenStack Helm Charts in Phases
helm install --debug /opt/kolla-kubernetes/helm/service/mariadb --namespace kolla --name mariadb --values /opt/cloud.yaml

while [ `kubectl get pods -n kolla -o wide | grep mariadb-0 | awk '{print $3}'` != 'Running' ]
do
  sleep 10
done

helm install --debug /opt/kolla-kubernetes/helm/service/rabbitmq --namespace kolla --name rabbitmq --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/service/memcached --namespace kolla --name memcached --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/service/keystone --namespace kolla --name keystone --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/service/glance --namespace kolla --name glance --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/service/cinder-control --namespace kolla --name cinder-control --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/service/cinder-volume-lvm --namespace kolla --name cinder-volume-lvm --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/service/horizon --namespace kolla --name horizon --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/service/neutron --namespace kolla --name neutron --values /opt/cloud.yaml

while [ `kubectl get pods -n kolla -o wide | grep neutron-server | awk '{print $3}'` != 'Running' ]
do
  sleep 10
done

helm install --debug /opt/kolla-kubernetes/helm/service/nova-control --namespace kolla --name nova-control --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/service/nova-compute --namespace kolla --name nova-compute --values /opt/cloud.yaml


while [ `kubectl get pods -n kolla -o wide | grep nova-compute | awk '{print $3}'` != 'Running' ]
do
  sleep 10
done

helm install --debug /opt/kolla-kubernetes/helm/microservice/nova-cell0-create-db-job --namespace kolla --name nova-cell0-create-db-job --values /opt/cloud.yaml
helm install --debug /opt/kolla-kubernetes/helm/microservice/nova-api-create-simple-cell-job --namespace kolla --name nova-api-create-simple-cell --values /opt/cloud.yaml
