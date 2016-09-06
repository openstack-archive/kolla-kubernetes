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
import yaml

from kolla_kubernetes.commands.cmd_resource import ResourceTemplate
from kolla_kubernetes.service_resources import KollaKubernetesResources
from kolla_kubernetes.tests import base

KKR = KollaKubernetesResources.Get()
RESOURCE_TYPES = ('secret pv pvc svc bootstrap pod').split(" ")

technical_debt = {
    'nodeSelector': [
        ['pod', 'nova', 'nova-compute-pod'],
        ['pod', 'openvswitch', 'openvswitch-db'],
        ['pod', 'openvswitch', 'openvswitch-vswitchd'],
        ['pod', 'neutron', 'neutron-openvswitch-agent-daemonset'],
        ['bootstrap', 'mariadb', 'mariadb-bootstrap-job'],
        ['pod', 'mariadb', 'mariadb-pod'],
        ['pod', 'memcached', 'memcached-pod'],
        ['bootstrap', 'keystone', 'keystone-bootstrap-job'],
        ['pod', 'keystone', 'keystone-pod'],
        ['pod', 'horizon', 'horizon-pod'],
        ['bootstrap', 'rabbitmq', 'rabbitmq-bootstrap-job'],
        ['pod', 'rabbitmq', 'rabbitmq-pod'],
        ['bootstrap', 'glance', 'glance-bootstrap-job'],
        ['pod', 'glance', 'glance-api-pod'],
        ['pod', 'glance', 'glance-registry-pod'],
        ['bootstrap', 'nova', 'nova-compute-bootstrap-job'],
        ['bootstrap', 'nova', 'create-api-db'],
        ['bootstrap', 'nova', 'create-endpoints'],
        ['bootstrap', 'nova', 'create-db'],
        ['pod', 'nova', 'nova-api-pod'],
        ['pod', 'nova', 'nova-conductor-pod'],
        ['pod', 'nova', 'nova-scheduler-pod'],
        ['bootstrap', 'neutron', 'neutron-bootstrap-job'],
        ['pod', 'neutron', 'neutron-control-pod'],
        ['pod', 'neutron', 'neutron-dhcp-agent-pod'],
        ['pod', 'neutron', 'neutron-l3-agent-pod'],
        ['pod', 'neutron', 'neutron-metadata-agent-pod'],
        ['pod', 'swift', 'swift-account-pod'],
        ['pod', 'swift', 'swift-container-pod'],
        ['pod', 'swift', 'swift-object-pod'],
        ['pod', 'swift', 'swift-proxy-pod'],
        ['pod', 'skydns', 'skydns-pod'],
        ['bootstrap', 'cinder',
         'cinder-bootstrap-job-create-db'],
        ['bootstrap', 'cinder',
         'cinder-bootstrap-job-manage-db'],
        ['bootstrap', 'cinder',
         'cinder-bootstrap-job-endpoints'],
        ['pod', 'cinder', 'cinder-api-pod'],
        ['pod', 'cinder', 'cinder-scheduler-pod']
    ],
    'namespaceNotFound': [
        ['pvc', 'mariadb', 'mariadb-pvc'],
        ['svc', 'mariadb', 'mariadb-service'],
        ['svc', 'memcached', 'memcached-service'],
        ['svc', 'keystone', 'keystone-service-admin'],
        ['svc', 'keystone', 'keystone-service-public'],
        ['svc', 'horizon', 'horizon-service'],
        ['pvc', 'rabbitmq', 'rabbitmq-pvc'],
        ['svc', 'rabbitmq', 'rabbitmq-service-management'],
        ['svc', 'rabbitmq', 'rabbitmq-service'],
        ['pvc', 'glance', 'glance-pvc'],
        ['svc', 'glance', 'glance-api-service'],
        ['svc', 'glance', 'glance-registry-service'],
        ['pod', 'glance', 'glance-api-haproxy-configmap'],
        ['pod', 'glance', 'glance-registry-haproxy-configmap'],
        ['svc', 'nova', 'nova-api'],
        ['svc', 'nova', 'nova-metadata'],
        ['pod', 'nova', 'nova-compute-pod'],
        ['svc', 'neutron', 'neutron-server-service'],
        ['pod', 'neutron', 'neutron-openvswitch-agent-daemonset'],
        ['svc', 'swift', 'swift-account-service'],
        ['svc', 'swift', 'swift-container-service'],
        ['svc', 'swift', 'swift-object-service'],
        ['svc', 'swift', 'swift-proxy-service'],
        ['svc', 'swift', 'swift-rsync-service'],
        ['pvc', 'cinder', 'cinder-pvc'],
        ['svc', 'cinder', 'cinder-api-service'],
        ['pod', 'cinder', 'cinder-api-haproxy-configmap'],
        ['bootstrap', 'mariadb', 'mariadb-bootstrap-job'],
        ['pod', 'mariadb', 'mariadb-pod'],
        ['pod', 'memcached', 'memcached-pod'],
        ['bootstrap', 'keystone', 'keystone-bootstrap-job'],
        ['pod', 'keystone', 'keystone-pod'],
        ['pod', 'horizon', 'horizon-pod'],
        ['bootstrap', 'rabbitmq', 'rabbitmq-bootstrap-job'],
        ['pod', 'rabbitmq', 'rabbitmq-pod'],
        ['bootstrap', 'glance', 'glance-bootstrap-job'],
        ['pod', 'glance', 'glance-api-pod'],
        ['pod', 'glance', 'glance-registry-pod'],
        ['bootstrap', 'nova', 'nova-compute-bootstrap-job'],
        ['bootstrap', 'nova', 'create-api-db'],
        ['bootstrap', 'nova', 'create-endpoints'],
        ['bootstrap', 'nova', 'create-db'],
        ['pod', 'nova', 'nova-api-pod'],
        ['pod', 'nova', 'nova-conductor-pod'],
        ['pod', 'nova', 'nova-scheduler-pod'],
        ['bootstrap', 'neutron', 'neutron-bootstrap-job'],
        ['pod', 'neutron', 'neutron-control-pod'],
        ['pod', 'neutron', 'neutron-dhcp-agent-pod'],
        ['pod', 'neutron', 'neutron-l3-agent-pod'],
        ['pod', 'neutron', 'neutron-metadata-agent-pod'],
        ['pod', 'swift', 'swift-account-pod'],
        ['pod', 'swift', 'swift-container-pod'],
        ['pod', 'swift', 'swift-object-pod'],
        ['pod', 'swift', 'swift-proxy-pod'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-create-db'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-manage-db'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-endpoints'],
        ['pod', 'cinder', 'cinder-api-pod'],
        ['pod', 'cinder', 'cinder-scheduler-pod']
    ],
    'namespaceInTemplate': [
        ['pod', 'nova', 'nova-compute-pod'],
        ['pod', 'openvswitch', 'openvswitch-db'],
        ['pod', 'openvswitch', 'openvswitch-vswitchd']
    ]
}


def unknown_technical_debt(args, selector):
    for i in technical_debt[selector]:
        if i[0] == args.resource_type and i[1] == args.service_name and \
           i[2] == args.resource_name:
            return False
    return True


class argobj(object):

    def __init__(self, action, resource_type, service_name, resource_name):
        self.service_name = service_name
        self.resource_type = resource_type
        self.resource_name = resource_name
        self.action = action
        self.print_jinja_keys_regex = None
        self.print_jinja_vars = False


def on_each_template(func):
    for service_name in KKR.getServices():
        service = KKR.getServiceByName(service_name)
        for resource_type in RESOURCE_TYPES:
            templates = service.getResourceTemplatesByType(resource_type)
            for template in templates:
                template_name = template.getName()
                args = argobj('create',
                              resource_type,
                              service_name,
                              template_name)
                print("Processing:", resource_type,
                      service_name, template_name)
                rt = ResourceTemplate('kolla-kubernetes.py',
                                      '', 'resource-template')
                o = rt.take_action(args=args, skip_and_return=True)
                func(args, o)


class TestTemplatesTest(base.BaseTestCase):

    def test_validate_templates(self):
        WERROR = True
        WARNING = {'found': False}

        def func(args, o):
            # Check if template is yaml
            y = yaml.load(o)
            js = '[]'
            try:
                # If there is an alpha init container, validate it is proper
                # json
                key = 'pod.alpha.kubernetes.io/init-containers'
                js = y['spec']['template']['metadata']['annotations'][key]
            except KeyError:
                pass
            except TypeError as e:
                m = ("'NoneType' object has no attribute '__getitem__'",
                     "'NoneType' object is not subscriptable")
                if e.args[0] not in m:
                    raise
            json.loads(js)
            if args.service_name != 'ceph':
                kind = y['kind']
                if 'namespace' not in y['metadata'] and \
                   kind != 'PersistentVolume' and \
                   unknown_technical_debt(args, 'namespaceNotFound'):
                    raise("namespace not found but required.")
                if kind in ('PetSet', 'Deployment', 'Job', 'DaemonSet',
                            'ReplicationController', 'Pod'):
                    pod = y
                    if kind != 'Pod':
                        pod = y['spec']['template']
                    if 'nodeSelector' not in pod['spec'] and \
                       unknown_technical_debt(args, 'nodeSelector'):
                        raise("nodeSelector not found but required.")
                    if 'namespace' in pod['metadata'] and kind != 'Pod' and \
                       unknown_technical_debt(args, 'namespaceInTemplate'):
                        raise("namespace found in inner template. its redundant.")
        on_each_template(func)
        if WARNING['found'] and WERROR:
            raise Exception('Found Warning when Werror set.')
