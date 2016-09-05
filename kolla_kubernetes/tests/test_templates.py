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

import yaml
import json

from kolla_kubernetes.service_resources import KollaKubernetesResources
from kolla_kubernetes.commands.cmd_resource import ResourceTemplate
from kolla_kubernetes.tests import base
KKR = KollaKubernetesResources.Get();

RESOURCE_TYPES = ('secret pv pvc svc bootstrap pod').split(" ")

class argobj:
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
             args = argobj('create', resource_type, service_name, template_name)
             print "Processing:", resource_type, service_name, template_name
             o = ResourceTemplate('kolla-kubernetes.py', '', 'resource-template').take_action(args=args, skip_and_return=True)
             func(argobj, o)

class TestTemplatesTest(base.BaseTestCase):

    def test_validate_templates(self):
      def func(argobj, o):
        #Check if template is yaml
        y = yaml.load(o)
        js = '[]'
        try:
          #If there is an alpha init container, validate it is proper json
          js = y['spec']['template']['metadata']['annotations']['pod.alpha.kubernetes.io/init-containers']
        except:
          pass
        json.loads(js)
      on_each_template(func)
