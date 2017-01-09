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


class MemcachedOperator(object):
    def __init__(self, name, namespace):
        self.name = name
        self.namespace = namespace
        self.version = ''
        self.port = ''
        self.service = ''
        self.state = ''
        self.json_data = ''


def add_helm_repo():

    command_line = "helm repo add --debug  \
                        helm-repo http://helm-repo:{}".format(helm_port)
    try:
        subprocess.check_output(command_line,
                                shell=True, executable='/bin/bash')
    except subprocess.CalledProcessError as err:
        print(err)
        return False
    return True


def generate_label():

    label = str(uuid.uuid4())[-12:]
    return label


def install_microservice(microservice_name, microservice_version,
                         operator_namespace='kolla'):
    microservice_url = "http://helm-repo:{}/{}-{}.tgz". \
        format(helm_port, microservice_name,
               microservice_version)
    print(microservice_url)
    return True


def put_request(cluster, operator, r_str, state):

    # (sbezverk) Add check for correct state list
    data = operator.json_data
    data['spec']['state'] = state
    encoded_data = json.dumps(data)
    clen = len(encoded_data)
    req = urllib2.Request(url=r_str, data=encoded_data)
    req.add_header('Authorization', 'Bearer ' + cluster.token)
    req.add_header('Content-Type', 'application/json')
    req.add_header('Accept', 'application/json')
    req.add_header('Accept-Encoding', 'gzip')
    req.add_header('Content-Length', clen)
    req.get_method = lambda: 'PUT'
    try:
        response = urllib2.urlopen(req)
    except urllib2.URLError as e:
        print(e.reason)
        return ''
    data = response.read()
    response.close()

    return data


def get_request(cluster, r_str):

    headers = {'Authorization': 'Bearer ' + cluster.token}
    req = urllib2.Request(url=r_str, headers=headers)
    try:
        response = urllib2.urlopen(req)
    except urllib2.URLError as e:
        print(e.reason)
        return ''
    data = response.read()
    response.close()

    return data


def build_api_request(cluster, namespace, object_kind, label, api_branch='api',
                      api_version='v1', wait_time=30):

    r_str = "{}/{}/namespaces/{}?labelSelector=operator%3D{}".format(
        cluster.dialString,
        api_branch, api_version, namespace,
        object_kind, label)

    return r_str


def build_operator_request(cluster, operator, api_branch='apis',
                           api_version='v1', domain='openstack.kolla',
                           object_kind='memcachedoperators'):

    r_str = "{}/{}/{}/{}/namespaces/{}/{}/{}".format(cluster.dialString,
                                                     api_branch, domain,
                                                     api_version,
                                                     operator.namespace,
                                                     object_kind,
                                                     operator.name)

    return r_str


def reset_operator_state(cluster, operator):

    r_str = build_operator_request(cluster, operator)

    data = put_request(cluster, operator, r_str, 'standby')

    print(data)

    return True


def check_object_status(cluster, object_kind, label):

    return True


def check_for_operator_object(cluster, operator):

    r_str = build_operator_request(cluster, operator)
    data = get_request(cluster, r_str)

    while True:
        data = get_request(cluster, r_str)
        if data != '':
            break
        else:
            print('No operator found, waiting ...')
            time.sleep(30)
    decoded_data = json.loads(data)

    return decoded_data


def check_for_state_change(cluster, operator):
    list_of_changes = []
    # Taking snapshot of the state of the operator object before
    # parsing changes.
    operator.json_data = check_for_operator_object(cluster, operator)
    for item in operator.json_data['spec']:
        if operator.json_data['spec'][item] != operator.__dict__[item]:
            list_of_changes.append(item)

    return list_of_changes


def check_for_initial_deployment(operator):

    for item in operator.json_data['spec']:
        if operator.__dict__[item] != '':
            print('It is NOT initial deployment')
            return False
    print('It is initial deployment')

    return True


def service_deployment(cluster, operator, label):
    # install_microservice("memcached-svc", "3.0.0-1",
    #                     operator_namespace='kolla')
    # object_kind = 'svc'

    # check_object_status(cluster, object_kind, label)

    # After a service gets deployed, values of operator class
    # object, must be updated.
    for item in operator.json_data['spec']:
        operator.__dict__[item] = operator.json_data['spec'][item]

    return True


def service_state_sync(cluster, operator, list_of_changes):
    return True


def main():

    if not add_helm_repo():
        raise SystemExit('Failed to add helm-repo to the list. Exiting...')

    label = generate_label()
    # Label will be automatically genearated
    # for debugging purposes, static label is used.
    label = '24ac7811240b'
    cluster = KubernetesCluster('kube-1')

    # (sbezverk) Later change to use variables for memcached-operator and
    # namespace
    operator = MemcachedOperator('memcached-operator', 'kolla')

    # Main Life cycle of operator
    list_of_changes = []
    while True:

        check_for_operator_object(cluster, operator)
        list_of_changes = check_for_state_change(cluster, operator)
        print(list_of_changes)
        # Checking if operator object is in sync with operator class object
        if len(list_of_changes) != 0:
            if check_for_initial_deployment(operator):
                # It is initial deployment, calling deployment()
                if service_deployment(cluster, operator, label):
                    print('Deployment was completed successfully')
                else:
                    print('Deployment failed')
            else:
                # It is just state change, calling service_state_sync()
                if service_state_sync(cluster, operator, list_of_changes):
                    print('Sync up was completed successfully')
                else:
                    print('Sync up failed')
            print('End of processing, short breath and onto the next cycle...')
            time.sleep(10)
        else:
            print('Object state is in sync...')
            time.sleep(10)


if __name__ == '__main__':
    sys.exit(main())
