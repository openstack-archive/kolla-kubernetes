FROM ubuntu:16.04

RUN apt-get update && apt-get -y install python-dev curl libffi-dev gcc libssl-dev sshpass wget crudini
RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py \
    && python get-pip.py \
    && rm get-pip.py
RUN pip install ansible==2.2.* oslo_config

ENV HELM_LATEST_VERSION="v2.7.2"
ENV KUBE_LATEST_VERSION="v1.8.4"

RUN wget http://storage.googleapis.com/kubernetes-helm/helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz \
    && tar -xvf helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz \
    && mv linux-amd64/helm /usr/local/bin \
    && rm -f /helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz
RUN curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBE_LATEST_VERSION}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

ADD orchestration/ansible /ansible
ADD helm /helm
