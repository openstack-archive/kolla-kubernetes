From centos:centos7

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
        net-tools; \
    pip install --upgrade pip setuptools; \
    adduser kolla;

ENV helm_version=v2.1.0
RUN curl -L http://storage.googleapis.com/kubernetes-helm/helm-${helm_version}-linux-amd64.tar.gz | \
    tar -zxv --strip 1 -C /tmp; \
    chmod +x /tmp/helm; \
    mv /tmp/helm /usr/local/bin/helm

COPY . /opt/kolla-kubernetes

WORKDIR /opt/kolla-kubernetes

ENTRYPOINT ["/usr/bin/bash"]

ENV development_env=docker
CMD ["tools/setup_dev_env.sh"]

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
                                  -v ~/.kube:/root/.kube:rw \
                                  kolla/k8s-devstack:latest"
