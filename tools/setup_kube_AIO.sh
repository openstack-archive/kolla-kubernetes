#!/bin/bash

## Compilation of Instructions from Kolla Kubernetes Gate
## This is meant to set up Kolla Kubernetes All-In-One for CentOS-7
## Cinder iSCSI backend is used here
## Note that $1 will be the kube proxy IP, $2 will be the tunnel_interface and $3 will be the ext_interface_name


## Ensure that the required parameters are passed in
if [ "$#" -ne 3 ]
then
  echo "Please provide the following Information to the script: \$1 for kube proxy IP, \$2 for tunnel_interface, \$3 for ext interface"
  exit 1
fi


## Setup Host
yum install -y net-tools wget telnet


## Setup Pip
yum install -y epel-release
yum install -y python-pip
pip install -U pip


## Turn off SELinux
setenforce 0
sed -i 's/enforcing/permissive/g' /etc/selinux/config


## Turn off firewalld
systemctl stop firewalld
systemctl disable firewalld


## Setup Kubernetes Repository
cat <<"EOEF" > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOEF


## Install Kubernetes 1.6.2 and other dependencies
kubelet_version=1.6.2-0
yum install -y docker ebtables kubeadm-$kubelet_version kubectl-$kubelet_version kubelet-$kubelet_version kubernetes-cni-$kubelet_version git gcc python-devel libffi-devel openssl-devel crudini
yum install -y python-docker-py
sudo systemctl enable docker
sudo systemctl enable kubelet


## Install Ansible
yum install -y ansible


## Setup NTP
yum install -y ntp
systemctl enable ntpd.service
systemctl start ntpd.service


## Kubeadm
sed -i 's/10.96.0.10/172.16.128.10/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

modprobe br_netfilter || true
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
systemctl daemon-reload
systemctl start docker
systemctl restart kubelet

kubeadm init --skip-preflight-checks --service-cidr 172.16.128.0/24 --pod-network-cidr 172.16.132.0/22

mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config
chown $(id -u):$(id -g) ~/.kube/config

kubectl update -f <(cat <<EOF
apiVersion: rbac.authorization.k8s.io/v1alpha1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: Group
  name: system:masters
- kind: Group
  name: system:authenticated
- kind: Group
  name: system:unauthenticated
EOF
)


## Setup Canal
url="https://raw.githubusercontent.com/projectcalico/canal/master"
url="$url/k8s-install/1.6/canal.yaml"

curl "$url" -o /tmp/canal.yaml

url="https://raw.githubusercontent.com/projectcalico/canal/master"
url="$url/k8s-install/1.6/rbac.yaml"

curl "$url" -o /tmp/rbac.yaml

kubectl create -f /tmp/rbac.yaml

cluster_cidr=$(sudo grep cluster-cidr /etc/kubernetes/manifests/kube-controller-manager.yaml || true)
cluster_cidr=${cluster_cidr##*=}

network_conf=$(grep net-conf.json /tmp/canal.yaml || true)
if [ "x$network_conf" == "x" ]; then
   sed -i '/masquerade:/a\
  net-conf.json: |\
    {\
      "Network": "'$cluster_cidr'",\
      "Backend": {\
        "Type": "vxlan"\
      }\
    }' /tmp/canal.yaml
else
   sed -i 's@"Network":.*"@"Network": "'$cluster_cidr'"@' /tmp/canal.yaml
fi

kubectl create -f /tmp/canal.yaml


## Untaint Master
kubectl taint nodes --all=true  node-role.kubernetes.io/master:NoSchedule-


## Setup Helm
HELM_VERSION="2.3.0"
HELM_TEMPLATE_URL="https://github.com/technosophos/helm-template/releases/download/2.2.2%2B1/helm-template-linux-2.2.2.1.tgz"

HELM_URL="http://storage.googleapis.com/kubernetes-helm/helm-v$HELM_VERSION-linux-amd64.tar.gz"

curl "$HELM_URL" | sudo tar --strip-components 1 -C /usr/bin linux-amd64/helm -zxf -
helm init



## Setup Loopback LVM for Cinder 
mkdir -p /data/kolla
df -h
dd if=/dev/zero of=/data/kolla/cinder-volumes.img bs=5M count=2048
LOOP=$(losetup -f)
losetup $LOOP /data/kolla/cinder-volumes.img
parted -s $LOOP mklabel gpt
parted -s $LOOP mkpart 1 0% 100%
parted -s $LOOP set 1 lvm on
partprobe $LOOP
pvcreate -y $LOOP
vgcreate -y cinder-volumes $LOOP
echo "Finished prepping lvm storage on $LOOP"


## Pip Install OpenStack Client
pip install python-openstackclient
pip install python-neutronclient
pip install python-cinderclient


## Git Clone Kolla Ansible
cd /opt && git clone http://github.com/openstack/kolla-ansible


## Git Clone Kolla Kubernetes
cd /opt && git clone http://github.com/openstack/kolla-kubernetes


## Install kolla-ansible and kolla-kubernetes
pip install -U /opt/kolla-ansible/ /opt/kolla-kubernetes/


## Copy default Kolla configuration to /etc
cp -aR /usr/share/kolla-ansible/etc_examples/kolla /etc


## Copy default kolla-kubernetes configuration to /etc
cp -aR kolla-kubernetes/etc/kolla-kubernetes /etc


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
crudini --set /etc/kolla/nova-compute/nova.conf libvirt virt_type qemu
crudini --set /etc/kolla/nova-compute/nova.conf libvirt cpu_mode none
crudini --set /etc/kolla/keystone/keystone.conf cache enabled False


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
           port: 6080
           port_external: true
     openvwswitch:
       all:
         add_port: true
         ext_bridge_name: br-ex
         ext_interface_name: $3
         setup_bridge: true
     horizon:
       all:
         port_external: true
EOF


## Execute Helm Charts
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
helm install --debug /opt/kolla-kubernetes/helm/service/openvswitch --namespace kolla --name openvswitch --values /opt/cloud.yaml
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

