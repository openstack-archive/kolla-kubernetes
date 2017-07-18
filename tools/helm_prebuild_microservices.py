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
import os
import subprocess
import sys
import yaml


stateful_services = [
    'rabbitmq-pv',
    'rabbitmq-pvc',
    'mariadb-pv',
    'mariadb-pvc',
    'glance-pv',
    'glance-pvc',
    'helm-repo-pv',
    'helm-repo-pvc'
]

pod_http_termination = [
    'neutron-server-deployment',
    'nova-api-deployment',
    'nova-novncproxy-deployment',
    'nova-placement-deployment',
    'cinder-api-deployment',
    'glance-api-deployment',
    'glance-registry-deployment',
    'heat-api-cfn-deployment',
    'heat-api-deployment',
    'ironic-api-deployment',
    'ironic-inspector-deployment'
]

common_mariadb = [
    'keystone-create-db-job',
    'neutron-create-db-job',
    'nova-create-db-job',
    'nova-api-create-db-job',
    'nova-cell0-create-db-job',
    'cinder-create-db-job',
    'glance-create-db-job',
    'ironic-api-create-db-job',
    'ironic-api-manage-db-job',
    'ironic-inspector-create-db-job',
    'ironic-inspector-manage-db-job',
    'heat-create-db-job',
    'cinder-delete-db-job',
    'glance-delete-db-job',
    'keystone-delete-db-job',
    'neutron-delete-db-job',
    'nova-delete-db-job',
    'nova-api-delete-db-job',
    'ironic-api-delete-db-job',
    'ironic-inspector-delete-db-job',
    'heat-create-db-job',
    'heat-delete-db-job'
]

common_create_keystone_admin = [
    'ironic-create-keystone-service-job',
    'ironic-create-keystone-user-job',
    'ironic-api-create-keystone-endpoint-public-job',
    'ironic-api-create-keystone-endpoint-internal-job',
    'ironic-api-create-keystone-endpoint-admin-job',
    'ironic-inspector-create-keystone-service-job',
    'ironic-inspector-create-keystone-user-job',
    'ironic-inspector-create-keystone-endpoint-public-job',
    'ironic-inspector-create-keystone-endpoint-internal-job',
    'ironic-inspector-create-keystone-endpoint-admin-job',
    'neutron-create-keystone-service-job',
    'neutron-create-keystone-endpoint-public-job',
    'neutron-create-keystone-endpoint-internal-job',
    'neutron-create-keystone-endpoint-admin-job',
    'cinder-create-keystone-user-job',
    'glance-create-keystone-user-job',
    'glance-create-keystone-service-job',
    'glance-create-keystone-endpoint-public-job',
    'glance-create-keystone-endpoint-internal-job',
    'glance-create-keystone-endpoint-admin-job',
    'neutron-create-keystone-user-job',
    'nova-create-keystone-user-job',
    'nova-create-keystone-service-job',
    'nova-create-keystone-endpoint-public-job',
    'nova-create-keystone-endpoint-internal-job',
    'nova-create-keystone-endpoint-admin-job',
    'nova-placement-create-keystone-user-job',
    'nova-placement-create-keystone-service-job',
    'nova-placement-create-keystone-endpoint-public-job',
    'nova-placement-create-keystone-endpoint-internal-job',
    'nova-placement-create-keystone-endpoint-admin-job',
    'cinder-create-keystone-service-job',
    'cinder-create-keystone-servicev2-job',
    'cinder-create-keystone-endpoint-public-job',
    'cinder-create-keystone-endpoint-internal-job',
    'cinder-create-keystone-endpoint-admin-job',
    'cinder-create-keystone-endpoint-publicv2-job',
    'cinder-create-keystone-endpoint-internalv2-job',
    'cinder-create-keystone-endpoint-adminv2-job',
    'cinder-delete-keystone-service-job',
    'cinder-delete-keystone-servicev2-job',
    'cinder-delete-keystone-user-job',
    'glance-delete-keystone-service-job',
    'glance-delete-keystone-user-job',
    'neutron-delete-keystone-service-job',
    'neutron-delete-keystone-user-job',
    'nova-delete-keystone-service-job',
    'nova-delete-keystone-user-job',
    'ironic-inspector-delete-keystone-service-job',
    'ironic-inspector-delete-keystone-user-job',
    'ironic-delete-keystone-service-job',
    'ironic-delete-keystone-user-job',
    'heat-create-keystone-user-job',
    'heat-create-keystone-service-job',
    'heat-create-keystone-endpoint-public-job',
    'heat-create-keystone-endpoint-internal-job',
    'heat-create-keystone-endpoint-admin-job',
    'heat-delete-keystone-user-job',
    'heat-delete-keystone-service-job',
    'heat-cfn-create-keystone-service-job',
    'heat-cfn-create-keystone-endpoint-public-job',
    'heat-cfn-create-keystone-endpoint-internal-job',
    'heat-cfn-create-keystone-endpoint-admin-job',
    'heat-cfn-delete-keystone-service-job'
]


def helm_dep_up(srcdir):
    command_line = "cd %s; helm dep up --skip-refresh" % (srcdir)
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
    values = yaml.safe_load(open(os.path.join(srcdir, "all_values.yaml")))

    packages = [p for p in microservices if _isdir(microdir, p)]
    count = 1
    for package in packages:
        if sys.stdout.isatty():
            sys.stdout.write("\rProcessing %3i/%i " % (count, len(packages)))
            sys.stdout.flush()
            count += 1
        pkgdir = os.path.join(microdir, package)
        helm_dep_up(pkgdir)
        pkg_values = {}
        if package in common_create_keystone_admin:
            key = 'common-create-keystone-admin'
            merge_dict(pkg_values, values[key])
        if package in pod_http_termination:
            merge_dict(pkg_values, values['pod-http-termination'])
        if package in stateful_services:
            merge_dict(pkg_values, values['stateful-service'])
        if package in common_mariadb:
            merge_dict(pkg_values, values['common-mariadb'])
        if package in values:
            merge_dict(pkg_values, values[package])
        with open(os.path.join(microdir, package, "values.yaml"), "w") as f:
            f.write("# This file is generated. Please edit all_values.yaml\n")
            f.write("# and rerun tools/helm_prebuild.py\n")
            f.write(yaml.safe_dump(pkg_values, default_flow_style=False))
    if sys.stdout.isatty():
            sys.stdout.write("\r                             \n")
            sys.stdout.flush()

if __name__ == '__main__':
    sys.exit(main())
