#!/bin/bash

set -o xtrace
set -o errexit

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

function copy_logs {
    cp -rnL /var/lib/docker/volumes/kolla_logs/_data/* /tmp/logs/kolla/
    cp -rnL /etc/kolla/* /tmp/logs/kolla_configs/
    cp -rvnL /var/log/* /tmp/logs/system_logs/

    if [[ -x "$(command -v journalctl)" ]]; then
        journalctl --no-pager -u docker.service > /tmp/logs/system_logs/docker.log
    else
        cp /var/log/upstart/docker.log /tmp/logs/system_logs/docker.log
    fi

    chmod -R 777 /tmp/logs/kolla /tmp/logs/kolla_configs /tmp/logs/system_logs
}

function sanity_check {
    #TOD0: implement sanity checks
    echo "sanity checks not implemented yet"
}

function check_container_failures {
    # Command failures after this point can be expected
    set +o errexit

    docker ps -a

    # TODO: Checking containers for now. In the future we need to detemine
    # failures in terms of pods.
    failed_containers=$(docker ps -a --format "{{.Names}}" --filter status=exited)

    for failed in ${failed_containers}; do
        docker logs --tail all ${failed}
    done

    copy_logs
}

trap check_container_failures EXIT

tools/kolla-kubernetes -d bootstrap all
tools/kolla-kubernetes -d run all

# Test OpenStack Environment
sanity_check
