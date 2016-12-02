#!/bin/bash -xe
install_reqs () {
  if [ -f /etc/redhat-release ]; then
      for PACKAGE in crudini jq sshpass python-devel; do
        rpm -q $PACKAGE || sudo yum install -y $PACKAGE
      done
  else
      sudo apt-get update
      sudo apt-get install -y crudini jq sshpass
  fi
}
install_reqs


setup_venv () {
  mkdir -p .venv
  if [ -f .venv/Kolla-Kube/bin/activate ];
  then
     echo "Kolla-Kube virtual env already exists."
  else
     virtualenv .venv/Kolla-Kube
  fi
  . .venv/Kolla-Kube/bin/activate
}
setup_venv


setup_etc () {
  sudo rm -rf /etc/kolla
  sudo rm -rf /usr/share/kolla
  sudo rm -rf /etc/kolla-kubernetes
  sudo ln -s `pwd`/kolla/etc/kolla /etc/kolla
  sudo ln -s `pwd`/kolla /usr/share/kolla
  sudo ln -s `pwd`/etc/kolla-kubernetes /etc/kolla-kubernetes
}
setup_etc


install_kolla_ansible () {
  [ ! -d kolla-ansible ] && git clone https://github.com/openstack/kolla-ansible.git
  mv kolla-ansible kolla
  pushd kolla;
  pip install pip --upgrade
  pip install "ansible<2.1"
  pip install "python-openstackclient"
  pip install "python-neutronclient"
  pip install -r requirements.txt
  pip install pyyaml
  popd
}
install_kolla_ansible


install_kolla_kube () {
  pip install -r requirements.txt
  pip install .
}
install_kolla_kube


#https://github.com/openstack-infra/project-config/blob/master/jenkins/jobs/kolla-kubernetes.yaml
#https://github.com/openstack-infra/project-config/blob/master/jenkins/jobs/projects.yaml#L6416
setup_kolla_kube () {
  tests/bin/setup_config.sh "centos" "ceph-multi"
  sed -i "s/centos-home/172.16.35.12/g" /etc/kolla-kubernetes/kolla-kubernetes.yml
}
setup_kolla_kube


setup_helm () {
  mkdir -p ~/.helm/repository/local
  sed -i 's/local/kolla/' ~/.helm/repository/repositories.yaml
  tools/helm_prebuild.py
  tools/helm_build_microservices.py ~/.helm/repository/local
  helm serve &
  sleep 1
  helm repo update
  helm search
}
setup_helm


setup_node_labels () {
  kubectl get nodes -L kubeadm.alpha.kubernetes.io/role --no-headers | awk '$NF ~ /^<none>/ { print $1}' | while read NODE ; do
      kubectl label node $NODE --overwrite kolla_controller=true
      kubectl label node $NODE --overwrite kolla_compute=true
  done
}
setup_node_labels


setup_kolla_kube_resources () {
  kubectl create namespace kolla
  tools/secret-generator.py create
}
setup_kolla_kube_resources
