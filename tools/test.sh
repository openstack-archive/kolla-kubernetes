#!/bin/bash
[ ! -d ../kolla ] && pushd .. && git clone https://github.com/openstack/kolla && popd
pushd ../kolla && git pull && popd
python setup.py test --slowest --testr-args="$1"
