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

"""Base class for Kubernetes Operators."""

import subprocess


class Operator(object):

    def __init__(self, data):
        self.data = data
        self.template = self.data.get('template')
        self.services = self.template.get('services')
        self.name = self.template.get('name')

        self.lifecycle_operations = ['deploy']
        self.operation = self.template.get('operation')

        super(Operator, self).__init__()

    def _kube_client(self, *args):
        kubeargs = ''
        if isinstance(args, list):
            for arg in args:
                kubeargs += arg
        else:
            kubeargs = ''.join(args)
            kubeargs = kubeargs.split(' ')
        subprocess.Popen(kubeargs)

    def get_services(self):
        return self.services

    def _user_action(self, *args, **kwargs):
        """Perform a user directed action.

        Gather and Execute how the user wants to run Kubernetes Operators.
        """

        print("does nothing")

    def _spawn_operators(self, service):
        """Spawn a Kubernetes Operator"""

        self._kube_client("kubectl create -f"
                          "/etc/kolla-kubernetes/%s/mariadb-operator.yaml"
                          % service)

    def _workflow(self):
        """Perform an OpenStack Lifecycle operation"""

        if self.operation in self.lifecycle_operations:
            self._user_action()
            for service in self.services:
                self._spawn_operators(service)
        else:
            print("This is not a valid lifecycle operation. "
                  "Pick from the list of valid operations: %s"
                  % self.lifecycle_operations)

    def deploy(self):
        self._workflow()
