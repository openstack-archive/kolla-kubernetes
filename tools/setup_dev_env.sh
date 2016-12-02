#!/bin/bash -xe

setup_user () {
  groupadd ${USER_GROUP_NAME} -g ${USER_GROUP_ID}
  HOME_DIR=/home/${USER_NAME}
  adduser --home-dir ${HOME_DIR} --gid ${USER_GROUP_ID} --uid ${USER_ID} --non-unique ${USER_NAME}
  chmod 0600 /etc/sudoers
  echo "%${USER_GROUP_NAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
  chmod 0400 /etc/sudoers
  mkdir -p ${HOME_DIR}/.kube
  cat /root/.kube/config > ${HOME_DIR}/.kube/config
  chown -R ${USER_NAME}:${USER_GROUP_NAME} ${HOME_DIR}
}


install_reqs () {
  if [ -f /etc/redhat-release ]; then
      for PACKAGE in epel-release; do
        rpm -q $PACKAGE || sudo yum install -y $PACKAGE
      done
      for PACKAGE in git \
                     git-review \
                     python-virtualenv \
                     python-devel \
                     python-pip \
                     gcc \
                     openssl-devel \
                     crudini \
                     jq \
                     sshpass \
                     hostname \
                     net-tools; do
        rpm -q $PACKAGE || sudo yum install -y $PACKAGE
      done
  else
      sudo apt-get update
      for PACKAGE in build-essential \
                     git \
                     git-review \
                     python-virtualenv \
                     python-dev \
                     python-pip \
                     gcc \
                     libssl-dev \
                     libffi-dev \
                     crudini \
                     jq \
                     sshpass \
                     hostname; do
        dpkg -l | grep -q $PACKAGE || sudo apt-get install -y $PACKAGE
      done
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


install_kolla_ansible () {
  [ ! -d kolla ] && \
    git clone https://github.com/openstack/kolla-ansible.git kolla
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

sudo mkdir -p /etc/nodepool
sudo sh -c "echo \"172.16.35.12\" > /etc/nodepool/primary_node_private"

install_kolla_kube () {
  pip install -r requirements.txt
  pip install -e .
}
install_kolla_kube

setup_etc () {
  sudo rm -rf /etc/kolla
  sudo rm -rf /usr/share/kolla
  sudo rm -rf /etc/kolla-kubernetes
  sudo ln -s `pwd`/kolla/etc/kolla /etc/kolla
  sudo ln -s `pwd`/kolla /usr/share/kolla
  sudo ln -s `pwd`/etc/kolla-kubernetes /etc/kolla-kubernetes
}
setup_etc

#https://github.com/openstack-infra/project-config/blob/master/jenkins/jobs/kolla-kubernetes.yaml
#https://github.com/openstack-infra/project-config/blob/master/jenkins/jobs/projects.yaml#L6416
setup_kolla_kube () {
  tests/bin/setup_dev_config.sh "centos" "ceph-multi"
  sed -i "s/$(hostname -s)/kube2/g" /etc/kolla-kubernetes/kolla-kubernetes.yml
}
setup_kolla_kube
#
#
setup_helm () {
  helm init
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
#
#
setup_node_labels () {
  kubectl get nodes -L kubeadm.alpha.kubernetes.io/role --no-headers | awk '$NF ~ /^<none>/ { print $1}' | while read NODE ; do
      #kubectl label node $NODE --overwrite kolla_controller=true
      kubectl label node $NODE --overwrite kolla_compute=true
  done
  kubectl label node 172.16.35.12 --overwrite kolla_controller=true
}
setup_node_labels
#
#
setup_kolla_kube_resources () {
  kubectl create namespace kolla
  tools/secret-generator.py create
}
setup_kolla_kube_resources

tools/setup-resolv-conf.sh

if [[ "$development_env" = "docker" ]]; then
  echo "now run: tests/bin/build_dev_ceph.sh"
  exec /usr/bin/bash
fi
