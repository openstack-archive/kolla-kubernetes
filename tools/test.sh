#!/bin/bash
[ ! -d kolla ] && git clone https://github.com/openstack/kolla
pushd kolla && git pull && popd
[ ! -L etc/kolla ] && ln -s '../kolla/etc/kolla' etc/kolla
python setup.py test --slowest --testr-args="$1"
