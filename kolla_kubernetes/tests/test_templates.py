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
# FIXME configmap should be here, but requires config to be done in tox.
# as it seems to change home.
RESOURCE_TYPES = ('secret pv pvc svc bootstrap pod').split(" ")

technical_debt = {
    'nodeSelector': [],
    'namespaceNotFound': [],
    'namespaceInTemplate': [],
    'namespaceHardCoded': [],
    'nameInTemplateMetadata': [],
    'mainContainer': [],
    'resourceNameObjNameNoMatch': [],
    'typeInName': []
}


def unknown_technical_debt(args, selector):
    for i in technical_debt[selector]:
        if i[0] == args.resource_type and i[1] == args.service_name and \
           i[2] == args.resource_name[0]:
            return False
    return True


class argobj(object):

    def __init__(self, action, resource_type, service_name, resource_name):
        self.service_name = service_name
        self.resource_type = resource_type
        self.resource_name = [resource_name]
        self.action = action
        self.print_jinja_keys_regex = None
        self.print_jinja_vars = False
        self.debug_container = None


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
                                            'secret', 'configmap'
                                            'ps', 'pv', 'pvc', 'disk',
                                            'ds', 'persistentvolume',
                                            'persistentvolumeclaim') and \
                           unknown_technical_debt(args, 'typeInName'):
                            raise Exception("type in name. [%s]" % part)
                    if service_names.get(template_name, False) and \
                        len(templates) != 1 and resource_type != 'svc':
                        s = "Resource name %s matches service name and" \
                            " there are more then one resource." \
                            % template_name
                        raise Exception(s)
                    if tnprt.get(template_name, False):
                        s = "Resource name %s matches another template name" \
                            % template_name
                        raise Exception(s)
                    tnprt[template_name] = True
                    if not template_name.startswith("%s-" % service_name) and \
                       template_name != service_name:
                        m = "%s doesn't start with %s-" % (template_name,
                                                           service_name)
                        raise Exception(m)

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
                if y['metadata']['name'] != args.resource_name[0] and \
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
                    if 'metadata' in pod and 'namespace' in pod['metadata'] and \
                       kind != 'Pod' and \
                       unknown_technical_debt(args, 'namespaceInTemplate'):
                        raise Exception("namespace found in inner template." +
                                        " Its redundant.")
                    if 'metadata' in pod and 'name' in pod['metadata'] and \
                       kind != 'Pod' and \
                       unknown_technical_debt(args, 'nameInTemplateMetadata'):
                        raise Exception("name in pod metadata. Its generated" +
                                        " from the main metadata. It can" +
                                        " cause issues.")
                    main_found = False
                    for container in pod['spec']['containers']:
                        if container['name'] == 'main':
                            main_found = True
                    container_count = len(pod['spec']['containers'])
                    if ((kind == 'Job' and container_count == 1) or
                        kind != 'Job') and not main_found and \
                       unknown_technical_debt(args, 'mainContainer'):
                        raise Exception("Pod does not contain a container" +
                                        " named main.")
        on_each_template(func)
        if WARNING['found'] and WERROR:
            raise Exception('Found Warning when Werror set.')
