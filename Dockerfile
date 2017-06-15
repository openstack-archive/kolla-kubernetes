FROM ubuntu:16.04

RUN apt-get update && apt-get -y install python-dev curl libffi-dev gcc libssl-dev sshpass wget
RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py \
    && python get-pip.py \
    && rm get-pip.py

ENV HELM_LATEST_VERSION="v2.4.2"
RUN pip install ansible==2.2.*
RUN wget http://storage.googleapis.com/kubernetes-helm/helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz \
    && tar -xvf helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz \
    && mv linux-amd64/helm /usr/local/bin \
    && rm -f /helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz

ADD ansible /ansible
ADD helm /helm

