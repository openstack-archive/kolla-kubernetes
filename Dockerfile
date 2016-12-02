From centos:centos7

RUN set -e; \
    set -x; \
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
        hostname; \
    pip install --upgrade pip setuptools; \
    adduser kolla;

ENV helm_version=v2.0.0
RUN curl -L http://storage.googleapis.com/kubernetes-helm/helm-${helm_version}-linux-amd64.tar.gz | \
    tar zxv --strip 1 -C /tmp; \
    chmod +x /tmp/helm; \
    mv /tmp/helm /usr/local/bin/helm

COPY . /opt/kolla-kubernetes

WORKDIR /opt/kolla-kubernetes

ENTRYPOINT ["/usr/bin/bash"]

ENV development_env=docker
CMD ["tools/setup_dev_env.sh"]
