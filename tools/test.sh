#!/bin/bash
[ ! -d kolla ] && git clone https://github.com/openstack/kolla
pushd kolla && git pull && popd
[ ! -L etc/kolla ] && ln -s '../kolla/etc/kolla/globals.yml' etc/kolla-kubernetes/globals.yml
python setup.py test --slowest --testr-args="$1"
