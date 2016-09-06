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
import subprocess
import sys
import yaml

from kolla_kubernetes.service_resources import KollaKubernetesResources


def usage():
    print("secret-generator.py requires one of these two commands: \
           create or delete")
    return

if len(sys.argv) != 2:
    usage()
    exit(1)

command = sys.argv[1].lower().strip()

if (command != 'create' and command != 'delete'):
    usage()
    exit(2)

password_file = "/etc/kolla/passwords.yml"

if not os.path.exists(password_file):
    print ("You need to generate password file before using this script")
    exit(3)

with open(password_file, 'r') as stream:
    try:
        passwords = yaml.safe_load(stream)
    except yaml.YAMLError as exc:
        print(exc)
for element in passwords:
    if isinstance(passwords[element], basestring):
        service_name = element.replace('_', '-')
        password_value = passwords[element]
        nsname = 'kolla_kubernetes_namespace'
        nsname = KollaKubernetesResources.GetJinjaDict()[nsname]
        if command == "create":
            command_line = 'kubectl create secret generic {} {}{} {}{}'.format(
                           service_name,
                           " --from-literal=password=",
                           password_value,
                           "--namespace=",
                           nsname)
        else:
            command_line = "kubectl delete secret {} --namespace={}".format(
                           service_name, nsname)
        try:
            res = subprocess.check_output(
                command_line, shell=True,
                executable='/bin/bash')
            res = res.strip()  # strip whitespace
            print(res)
        except subprocess.CalledProcessError as e:
            print(e)
exit(0)
