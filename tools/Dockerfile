From centos:centos7

ENV helm_version=v2.1.3 \
    development_env=docker

# build up base os layer
RUN set -e; \
    set -x; \
    export KUBE_REPO=/etc/yum.repos.d/kubernetes.repo; \
    echo '[kubernetes]' > ${KUBE_REPO}; \
    echo 'name=Kubernetes' >> ${KUBE_REPO}; \
    echo 'baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64' >> ${KUBE_REPO}; \
    echo 'enabled=1' >> ${KUBE_REPO}; \
    echo 'gpgcheck=1' >> ${KUBE_REPO}; \
    echo 'repo_gpgcheck=1' >> ${KUBE_REPO}; \
    echo 'repo_gpgcheck=1' >> ${KUBE_REPO}; \
    echo 'gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg' >> ${KUBE_REPO}; \
    echo '       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg' >> ${KUBE_REPO}; \
    yum install -y \
        epel-release; \
    yum install -y \
        git \
        git-review \
        python-virtualenv \
        python-devel \
        python-pip \
        gcc \
        openssl-devel \
        crudini \
        sudo \
        jq \
        sshpass \
        hostname \
        kubectl \
        iproute2 \
        wget \
        net-tools; \
    pip install --upgrade pip setuptools; \
    adduser kolla; \
    # install helm
    curl -L http://storage.googleapis.com/kubernetes-helm/helm-${helm_version}-linux-amd64.tar.gz | \
    tar -zxv --strip 1 -C /tmp; \
    chmod +x /tmp/helm; \
    mv /tmp/helm /usr/local/bin/helm; \
    # install vagrant (could be added to run or made conditional for non-vagrant envs?)
    wget https://releases.hashicorp.com/vagrant/1.9.1/vagrant_1.9.1_x86_64.rpm; \
    yum --nogpgcheck localinstall -y vagrant_1.9.1_x86_64.rpm

# build up temporary dev environment specific layer
COPY repos /opt/ 
RUN  pip install pip --upgrade; \
     pip install "ansible<2.1"; \
     pip install "python-openstackclient"; \
     pip install "python-neutronclient"; \
     pip install -r /opt/kolla-ansible/requirements.txt; \
     pip install -e /opt/kolla-ansible/; \
     pip install pyyaml; \
     pip install -r /opt/kolla-kubernetes/requirements.txt; \
     pip install -e /opt/kolla-kubernetes/; \
     mkdir -p /etc/nodepool; \
     echo "172.16.35.12" > /etc/nodepool/primary_node_private; \
     rm -rf /etc/kolla; \
     rm -rf /usr/share/kolla; \
     rm -rf /etc/kolla-kubernetes; \
     ln -s /opt/kolla-ansible/etc/kolla /etc/kolla; \
     ln -s /opt/kolla-ansible /usr/share/kolla; \
     ln -s /opt/kolla-kubernetes/etc/kolla-kubernetes /etc/kolla-kubernetes; \
     mkdir /root/.ssh; \
     mv /opt/halcyon-vagrant-kubernetes/ssh-config /root/.ssh/config; \
     echo 'sleep infinity' > /bootstrap.sh; \
     chmod +x /bootstrap.sh


WORKDIR /opt/kolla-kubernetes

ENTRYPOINT ["/usr/bin/bash"]

CMD ["/bootstrap.sh"]

LABEL docker.cmd.build = "docker build . --tag 'kolla/k8s-devstack:latest'"

# Run in the hosts network namespace to ensure we have routes to the k8s cluster
# otherwise set up a route to the k8s cluster on the host from the docker0 iface
LABEL docker.cmd.devel = "docker run -it --rm \
                                  --net=host \
                                  -e USER_NAME=$(id -un) \
                                  -e USER_ID=$(id -u) \
                                  -e USER_GROUP_NAME=$(id -gn) \
                                  -e USER_GROUP_ID=$(id -g) \
                                  -v ~/.kube/config:/root/.kube/config:ro \
                                  -v `pwd`:/opt/kolla-kubernetes:rw \
                                  --entrypoint=/bin/bash \
                                  kolla/k8s-devstack:latest"

LABEL docker.cmd.run = "docker run -it --rm \
                                  --net=host \
                                  -v ~/.kube:/root/.kube:rw \
                                  kolla/k8s-devstack:latest"
