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

from kolla_kubernetes.common.pathfinder import PathFinder
from kolla_kubernetes.common.utils import ExecUtils
from kolla_kubernetes.common.utils import JinjaUtils
from kolla_kubernetes.common.utils import StringUtils
from kolla_kubernetes.common.utils import YamlUtils

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
        jvars = {'deployment_id': CONF.kolla.deployment_id,
                 'node_config_directory': '',
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
            files.append(os.path.join(kolla_dir, 'ansible/roles',
                                      service_name, 'defaults/main.yml'))
        files.append(os.path.join(kolla_dir,
                                  'ansible/roles/common/defaults/main.yml'))

        # Create the config dict
        x = JinjaUtils.merge_configs_to_dict(
            reversed(files), jvars, debug_regex)

        # Render values containing nested jinja variables
        r = JinjaUtils.dict_self_render(x)

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
        for i in self.y['kolla-kubernetes']['services']:
            self.services[i['name']] = Service(i)

    def getServices(self):
        return self.services

    def getServiceByName(self, name):
        r = self.getServices()
        if name not in r:
            print("unable to find service={}", name)
            sys.exit(1)
        return r[name]

    def __str__(self):
        s = self.__class__.__name__
        for k, v in self.getServices().items():
            s += "\n" + StringUtils.pad_str(" ", 2, str(v))
        return s


class Service(object):
    VALID_ACTIONS = 'create delete'.split(" ")
    VALID_RESOURCE_TYPES = 'configmap disk pv pvc svc bootstrap pod'.split(" ")

    def __init__(self, y):
        self.y = y
        self.pods = collections.OrderedDict()
        for i in self.y['pods']:
            self.pods[i['name']] = Pod(i)

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

        ACTION: string value of (create|delete)
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

        # Execute the action for each resource_type
        for rt in resource_types:
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

    def getResourceFilesByType(self, type_):
        assert type_ in Service.VALID_RESOURCE_TYPES
        assert 'resources' in self.y

        # Handle where resource files not defined for type.
        #   i.e Not all services may require 'disk' resources
        if type_ not in self.y['resources']:
            return []
        if type(self.y['resources'][type_]) is not list:
            return []

        # Fully resolve each resource file
        ret = []
        kkdir = PathFinder.find_kolla_kubernetes_dir()
        for i in self.y['resources'][type_]:
            file_ = os.path.join(kkdir, i)
            assert os.path.exists(file_)
            ret.append(file_)
        return ret

    def _ensureResource(self, action, resource_type):
        for file_ in self.getResourceFilesByType(resource_type):

            # Build the command based on if shell script or not. If
            # shell script, pipe to sh.  Else, pipe to kubectl
            cmd = "kolla-kubernetes resource-template {} {} {} {}".format(
                action, resource_type, self.getName(), file_)
            if file_.endswith('.sh.j2'):
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

        cmd = ("kubectl {} configmap {}-configmap".format(
            action, self.getName()))

        # For the create action, add some more arguments
        if action == 'create':
            for f in PathFinder.find_config_files(self.getName()):
                cmd += ' --from-file={}={}'.format(
                    os.path.basename(f).replace("_", "-"), f)

        # Execute the command
        ExecUtils.exec_command(cmd)
