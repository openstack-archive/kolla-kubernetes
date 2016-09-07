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
                func(argobj, o)


class TestTemplatesTest(base.BaseTestCase):

    def test_validate_names(self):
        service_names = {}
        template_names = {}
        for service_name in KKR.getServices():
            service_names[service_name] = True
            service = KKR.getServiceByName(service_name)
            for resource_type in RESOURCE_TYPES:
                tnprt = template_names.get(resource_type)
                if tnprt == None:
                    template_names[resource_type] = tnprt = {}
                templates = service.getResourceTemplatesByType(resource_type)
                for template in templates:
                    template_name = template.getName()
                    if service_names.get(template_name, False) and \
                        len(templates) != 1:
                        s = "Resource name %s matches service name and" \
                            " there are more then one resource." \
                              %template_name
                        raise Exception(s)
                    if tnprt.get(template_name, False):
                        s = "Resource name %s matches another template name" \
                            %template_name
                        raise Exception(s)
                    tnprt[template_name] = True

    def test_validate_templates(self):
        def func(argobj, o):
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
        on_each_template(func)
