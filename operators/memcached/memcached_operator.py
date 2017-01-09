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
        self.configmaps = []
        self.label = ''
        self.json_data = ''

    def print_data(self):
        print('name: ', self.name)
        print('namespace: ', self.namespace)
        print('version: ', self.version)
        print('port: ', self.port)
        print('service: ', self.service)
        print('state: ', self.state)
        print('configmaps: ', self.configmaps)
        print('label: ', self.label)
        print('json data: ', self.json_data)


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


def install_microservice(microservice_name, operator):

    microservice_url = "http://helm-repo:{}/{}-{}.tgz". \
        format(helm_port, microservice_name,
               operator.version)
    command_line = "helm install {} --debug --dry-run --namespace {} \
                    --name {} --set port={}".format(microservice_url,
                                                    operator.namespace,
                                                    microservice_name + '-' +
                                                    operator.label,
                                                    operator.port)
    print(command_line)

    return True


def put_request(cluster, operator, r_str, var, val):

    # (sbezverk) Add check for correct state list
    data = operator.json_data
    data['spec'][var] = val
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


def build_configmap_request(cluster, operator, configmap_name):

    r_str = "{}/api/v1/namespaces/{}/configmaps/{}".format(
        cluster.dialString, operator.namespace, configmap_name)

    return r_str


def build_api_request(cluster, operator, object_kind, api_branch='api',
                      api_version='v1'):

    r_str = "{}/{}/namespaces/{}?labelSelector=operator%3D{}".format(
        cluster.dialString,
        api_branch, api_version, operator.namespace,
        object_kind, operator.label)

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
        print('Comparing items: ', operator.json_data['spec'][item],
              operator.__dict__[item])
        if item == 'configmaps':
            if str(operator.json_data['spec'][item]).strip('[]{}') != \
                str(operator.__dict__[item]).strip('[]{}'):
                list_of_changes.append(item)
        else:
            if operator.json_data['spec'][item] != operator.__dict__[item]:
                list_of_changes.append(item)

    return list_of_changes


def get_configmap_version(cluster, r_str):

    data = get_request(cluster, r_str)

    while True:
        data = get_request(cluster, r_str)
        if data != '':
            break
        else:
            print('No configmap found, waiting ...')
            time.sleep(30)
    decoded_data = json.loads(data)

    return decoded_data['metadata']['resourceVersion']


def check_for_configmaps(cluster, operator):

    for item in operator.configmaps:
        r_str = build_configmap_request(cluster, operator, item['name'])
        version = get_configmap_version(cluster, r_str)
        item['version'] = version
        operator.json_data['spec']['configmaps'] = item

    return True


def service_deployment(cluster, operator):

    # If configmaps required for memcached are not created
    # this call will not return control.
    check_for_configmaps(cluster, operator)

    # Installing memcached svc
    install_microservice("memcached-svc", operator)
    object_kind = 'svc'
    check_object_status(cluster, operator, object_kind)

    # After a service gets deployed, values of operator class
    # object, must be updated.

    r_str = build_operator_request(cluster, operator)
    data = put_request(cluster, operator, r_str, 'state', 'deployed')
    print(data)
#    operator.json_data = json.loads(put_request(cluster, operator, r_str,
#                                                'state', 'deployed'))

#    for item in operator.json_data['spec']:
#        operator.__dict__[item] = operator.json_data['spec'][item]

    return True


def service_state_sync(cluster, operator, list_of_changes):
    return True


def check_for_recovery(cluster, operator):

    operator.json_data = check_for_operator_object(cluster, operator)

    if operator.json_data['spec']['label'] == '':
        return False
    else:
        return True


def do_info_recovery(cluster, operator):
    return False


def initialize_operator(cluster, operator, label):

    r_str = build_operator_request(cluster, operator)
    put_request(cluster, operator, r_str, 'label', label)

    operator.json_data = json.loads(get_request(cluster, r_str))
    for item in operator.json_data['spec']:
        operator.__dict__[item] = operator.json_data['spec'][item]
    operator.json_data['spec']['state'] = 'init'
    check_for_configmaps(cluster, operator)
    put_request(cluster, operator, r_str, 'state', 'init')
    operator.state = 'init'

    return True


def main():

    if not add_helm_repo():
        raise SystemExit('Failed to add helm-repo to the list. Exiting...')

    cluster = KubernetesCluster('kube-1')

    # (sbezverk) Later change to use variables for memcached-operator and
    # namespace. name provided in MemcachedOperator must match to the name of
    # third party resource opreator object.
    operator = MemcachedOperator(name='memcached-operator', namespace='kolla')

    # Check for recovery verifies not only if third party resource object
    # exist, but also if the operator recovering from 'delete' scenario
    # The indication of this scenario would be fully initialized third
    # party operator object.

    if check_for_recovery(cluster, operator):
        # In recovery scenarion, the label stored in third party object gets
        # retrived and used instead of generating a new one.
        print('Recovery scenario')
        do_info_recovery(cluster, operator)
    else:
        print('Initial scenario')
        # Third party Operator object gets initialized by assigning it
        # unique label.
        label = generate_label()
        # Label will be automatically genearated
        # for debugging purposes, static label is used.
        label = '24ac7811240b'
        initialize_operator(cluster, operator, label)
        if service_deployment(cluster, operator):
            print('Initial deployment was completed successfully')
        else:
            print('Initial deployment failed')

    # Main Life cycle of operator
    list_of_changes = []

    while True:

        check_for_operator_object(cluster, operator)
        operator.print_data()
        list_of_changes = check_for_state_change(cluster, operator)
        print('Changes: ', list_of_changes)
        # Checking if operator object is in sync with operator class object
        if len(list_of_changes) != 0:
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
