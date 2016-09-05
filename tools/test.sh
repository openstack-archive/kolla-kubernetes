#!/bin/bash
[ ! -d ../kolla ] && pushd .. && git clone https://github.com/openstack/kolla && popd
grep api_interface_address ../kolla/etc/kolla/globals.yml || echo api_interface_address: "0.0.0.0" >> ../kolla/etc/kolla/globals.yml
grep orchestration_engine ../kolla/etc/kolla/globals.yml || echo orchestration_engine: KUBERNETES >> ../kolla/etc/kolla/globals.yml
python setup.py test --slowest --testr-args="$1"
