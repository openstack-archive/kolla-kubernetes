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
import sys
import yaml
import subprocess

password_file = "/etc/kolla/passwords.yml"

if not os.path.exists(password_file):
    print ("You need to generate password file before using this script")
    exit(1)

with open(password_file, 'r') as stream:
    try:
        passwords = yaml.safe_load(stream)
    except yaml.YAMLError as exc:
        print(exc)
for element in passwords:
    if isinstance(passwords[element], basestring):
        service_name = element.replace('_', '-')
        password_value = passwords[element]
        command_line = "kubectl create secret generic "
        command_line += service_name
        command_line += " --from-literal=password="
        command_line += password_value
        command_line = command_line.strip()  # strip whitespace
        try:
            res = subprocess.check_output(
                command_line, shell=True,
                executable='/bin/bash')
            res = res.strip()  # strip whitespace
            print res
        except subprocess.CalledProcessError as e:
            print e
exit(0)
