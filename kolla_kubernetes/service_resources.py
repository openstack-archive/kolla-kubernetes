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

import collections
import os
import sys
import time

from oslo_config import cfg
from oslo_log import log as logging

from kolla_kubernetes.kube_service_status import KubeResourceTypeStatus
from kolla_kubernetes.pathfinder import PathFinder
from kolla_kubernetes.utils import ExecUtils
from kolla_kubernetes.utils import JinjaUtils
from kolla_kubernetes.utils import StringUtils
from kolla_kubernetes.utils import YamlUtils

CONF = cfg.CONF
LOG = logging.getLogger()


class KollaKubernetesResources(object):
    _singleton = None

    _jinja_dict_cache = {}

    @staticmethod
    def Get():
        if KollaKubernetesResources._singleton is None:
            KollaKubernetesResources._singleton = KollaKubernetesResources(
                PathFinder.find_config_file('service_resources.yml'))
        return KollaKubernetesResources._singleton

    @staticmethod
    def GetJinjaDict(service_name=None, cli_args={}, debug_regex=None):
        # check the cache first
        cache_key = ((service_name if service_name is not None else "None") +
                     str(cli_args) +
                     (debug_regex if debug_regex is not None else "None"))
        if cache_key in KollaKubernetesResources._jinja_dict_cache:
            return KollaKubernetesResources._jinja_dict_cache[cache_key]

        # Apply basic variables that aren't defined in any config file
        jvars = {'node_config_directory': '',
                 'timestamp': str(time.time())}

        # Add the cli args to the template vars, to be fed into templates
        jvars["kolla_kubernetes"] = {
            "cli": {"args": YamlUtils.yaml_dict_normalize(cli_args)}}

        # Create the prioritized list of config files that need to be
        # merged.  Search method for config files: locks onto the first
        # path where the file exists.  Search method for template files:
        # locks onto the first path that exists, and then expects the file
        # to be there.
        kolla_dir = PathFinder.find_kolla_dir()
        files = [
            PathFinder.find_config_file('kolla-kubernetes.yml'),
            PathFinder.find_config_file('globals.yml'),
            PathFinder.find_config_file('passwords.yml'),
            os.path.join(kolla_dir, 'ansible/group_vars/all.yml')]
        if service_name is not None:
            service_ansible_file = os.path.join(
                kolla_dir, 'ansible/roles', service_name, 'defaults/main.yml')
            if os.path.exists(service_ansible_file):
                files.append(service_ansible_file)
        files.append(os.path.join(kolla_dir,
                                  'ansible/roles/common/defaults/main.yml'))
        # FIXME probably should move this stuff into
        # ansible/roles/common/defaults/main.yml instead.
        files.append(os.path.join(kolla_dir,
                                  'ansible/roles/haproxy/defaults/main.yml'))

        # FIXME I think we need a way to add aditional roles to services
        # in the service_resources.yaml.
        files.append(os.path.join(kolla_dir,
                                  'ansible/roles/neutron/defaults/main.yml'))

        # Create the config dict
        x = JinjaUtils.merge_configs_to_dict(
            reversed(files), jvars, debug_regex)

        # Render values containing nested jinja variables
        r = JinjaUtils.dict_self_render(x)

        # Add a self referential link so templates can look up things by name.
        r['global'] = r

        # Fix up hostlabels so that they are always strings. Kubernetes
        # expects this.
        for (key, value) in r.items():
            if key.startswith('kolla_kubernetes_hostlabel_'):
                value['value'] = "'%s'" % value['value'].replace("'", "''")

        if os.environ.get('KOLLA_KUBERNETES_TOX', None):
            r['kolla_kubernetes_namespace'] = 'not_real_namespace'

        # Update the cache
        KollaKubernetesResources._jinja_dict_cache[cache_key] = r
        return r

    def __init__(self, filename):
        if not os.path.isfile(filename):
            print("configuration file={} not found".format(filename))
            sys.exit(1)

        self.filename = filename
        self.y = YamlUtils.yaml_dict_from_file(filename)
        self.services = collections.OrderedDict()
        self.rtn2sn = {}
        for service in self.y['kolla-kubernetes']['services']:
            self.services[service['name']] = Service(service)
            # This code creates a record:
            # rtn2sn[resource_type][resource_name] = service_name
            # for all resources
            for (resource_type, value) in service['resources'].items():
                resource_table = self.rtn2sn.get(resource_type)
                if resource_table is None:
                    self.rtn2sn[resource_type] = resource_table = {}
                for resource in value:
                    resource_table[resource['name']] = service['name']

    def getServices(self):
        return self.services

    def getServiceByName(self, name):
        r = self.getServices()
        if name not in r:
            print("unable to find service={}", name)
            sys.exit(1)
        return r[name]

    def getServiceNameByResourceTypeName(self, resource_type, resource_name):
        t = self.rtn2sn.get(resource_type)
        if t is None:
            print("unable to find resource_type={}", resource_type)
            sys.exit(1)
        service_name = t.get(resource_name)
        if service_name is None:
            print("unable to find resource_name={}", resource_name)
            sys.exit(1)
        return service_name

    def __str__(self):
        s = self.__class__.__name__
        for k, v in self.getServices().items():
            s += "\n" + StringUtils.pad_str(" ", 2, str(v))
        return s


class Service(object):
    VALID_ACTIONS = 'create delete status'.split(" ")
    VALID_RESOURCE_TYPES = ('configmap secret '
                            'disk pv pvc svc bootstrap pod').split(" ")
    # Keep old logic for LEGACY support of bootstrap, run, and kill commands
    #   Legacy commands did not keep order.  Here, we define order.
    #   Hoping to get rid of the LEGACY commands entirely if people okay.
    #   Otherwise, we wait until Ansible workflow engine.
    #   SVC should really be in bootstrap command, since it is stateful
    #   CONFIGMAP remains listed twice, since that was the old logic.
    LEGACY_BOOTSTRAP_RESOURCES = ('configmap secret '
                                  'disk pv pvc bootstrap').split(" ")
    LEGACY_RUN_RESOURCES = 'configmap svc pod'.split(" ")

    def __init__(self, y):
        self.y = y
        self.pods = collections.OrderedDict()
        for i in self.y['pods']:
            self.pods[i['name']] = Pod(i)
        self.resourceTemplates = {}
        for rt in self.VALID_RESOURCE_TYPES:
            # Initialize instance resourceTemplates hash
            if rt not in self.resourceTemplates:
                self.resourceTemplates[rt] = []
            # Skip empty definitions
            if rt not in self.y['resources']:
                continue
            # Handle definitions
            for i in self.y['resources'][rt]:
                self.resourceTemplates[rt].append(ResourceTemplate(i, rt))

    def getName(self):
        return self.y['name']

    def getPods(self):
        return self.pods

    def getPodByName(self, name):
        r = self.getPods()
        if name not in r:
            print("unable to find pod={}", name)
            sys.exit(1)
        return r[name]

    def getResourceTemplatesByType(self, resource_type):
        assert resource_type in self.resourceTemplates
        return self.resourceTemplates[resource_type]

    def getResourceTemplateByTypeAndName(
            self, resource_type, resource_name):

        # create an inverted hash[name]=resourceTemplate
        resourceTemplates = self.getResourceTemplatesByType(resource_type)
        h = {i.getName(): i for i in resourceTemplates}

        # validate
        if resource_name not in h.keys():
            print("unable to find resource_name={}", resource_name)
            sys.exit(1)

        return h[resource_name]

    def __str__(self):
        s = self.__class__.__name__ + " " + self.getName()
        for k, v in self.getPods().items():
            s += "\n" + StringUtils.pad_str(" ", 2, str(v))
        return s

    def do_apply(self, action, resource_types, dry_run=False):
        """Apply action to resource_types

        Example: service.apply("create", "disk")
        Example: service.apply("create", ["disk", "pv", "pvc"])
        Example: service.apply("delete", "all")
        Example: service.apply("status", "all")

        ACTION: string value of (create|delete|status)
        RESOURCE_TYPES: string value of one resource type, or list of
          string values of many resource types
          (configmap|disk|pv|pvc|svc|bootstrap|pod).
          In addition 'all' is a valid resource type.
        """

        # Check action input arg for code errors
        assert type(action) is str
        assert action in Service.VALID_ACTIONS

        # Handle resource_types as string or list, and the special case 'all'
        if type(resource_types) is str:
            if resource_types == 'all':
                resource_types = Service.VALID_RESOURCE_TYPES
            else:
                resource_types = [resource_types]

        # Check resource_type input arg for code errors
        assert type(resource_types) is list
        for t in resource_types:
            assert t in Service.VALID_RESOURCE_TYPES

        # If action is delete, then delete the resource types in
        # reverse order.
        if action == 'delete':
            resource_types = reversed(resource_types)

        # Execute the action for each resource_type
        for rt in resource_types:
            # Handle status action
            if action == "status":
                if rt == "disk":
                    raise Exception('resource type for disk not supported yet')
                krs = KubeResourceTypeStatus(self, rt)
                print(YamlUtils.yaml_dict_to_string(krs.asDict()))
                continue

            # Handle create and delete action
            if rt == "configmap":
                # Take care of configmap as a special case
                for pod in self.getPods().values():
                    for container in pod.getContainers().values():
                        if action == 'create':
                            container.createConfigMaps()
                        elif action == 'delete':
                            container.deleteConfigMaps()
                        else:
                            raise Exception('Code Error')
            else:
                # Handle all other resource_types as the same
                self._ensureResource(action, rt)

    def _ensureResource(self, action, resource_type):
        # Check input args
        assert action in Service.VALID_ACTIONS
        assert resource_type in Service.VALID_RESOURCE_TYPES
        assert resource_type in self.resourceTemplates

        resourceTemplates = self.resourceTemplates[resource_type]

        # If action is delete, then delete the resourceTemplates in
        # reverse order.
        if action == 'delete':
            resourceTemplates = reversed(resourceTemplates)

        for resourceTemplate in resourceTemplates:
            # Build the command based on if shell script or not. If
            # shell script, pipe to sh.  Else, pipe to kubectl
            cmd = "kolla-kubernetes resource-template {} {} {}".format(
                action, resource_type,
                resourceTemplate.getName())
            if resourceTemplate.getTemplatePath().endswith('.sh.j2'):
                cmd += " | sh"
            else:
                cmd += " | kubectl {} -f -".format(action)

            # Execute the command
            ExecUtils.exec_command(cmd)


class Pod(object):

    def __init__(self, y):
        self.y = y
        self.containers = collections.OrderedDict()
        for i in self.y['containers']:
            self.containers[i['name']] = Container(i)

    def getName(self):
        return self.y['name']

    def getContainers(self):
        return self.containers

    def getContainerByName(self, name):
        r = self.getContainers()
        if name not in r:
            print("unable to find container={}", name)
            sys.exit(1)
        return r[name]

    def __str__(self):
        s = self.__class__.__name__ + " " + self.getName()
        for k, v in self.getContainers().items():
            s += "\n" + StringUtils.pad_str(" ", 2, str(v))
        return s


class Container(object):

    def __init__(self, y):
        self.y = y

    def getName(self):
        return self.y['name']

    def __str__(self):
        s = self.__class__.__name__
        s += " " + self.getName()
        return s

    def createConfigMaps(self):
        self._ensureConfigMaps('create')

    def deleteConfigMaps(self):
        self._ensureConfigMaps('delete')

    def _ensureConfigMaps(self, action):
        assert action in Service.VALID_ACTIONS

        nsname = 'kolla_kubernetes_namespace'
        cmd = ("kubectl {} configmap {} --namespace={}".format(
            action, self.getName(),
            KollaKubernetesResources.GetJinjaDict()[nsname]))

        # For the create action, add some more arguments
        if action == 'create':
            for f in PathFinder.find_config_files(self.getName()):
                cmd += ' --from-file={}={}'.format(
                    os.path.basename(f).replace("_", "-"), f)

        # Execute the command
        ExecUtils.exec_command(cmd)


class ResourceTemplate(object):

    def __init__(self, y, resource_type):
        # Checks
        if resource_type == 'configmap' and \
           'template' not in y:
            y['template'] = 'auto'
        assert 'template' in y, str(y)  # not optional
        assert 'name' in y, str(y)  # not optional
        # Construct
        self.y = y

    def getName(self):
        return self.y['name']

    def getTemplate(self):
        return self.y['template']

    def getVars(self):
        return (self.y['vars']
                if 'vars' in self.y else None)  # optional

    def getTemplatePath(self):
        kkdir = PathFinder.find_kolla_kubernetes_dir()
        path = os.path.join(kkdir, self.getTemplate())
        assert os.path.exists(path)
        return path

    def __str__(self):
        s = self.__class__.__name__
        s += " name[{}]".format(
            self.getName() if self.getName() is not None else "")
        s += " template[{}]".format(self.getTemplate())
        s += " vars[{}]".format(
            self.getVars() if self.getVars() is not None else "")
        return s
