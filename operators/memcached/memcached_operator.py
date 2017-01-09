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

import json
import os
import os.path
import subprocess
import sys
import time
import urllib2
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
            with open('/var/run/secrets/kubernetes.io/serviceaccount/token',
                      'r') as f:
                token = f.read()
        except (OSError, IOError):
            pass
        return token

    def build_dial_string(self):
        dial_string = 'https://{}:{}'.format(
                      os.environ["KUBERNETES_SERVICE_HOST"],
                      os.environ["KUBERNETES_PORT_443_TCP_PORT"])
        return dial_string


def add_helm_repo():

    command_line = "helm repo add --debug  \
                        helm-repo http://helm-repo:{}".format(helm_port)
    try:
        subprocess.check_output(command_line,
                                shell=True, executable='/bin/bash')
    except subprocess.CalledProcessError:
        return 1
    return 0


def generate_label():

    label = str(uuid.uuid4())[-12:]
    return label


def install_microservice(microservice_name, microservice_version,
                         operator_namespace='kolla'):
    microservice_url = "http://helm-repo:{}/{}-{}.tgz". \
        format(helm_port, microservice_name,
               microservice_version)
    print(microservice_url)
    return 0


def run_request(cluster, r_str):

    headers = {'Authorization': 'Bearer ' + cluster.token}
    req = urllib2.Request(url=r_str, headers=headers)
    try:
        response = urllib2.urlopen(req)
    except urllib2.URLError as e:
        print(e.reason)
        return ''
    data = response.read()

    return data


def build_api_request(cluster, namespace, object_kind, label, api_branch='api',
                      api_version='v1', wait_time=30):

    r_str = "{}/{}/namespaces/{}?labelSelector=operator%3D{}".format(
        cluster.dialString,
        api_branch, api_version, namespace,
        object_kind, label)

    return r_str


def build_3rd_party_request(cluster, api_branch='apis', api_version='v1',
                            domain='openstack.kolla',
                            object_kind='memcachedoperators'):

    r_str = "{}/{}/{}/{}/{}".format(cluster.dialString, api_branch, domain,
                                    api_version, object_kind)

    return r_str


def wait_for_deploy(cluster):

    r_str = build_3rd_party_request(cluster)
    print(r_str)
    data = run_request(cluster, r_str)

    while True:
        data = run_request(cluster, r_str)
        if data != '':
            break
        else:
            time.sleep(30)

    decoded_data = json.loads(data)
    items = decoded_data['items'][0]
    item = items['spec']

    while item['state'] == 'standby':
        time.sleep(60)

    return item['state']


def check_object_status(cluster, object_kind, label):

    return 0


def main():

    if add_helm_repo() != 0:
        raise SystemExit('Failed to add helm-repo to the list. Exiting...')

    label = generate_label()
    label = '24ac7811240b'
    cluster = KubernetesCluster('kube-1')

    print('Exit "standby" state, new state: ', wait_for_deploy(cluster))

    install_microservice("memcached-svc", "3.0.0-1",
                         operator_namespace='kolla')

    object_kind = 'svc'

    if check_object_status(cluster, object_kind, label) != 0:
        raise SystemExit('Failed to create kubernetes object. Exiting...')


if __name__ == '__main__':
    sys.exit(main())
