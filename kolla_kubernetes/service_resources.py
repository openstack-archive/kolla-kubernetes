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

from kolla_kubernetes.common.utils import StringUtils
from kolla_kubernetes.common.utils import YamlUtils


class KollaKubernetesResources(object):

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
