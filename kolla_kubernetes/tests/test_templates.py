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
        ['pod', 'openvswitch', 'openvswitch-db'],
        ['pod', 'openvswitch', 'openvswitch-vswitchd'],
        ['pod', 'neutron', 'neutron-openvswitch-agent-daemonset'],
        ['bootstrap', 'glance', 'glance-bootstrap-job'],
        ['bootstrap', 'neutron', 'neutron-bootstrap-job'],
        ['pod', 'neutron', 'neutron-control-pod'],
        ['pod', 'neutron', 'neutron-dhcp-agent-pod'],
        ['pod', 'neutron', 'neutron-l3-agent-pod'],
        ['pod', 'neutron', 'neutron-metadata-agent-pod'],
    ],
    'namespaceNotFound': [
        ['svc', 'neutron', 'neutron-server-service'],
        ['pod', 'neutron', 'neutron-openvswitch-agent-daemonset'],
        ['pod', 'horizon', 'horizon-pod'],
        ['bootstrap', 'neutron', 'neutron-bootstrap-job'],
        ['pod', 'neutron', 'neutron-control-pod'],
        ['pod', 'neutron', 'neutron-dhcp-agent-pod'],
        ['pod', 'neutron', 'neutron-l3-agent-pod'],
        ['pod', 'neutron', 'neutron-metadata-agent-pod'],
    ],
    'namespaceInTemplate': [],
    'namespaceHardCoded': [],
    'nameInTemplateMetadata': [
        ['bootstrap', 'mariadb', 'mariadb-bootstrap-job'],
        ['bootstrap', 'keystone', 'keystone-bootstrap-job'],
        ['bootstrap', 'rabbitmq', 'rabbitmq-bootstrap-job'],
        ['bootstrap', 'glance', 'glance-create-db'],
        ['bootstrap', 'glance', 'glance-manage-db'],
        ['bootstrap', 'glance', 'glance-endpoints'],
        ['bootstrap', 'nova', 'nova-compute-bootstrap-job'],
        ['bootstrap', 'nova', 'create-api-db'],
        ['bootstrap', 'nova', 'create-endpoints'],
        ['bootstrap', 'nova', 'create-db'],
        ['pod', 'nova', 'nova-compute-pod'],
        ['pod', 'openvswitch', 'openvswitch-db'],
        ['pod', 'openvswitch', 'openvswitch-vswitchd'],
        ['bootstrap', 'neutron', 'neutron-bootstrap-job'],
        ['pod', 'neutron', 'neutron-openvswitch-agent-daemonset'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-create-db'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-manage-db'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-endpoints'],
        ['pod', 'cinder', 'cinder-volume-lvm-pod']
    ],
    'mainContainer': [
        ['bootstrap', u'mariadb', u'mariadb-bootstrap-job'],
        ['pod', u'mariadb', u'mariadb-pod'],
        ['pod', u'memcached', u'memcached-pod'],
        ['bootstrap', u'keystone', u'keystone-bootstrap-job'],
        ['pod', u'keystone', u'keystone-pod'],
        ['pod', u'horizon', u'horizon-pod'],
        ['bootstrap', u'rabbitmq', u'rabbitmq-bootstrap-job'],
        ['pod', u'rabbitmq', u'rabbitmq-pod'],
        ['bootstrap', u'glance', u'glance-create-db'],
        ['bootstrap', u'glance', u'glance-manage-db'],
        ['bootstrap', u'glance', u'glance-endpoints'],
        ['pod', u'glance', u'glance-api-pod'],
        ['pod', u'glance', u'glance-registry-pod'],
        ['bootstrap', u'nova', u'nova-compute-bootstrap-job'],
        ['bootstrap', u'nova', u'create-api-db'],
        ['bootstrap', u'nova', u'create-endpoints'],
        ['bootstrap', u'nova', u'create-db'],
        ['pod', u'nova', u'nova-compute-pod'],
        ['pod', u'nova', u'nova-api-pod'],
        ['pod', u'nova', u'nova-conductor-pod'],
        ['pod', u'nova', u'nova-scheduler-pod'],
        ['pod', u'openvswitch', u'openvswitch-db'],
        ['pod', u'openvswitch', u'openvswitch-vswitchd'],
        ['bootstrap', u'neutron', u'neutron-bootstrap-job'],
        ['pod', u'neutron', u'neutron-control-pod'],
        ['pod', u'neutron', u'neutron-dhcp-agent-pod'],
        ['pod', u'neutron', u'neutron-l3-agent-pod'],
        ['pod', u'neutron', u'neutron-metadata-agent-pod'],
        ['pod', u'swift', u'swift-account-pod'],
        ['pod', u'swift', u'swift-container-pod'],
        ['pod', u'swift', u'swift-object-pod'],
        ['pod', u'swift', u'swift-proxy-pod'],
        ['pod', u'skydns', u'skydns-pod'],
        ['pod', u'iscsi', u'iscsi-iscsid'],
        ['pod', u'iscsi', u'iscsi-tgtd'],
        ['bootstrap', u'cinder', u'cinder-bootstrap-job-create-db'],
        ['bootstrap', u'cinder', u'cinder-bootstrap-job-manage-db'],
        ['bootstrap', u'cinder', u'cinder-bootstrap-job-endpoints'],
        ['pod', u'cinder', u'cinder-api-pod'],
        ['pod', u'cinder', u'cinder-scheduler-pod'],
        ['pod', u'cinder', u'cinder-backup-pod'],
        ['pod', u'cinder', u'cinder-volume-lvm-pod'],
    ],
    'resourceNameObjNameNoMatch': [
        ['pv', 'mariadb', 'mariadb-pv'],
        ['pvc', 'mariadb', 'mariadb-pvc'],
        ['svc', 'mariadb', 'mariadb-service'],
        ['bootstrap', 'mariadb', 'mariadb-bootstrap-job'],
        ['pod', 'mariadb', 'mariadb-pod'],
        ['svc', 'memcached', 'memcached-service'],
        ['pod', 'memcached', 'memcached-pod'],
        ['svc', 'keystone', 'keystone-service-admin'],
        ['svc', 'keystone', 'keystone-service-public'],
        ['bootstrap', 'keystone', 'keystone-bootstrap-job'],
        ['pod', 'keystone', 'keystone-pod'],
        ['svc', 'horizon', 'horizon-service'],
        ['pod', 'horizon', 'horizon-pod'],
        ['pv', 'rabbitmq', 'rabbitmq-pv'],
        ['pvc', 'rabbitmq', 'rabbitmq-pvc'],
        ['svc', 'rabbitmq', 'rabbitmq-service-management'],
        ['svc', 'rabbitmq', 'rabbitmq-service'],
        ['bootstrap', 'rabbitmq', 'rabbitmq-bootstrap-job'],
        ['pod', 'rabbitmq', 'rabbitmq-pod'],
        ['pv', 'glance', 'glance-pv'],
        ['pvc', 'glance', 'glance-pvc'],
        ['svc', 'glance', 'glance-api-service'],
        ['svc', 'glance', 'glance-registry-service'],
        ['pod', 'glance', 'glance-api-haproxy-configmap'],
        ['pod', 'glance', 'glance-api-pod'],
        ['pod', 'glance', 'glance-registry-haproxy-configmap'],
        ['pod', 'glance', 'glance-registry-pod'],
        ['bootstrap', 'nova', 'nova-compute-bootstrap-job'],
        ['bootstrap', 'nova', 'create-api-db'],
        ['bootstrap', 'nova', 'create-endpoints'],
        ['bootstrap', 'nova', 'create-db'],
        ['pod', 'nova', 'nova-compute-pod'],
        ['pod', 'nova', 'nova-api-pod'],
        ['pod', 'nova', 'nova-conductor-pod'],
        ['pod', 'nova', 'nova-scheduler-pod'],
        ['svc', 'neutron', 'neutron-server-service'],
        ['bootstrap', 'neutron', 'neutron-bootstrap-job'],
        ['pod', 'neutron', 'neutron-openvswitch-agent-daemonset'],
        ['pod', 'neutron', 'neutron-control-pod'],
        ['pod', 'neutron', 'neutron-dhcp-agent-pod'],
        ['pod', 'neutron', 'neutron-l3-agent-pod'],
        ['pod', 'neutron', 'neutron-metadata-agent-pod'],
        ['svc', 'swift', 'swift-account-service'],
        ['svc', 'swift', 'swift-container-service'],
        ['svc', 'swift', 'swift-object-service'],
        ['svc', 'swift', 'swift-proxy-service'],
        ['svc', 'swift', 'swift-rsync-service'],
        ['pod', 'swift', 'swift-account-pod'],
        ['pod', 'swift', 'swift-container-pod'],
        ['pod', 'swift', 'swift-object-pod'],
        ['pod', 'swift', 'swift-proxy-pod'],
        ['svc', 'skydns', 'skydns-service'],
        ['pod', 'skydns', 'skydns-pod'],
        ['svc', 'cinder', 'cinder-api-service'],
        ['pod', 'cinder', 'cinder-api-haproxy-configmap'],
        ['pod', 'cinder', 'cinder-api-pod'],
        ['pod', 'cinder', 'cinder-scheduler-pod'],
        ['pod', 'cinder', 'cinder-backup-pod'],
        ['pod', 'cinder', 'cinder-volume-lvm-pod']
    ],
    'typeInName': [
        ['secret', 'ceph', 'ceph-secret'],
        ['disk', 'mariadb', 'mariadb-disk'],
        ['pv', 'mariadb', 'mariadb-pv'],
        ['pvc', 'mariadb', 'mariadb-pvc'],
        ['svc', 'mariadb', 'mariadb-service'],
        ['bootstrap', 'mariadb', 'mariadb-bootstrap-job'],
        ['pod', 'mariadb', 'mariadb-pod'],
        ['svc', 'memcached', 'memcached-service'],
        ['pod', 'memcached', 'memcached-pod'],
        ['svc', 'keystone', 'keystone-service-admin'],
        ['svc', 'keystone', 'keystone-service-public'],
        ['bootstrap', 'keystone', 'keystone-bootstrap-job'],
        ['pod', 'keystone', 'keystone-pod'],
        ['svc', 'horizon', 'horizon-service'],
        ['pod', 'horizon', 'horizon-pod'],
        ['disk', 'rabbitmq', 'rabbitmq-disk'],
        ['pv', 'rabbitmq', 'rabbitmq-pv'],
        ['pvc', 'rabbitmq', 'rabbitmq-pvc'],
        ['svc', 'rabbitmq', 'rabbitmq-service-management'],
        ['svc', 'rabbitmq', 'rabbitmq-service'],
        ['bootstrap', 'rabbitmq', 'rabbitmq-bootstrap-job'],
        ['pod', 'rabbitmq', 'rabbitmq-pod'],
        ['disk', 'glance', 'glance-disk'],
        ['pv', 'glance', 'glance-pv'],
        ['pvc', 'glance', 'glance-pvc'],
        ['svc', 'glance', 'glance-api-service'],
        ['svc', 'glance', 'glance-registry-service'],
        ['pod', 'glance', 'glance-api-haproxy-configmap'],
        ['pod', 'glance', 'glance-api-pod'],
        ['pod', 'glance', 'glance-registry-haproxy-configmap'],
        ['pod', 'glance', 'glance-registry-pod'],
        ['svc', 'nova', 'nova-api'],
        ['svc', 'nova', 'nova-metadata'],
        ['bootstrap', 'nova', 'nova-compute-bootstrap-job'],
        ['pod', 'nova', 'nova-compute-pod'],
        ['pod', 'nova', 'nova-api-pod'],
        ['pod', 'nova', 'nova-conductor-pod'],
        ['pod', 'nova', 'nova-scheduler-pod'],
        ['svc', 'neutron', 'neutron-server-service'],
        ['bootstrap', 'neutron', 'neutron-bootstrap-job'],
        ['pod', 'neutron', 'neutron-openvswitch-agent-daemonset'],
        ['pod', 'neutron', 'neutron-control-pod'],
        ['pod', 'neutron', 'neutron-dhcp-agent-pod'],
        ['pod', 'neutron', 'neutron-l3-agent-pod'],
        ['pod', 'neutron', 'neutron-metadata-agent-pod'],
        ['svc', 'swift', 'swift-account-service'],
        ['svc', 'swift', 'swift-container-service'],
        ['svc', 'swift', 'swift-object-service'],
        ['svc', 'swift', 'swift-proxy-service'],
        ['svc', 'swift', 'swift-rsync-service'],
        ['pod', 'swift', 'swift-account-pod'],
        ['pod', 'swift', 'swift-container-pod'],
        ['pod', 'swift', 'swift-object-pod'],
        ['pod', 'swift', 'swift-proxy-pod'],
        ['svc', 'skydns', 'skydns-service'],
        ['pod', 'skydns', 'skydns-pod'],
        ['svc', 'cinder', 'cinder-api-service'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-create-db'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-manage-db'],
        ['bootstrap', 'cinder', 'cinder-bootstrap-job-endpoints'],
        ['pod', 'cinder', 'cinder-api-haproxy-configmap'],
        ['pod', 'cinder', 'cinder-api-pod'],
        ['pod', 'cinder', 'cinder-scheduler-pod'],
        ['pod', 'cinder', 'cinder-backup-pod'],
        ['pod', 'cinder', 'cinder-volume-lvm-pod'],
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

    def test_validate_names(self):
        service_names = {}
        template_names = {}
        for service_name in KKR.getServices():
            service_names[service_name] = True
            service = KKR.getServiceByName(service_name)
            for resource_type in RESOURCE_TYPES:
                tnprt = template_names.get(resource_type)
                if tnprt is None:
                    template_names[resource_type] = tnprt = {}
                templates = service.getResourceTemplatesByType(resource_type)
                for template in templates:
                    template_name = template.getName()
                    args = argobj('create',
                                  resource_type,
                                  service_name,
                                  template_name)
                    for part in template_name.split('-'):
                        if part.lower() in ('petset', 'deployment', 'job',
                                            'replicationcontroller', 'pod',
                                            'daemonset', 'configmap',
                                            'secret',
                                            'ps', 'pv', 'pvc', 'disk',
                                            'ds', 'persistentvolume',
                                            'persistentvolumeclaim') and \
                           unknown_technical_debt(args, 'typeInName'):
                            raise Exception("type in name. [%s]" % part)
                    if service_names.get(template_name, False) and \
                        len(templates) != 1:
                        s = "Resource name %s matches service name and" \
                            " there are more then one resource." \
                            % template_name
                        raise Exception(s)
                    if tnprt.get(template_name, False):
                        s = "Resource name %s matches another template name" \
                            % template_name
                        raise Exception(s)
                    tnprt[template_name] = True

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
                    raise Exception("namespace not found but required.")
                if 'namespace' in y['metadata'] and \
                   y['metadata']['namespace'] != 'not_real_namespace' and \
                   unknown_technical_debt(args, 'namespaceHardCoded'):
                    raise Exception("namespace is hardcoded.")
                if y['metadata']['name'] != args.resource_name and \
                   unknown_technical_debt(args, 'resourceNameObjNameNoMatch'):
                    raise Exception("Object name does not match the" +
                                    " resource_name.")
                if kind in ('PetSet', 'Deployment', 'Job', 'DaemonSet',
                            'ReplicationController', 'Pod'):
                    pod = y
                    if kind != 'Pod':
                        pod = y['spec']['template']
                    if 'nodeSelector' not in pod['spec'] and \
                       unknown_technical_debt(args, 'nodeSelector'):
                        raise Exception("nodeSelector not found but required.")
                    if 'namespace' in pod['metadata'] and kind != 'Pod' and \
                       unknown_technical_debt(args, 'namespaceInTemplate'):
                        raise Exception("namespace found in inner template." +
                                        " Its redundant.")
                    if 'name' in pod['metadata'] and kind != 'Pod' and \
                       unknown_technical_debt(args, 'nameInTemplateMetadata'):
                        raise Exception("name in pod metadata. Its generated" +
                                        " from the main metadata. It can" +
                                        " cause issues.")
                    main_found = False
                    for container in pod['spec']['containers']:
                        if container['name'] == 'main':
                            main_found = True
                    if not main_found and \
                       unknown_technical_debt(args, 'mainContainer'):
                        raise Exception("Pod does not contain a container" +
                                        " named main.")
        on_each_template(func)
        if WARNING['found'] and WERROR:
            raise Exception('Found Warning when Werror set.')
