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
    'nova-api',
    'nova-novncproxy',
    'cinder-api',
    'glance-api',
    'glance-registry',
    'heat-api-cfn',
    'heat-api'
]

common_create_keystone_admin = [
    'neutron-create-keystone-service',
    'neutron-create-keystone-endpoint-public',
    'neutron-create-keystone-endpoint-internal',
    'neutron-create-keystone-endpoint-admin',
    'cinder-create-keystone-user',
    'glance-create-keystone-user',
    'glance-create-keystone-service',
    'glance-create-keystone-endpoint-public',
    'glance-create-keystone-endpoint-internal',
    'glance-create-keystone-endpoint-admin',
    'neutron-create-keystone-user',
    'nova-create-keystone-user',
    'nova-create-keystone-service',
    'nova-create-keystone-endpoint-public',
    'nova-create-keystone-endpoint-internal',
    'nova-create-keystone-endpoint-admin',
    'cinder-create-keystone-service',
    'cinder-create-keystone-servicev2',
    'cinder-create-keystone-endpoint-public',
    'cinder-create-keystone-endpoint-internal',
    'cinder-create-keystone-endpoint-admin',
    'cinder-create-keystone-endpoint-publicv2',
    'cinder-create-keystone-endpoint-internalv2',
    'cinder-create-keystone-endpoint-adminv2'
]


def helm_build_package(repodir, srcdir):
    command_line = "cd %s; helm package %s" % (repodir, srcdir)
    try:
        res = subprocess.check_output(
            command_line, shell=True,
            executable='/bin/bash')
        res = res.strip()  # strip whitespace
        if res != "":
            print(res)
    except subprocess.CalledProcessError as e:
        print(e)
        raise


def _isdir(path, entry):
    return os.path.isdir(os.path.join(path, entry))


def merge_dict(a, b):
    for key in b:
        if key not in a:
            a[key] = b[key]
        else:
            if isinstance(b[key], dict):
                merge_dict(a[key], b[key])
            else:
                a[key] = b[key]


def main():
    path = os.path.abspath(os.path.dirname(sys.argv[0]))

    srcdir = os.path.join(path, "..", "helm")
    microdir = os.path.join(srcdir, "microservice")
    microservices = os.listdir(microdir)
    values = yaml.load(open(os.path.join(srcdir, "all_values.yaml")))

    packages = [p for p in microservices if _isdir(microdir, p)]
    count = 1
    for package in packages:
        if sys.stdout.isatty():
            sys.stdout.write("\rProcessing %i/%i" % (count, len(packages)))
            sys.stdout.flush()
            count += 1
        pkgchartdir = os.path.join(microdir, package, "charts")
        try:
            os.makedirs(pkgchartdir)
        except OSError as e:
            if e.errno != errno.EEXIST:
                raise
        helm_build_package(pkgchartdir, os.path.join(srcdir, "kolla-common"))
        pkg_values = copy.deepcopy(values['common'])
        if package in common_create_keystone_admin:
            key = 'common-create-keystone-admin'
            merge_dict(pkg_values, values[key])
        if package in pod_http_termination:
            merge_dict(pkg_values, values['pod-http-termination'])
        if package in stateful_services:
            merge_dict(pkg_values, values['stateful-service'])
        if package in values:
            merge_dict(pkg_values, values[package])
        f = open(os.path.join(microdir, package, "values.yaml"), "w")
        f.write("# This file is generated. Please edit all_values.yaml\n")
        f.write("# and rerun tools/helm_prebuild.py\n")
        f.write(yaml.safe_dump(pkg_values, default_flow_style=False))
        f.close()
    if sys.stdout.isatty():
            sys.stdout.write("\r                             \n")
            sys.stdout.flush()

if __name__ == '__main__':
    sys.exit(main())
