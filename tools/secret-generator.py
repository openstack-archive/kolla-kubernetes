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

import os.path
import six
import subprocess
import sys
import yaml


def usage():
    print("secret-generator.py <create|delete> [namespace]")
    return

if len(sys.argv) < 2:
    usage()
    exit(1)

command = sys.argv[1].lower().strip()

if (command != 'create' and command != 'delete'):
    usage()
    exit(2)

if len(sys.argv) == 3:
    namespace = sys.argv[2].lower().strip()
else:
    namespace = 'kolla'

password_file = "/etc/kolla/passwords.yml"
certificate_file = "/etc/kolla/certificates/haproxy.pem"

if not os.path.exists(password_file):
    print("You need to generate password file before using this script")
    exit(3)

with open(password_file, 'r') as stream:
    try:
        passwords = yaml.safe_load(stream)
    except yaml.YAMLError as exc:
        print(exc)
for element in passwords:
    if isinstance(passwords[element], six.string_types):
        service_name = element.replace('_', '-')
        password_value = passwords[element]
        if command == "create":
            command_line = "kubectl create secret generic {} " \
                           "--from-literal=password={} --namespace={}".format(
                               service_name, password_value, namespace)
        else:
            command_line = "kubectl delete secret {} --namespace={}".format(
                           service_name, namespace)
        try:
            res = subprocess.check_output(
                command_line, shell=True,
                executable='/bin/bash')
            res = res.strip()  # strip whitespace
            print(res)
        except subprocess.CalledProcessError as e:
            print(e)

if os.path.exists(certificate_file):
    if command == "create":
        command_line = "kubectl create secret generic {} " \
                       "--from-file={} --namespace={}".format(
            "haproxy-certificate", certificate_file, namespace)
    else:
        command_line = "kubectl delete secret {} --namespace={}".format(
            "haproxy-certificate", namespace)
    try:
        res = subprocess.check_output(
            command_line, shell=True,
            executable='/bin/bash')
        res = res.strip()  # strip whitespace
        print(res)
    except subprocess.CalledProcessError as e:
        print(e)

exit(0)
