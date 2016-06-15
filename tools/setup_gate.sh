#!/bin/bash

set -o xtrace
set -o errexit

if [[ ! -f /etc/sudoers.d/jenkins ]]; then
    echo "jenkins ALL=(:docker) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/jenkins
fi

function setup_config {
    # Kolla will be used to generate config files
    git clone https://github.com/openstack/kolla

    pushd kolla
    sudo -H pip install -U "ansible>=2" "docker-py>=1.6.0"
    sed -i 's/#api_interface_address: 0.0.0.0/api_interface_address: 0.0.0.0/' etc/kolla/globals.yml
    sudo cp -a etc/kolla /etc/
    tox -e genconfig
    sudo tools/generate_passwords.py
    popd

    # Use Infra provided pypi
    echo "RUN echo $(base64 -w0 /etc/pip.conf) | base64 -d > /etc/pip.conf" | sudo tee /etc/kolla/header
    sed -i 's|^#include_header.*|include_header = /etc/kolla/header|' /etc/kolla/kolla-build.conf
}

function setup_logging {
    # This directory is the directory that is copied with the devstack-logs
    # publisher. It must exist at /home/jenkins/workspace/<job-name>/logs
    mkdir logs

    # For ease of access we symlink that logs directory to a known path
    ln -s $(pwd)/logs /tmp/logs
    mkdir -p /tmp/logs/{build,kolla,kolla_configs,system_logs}
}

setup_logging
tools/dump_info.sh
setup_config
