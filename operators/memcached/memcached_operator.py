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

import argparse
import json
import urllib2
import os.path
import os
import subprocess
import sys
import yaml
import uuid

helm_port = '8879'
operator_namespace = 'kolla'

class KubernetesCluster(object):
    def __init__(self, name):
        self.name = name
        self.token = self.load_token()
        self.dialString = self.build_dial_string()

    def load_token(self):
        token = ''
        try:
            with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'r') as f:
                token = f.read()
        except (OSError, IOError):
            pass 
        return token

    def build_dial_string(self):
        dial_string = 'https://{}:{}/api/'.format(os.environ["KUBERNETES_SERVICE_HOST"],os.environ["KUBERNETES_PORT_443_TCP_PORT"]) 
        return dial_string

def add_helm_repo():

    command_line = "helm repo add --debug helm-repo http://helm-repo:{}".format( helm_port)
    try:
        res = subprocess.check_output(  command_line, shell=True, executable='/bin/bash')
    except subprocess.CalledProcessError as e:
        return 1
    return 0

def generate_label():
    '''
    generate unique label used for operator
    to identify object belonging to it.
    '''
    label = str(uuid.uuid4())[-12:]
    return label

def install_microservice(microservice_name,microservice_version,operator_namespace='kolla'):
    microservice_url = "http://helm-repo:{}/{}-{}.tgz".format( helm_port, microservice_name, microservice_version)
    print(microservice_url)
    return 0

def check_object_status(object_kind, label, wait_time=120):
    return 0

def main():

    if add_helm_repo() != 0:
       raise SystemExit('Failed to add helm-repo to the list. Exiting...')

    label = generate_label()
    label = '24ac7811240b'
    cluster = KubernetesCluster('kube-1')
    print('Retrieved token: ',cluster.token)
    print('Dial string: ',cluster.dialString)

    install_microservice("memcached-svc","3.0.0-1",operator_namespace='kolla')

    object_kind = 'svc'

    if check_object_status(object_kind, label) != 0:
       raise SystemExit('Failed to create kubernetes object. Exiting...')

if __name__ == '__main__':
    sys.exit(main())
