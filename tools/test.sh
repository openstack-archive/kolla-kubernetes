#!/bin/bash
[ ! -d kolla ] && git clone https://github.com/openstack/kolla
pushd kolla && git pull && popd
python setup.py test --slowest --testr-args="$1"
