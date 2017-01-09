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


def install_microservice(name, operator):

    microservice_url = "http://helm-repo:{}/{}-{}.tgz". \
        format(helm_port, name, operator.version)

    command_line = 'helm install {} --debug --namespace {} --name {}'. \
        format(microservice_url, operator.namespace,
               '-'.join([name, operator.label]))
    args1 = ' --set "port={},element_name={},operator_label={},'. \
        format(operator.port, '-'.join([name, operator.label]), operator.label)
    args2 = 'operator_configmap={},kube_logger=false" '. \
        format(operator.configmaps[0]['name'])

    command_line = ''.join([command_line, args1, args2])
    print(command_line)

    try:
        subprocess.check_call(command_line, shell=True,
                              executable='/bin/bash')
    except subprocess.CalledProcessError as e:
        print(e.reason)
        return False

    return True


def put_request(cluster, operator, r_str, var, val):

    data = operator.json_data
    data['spec'][var] = val
    data['metadata']['resourceVersion'] = '0'
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


def build_api_request_by_label(cluster, operator, object_kind,
                               api_branch='api', api_version='v1',
                               label_name='operator'):

    r_str = "{}/{}/{}/namespaces/{}/{}?labelSelector={}%3D{}".format(
        cluster.dialString,
        api_branch, api_version, operator.namespace,
        object_kind, label_name, operator.label)

    return r_str


def build_all_of_kind_request(cluster, operator, object_kind, api_branch='api',
                              api_version='v1'):

    r_str = "{}/{}/{}/namespaces/{}/{}".format(
        cluster.dialString,
        api_branch, api_version, operator.namespace, object_kind)

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


def check_object_status(cluster, operator, object_kind,
                        name, timeout, api_version='v1',
                        api_branch='api'):

    r_str = build_api_request_by_label(cluster, operator, object_kind,
                                       api_branch, api_version)
    print(r_str)
    times = timeout // 10
    i = 0
    while (i < times):
        data = get_request(cluster, r_str)
        if data != '':
            data = json.loads(data)
            if str(data['items']) != 'None':
                for item in data['items']:
                    if str(item['metadata']['name']) == \
                        str(name + '-' + operator.label):
                        return True
        time.sleep(10)
        i += 1

    return False


def check_pod_status(cluster, operator, name, timeout):

    r_str = build_all_of_kind_request(cluster, operator, 'pods')
    print(r_str)
    times = timeout // 10
    i = 0
    while (i < times):
        data = get_request(cluster, r_str)
        if data != '':
            data = json.loads(data)
            if str(data['items']) != 'None':
                for item in data['items']:
                    if str(name + '-' + operator.label) in \
                       str(item['metadata']['name']):
                        return True
        time.sleep(10)
        i += 1

    return False


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
    check_for_configmaps(cluster, operator)
    dict_temp = {}
    for item in operator.json_data['spec']:
        if item == 'configmaps':
            for i, configmap in enumerate(operator.json_data['spec']
                                          ['configmaps']):
                if operator.__dict__[item][i]['version'] != \
                   operator.json_data['spec'][item][i]['version']:
                    dict_temp[item] = operator.__dict__[item][i]['name']
                    list_of_changes.append(dict_temp)
                    dict_temp = {}
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


def sync_configmap_version(cluster, operator, name):

    for i, configmap in enumerate(operator.configmaps):
        if configmap['name'] == name:
            operator.configmaps[i]['version'] = \
                operator.json_data['spec']['configmaps'][i]['version']
    r_str = build_operator_request(cluster, operator)
    put_request(cluster, operator, r_str, 'state', operator.state)

    return True


def check_for_configmaps(cluster, operator):

    for i, configmap in enumerate(operator.configmaps):
        r_str = build_configmap_request(cluster, operator,
                                        operator.configmaps[i]['name'])
        operator.json_data['spec']['configmaps'][i]['version'] = \
            get_configmap_version(cluster, r_str)

    return True


def service_deployment(cluster, operator):

    # If configmaps required for memcached are not created
    # this call will not return control.
    check_for_configmaps(cluster, operator)
    # Installing memcached svc
    if install_microservice('memcached-svc', operator) is False:
        return False

    # Service has been deployed, need to check if it actually exists
    if check_object_status(cluster, operator, object_kind='services',
                           name='memcached-svc', timeout=60) is False:
        return False
    else:
        print('Service Object has been found, moving on...')
    if install_microservice('memcached-deployment', operator) is False:
        return False

    # Service has been deployed, need to check if it actually exists
    if check_object_status(cluster, operator, object_kind='deployments',
                           name='memcached-deployment', timeout=60,
                           api_branch='apis/extensions',
                           api_version='v1beta1') is False:
        return False
    else:
        print('Memcached has been deployed...')

    # Last check for running memcached POD
    if check_pod_status(cluster, operator, name='memcached-deployment',
                        timeout=60) is False:
        return False
    else:
        print('Memcached POD is running...')

    # After a service gets deployed, values of operator class
    # object, must be updated.
    r_str = build_operator_request(cluster, operator)
    if (put_request(cluster, operator, r_str, 'state', 'deployed') == ''):
        return False
    else:
        operator.json_data['spec']['state'] = 'deployed'
        operator.state = 'deployed'

    return True


def service_state_sync(cluster, operator, list_of_changes):

    print('Changes detected')

    for i, item in enumerate(list_of_changes):
        print(item)
        if 'configmaps' in item:
            print('Configmap change detected in ', item['configmaps'])
            sync_configmap_version(cluster, operator, item['configmaps'])
            print('Re-deploying memcached service')

    return True


def check_for_recovery(cluster, operator):

    operator.json_data = check_for_operator_object(cluster, operator)

    if operator.json_data['spec']['label'] == '':
        return False
    else:
        return True


def load_operator_from_json(operator):
    for item in operator.json_data['spec']:
        if item == 'configmaps':
            for configmap in operator.json_data['spec']['configmaps']:
                operator.__dict__[item].append(configmap)
        else:
            operator.__dict__[item] = operator.json_data['spec'][item]
    return True


def do_info_recovery(cluster, operator):

    r_str = build_operator_request(cluster, operator)
    operator.json_data = json.loads(get_request(cluster, r_str))
    load_operator_from_json(operator)
    check_for_configmaps(cluster, operator)

    # Ideally here all objects of memchaed must be checked

    return True


def initialize_operator(cluster, operator, label):

    r_str = build_operator_request(cluster, operator)
    put_request(cluster, operator, r_str, 'label', label)
    load_operator_from_json(operator)
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
        label = '154b6510b2d9'
        initialize_operator(cluster, operator, label)
        if service_deployment(cluster, operator):
            print('Initial deployment was completed successfully')
        else:
            print('Initial deployment failed')
            sys.exit()

    # Main Life cycle of operator
    list_of_changes = []

    while True:

        check_for_operator_object(cluster, operator)

        list_of_changes = check_for_state_change(cluster, operator)

        # Checking if operator object is in sync with operator class object
        if len(list_of_changes) != 0:
            print('Object state is NOT in sync...')
            # It is just state change, calling service_state_sync()
            if service_state_sync(cluster, operator, list_of_changes):
                print('Sync up was completed successfully')
            else:
                print('Sync up failed')
            print('End of processing, short breath and onto the next cycle...')
            list_of_changes = []
            time.sleep(10)
        else:
            print('Object state is in sync...')
            time.sleep(10)


if __name__ == '__main__':
    sys.exit(main())
