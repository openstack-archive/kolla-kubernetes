#!/usr/bin/env python
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import copy
import errno
import os
import subprocess
import sys
import yaml


stateful_services = [
    'rabbitmq-pv',
    'mariadb-pv',
    'glance-pv'
]

pod_http_termination = [
    'neutron-server',
    'nova-api'
]

common_create_keystone_admin = [
    'neutron-create-keystone-service',
    'neutron-create-keystone-endpoint-public',
    'neutron-create-keystone-endpoint-internal',
    'neutron-create-keystone-endpoint-admin',
    'glance-create-keystone-user',
    'cinder-create-keystone-user',
    'neutron-create-keystone-user',
    'nova-create-keystone-user'
]


def helm_build_package(repodir, srcdir):
    command_line = "cd %s; helm package %s" % (repodir, srcdir)
    try:
        res = subprocess.check_output(
            command_line, shell=True,
            executable='/bin/bash')
        res = res.strip()  # strip whitespace
        print(res)
    except subprocess.CalledProcessError as e:
        print(e)
        raise


def _isdir(path, entry):
    return os.path.isdir(os.path.join(path, entry))


def main():
    path = os.path.abspath(os.path.dirname(sys.argv[0]))

    srcdir = os.path.join(path, "..", "helm")
    microdir = os.path.join(srcdir, "microservice")
    microservices = os.listdir(microdir)
    values = yaml.load(open(os.path.join(srcdir, "all_values.yaml")))

    for package in [p for p in microservices if _isdir(microdir, p)]:
        pkgchartdir = os.path.join(microdir, package, "charts")
        try:
            os.makedirs(pkgchartdir)
        except OSError as e:
            if e.errno != errno.EEXIST:
                raise
        helm_build_package(pkgchartdir, os.path.join(srcdir, "kolla-common"))
        pkg_values = copy.deepcopy(values['common'])
        if package in common_create_keystone_admin:
            pkg_values.update(values['common-create-keystone-admin'])
        if package in pod_http_termination:
            pkg_values.update(values['pod-http-termination'])
        if package in stateful_services:
            pkg_values.update(values['stateful-service'])
        try:
            pkg_values.update(values[package])
        except KeyError:
            pass
        f = open(os.path.join(microdir, package, "values.yaml"), "w")
        f.write("# This file is generated. Please edit all_values.yaml\n")
        f.write("# and rerun tools/helm_prebuild.py\n")
        f.write(yaml.safe_dump(pkg_values, default_flow_style=False))
        f.close()

if __name__ == '__main__':
    sys.exit(main())
