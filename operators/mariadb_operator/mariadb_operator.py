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

"""Mariadb Operator class."""


from service_operator import ServiceOperator


class MariadbOperator(ServiceOperator):

    def __init__(self, data):
        self.data = data
        self.template = self.data.get('template')
        self.dependencies = self.template.get('dependencies')
        self.name = self.template.get('name')

        self.lifecycle_operations = ['deploy, recovery']
        self.operation = self.template.get('operation')
        super(MariadbOperator, self).__init__(data)

    def _mariadb_recovery(self):
        """Workflow for recovering mariadb"""

        print("does nothing")

    def _dependency_chain(self):
        """Determine the dependency chain of a service"""

        print("does nothing")

    def deploy(self):
        self._dependency_chain()
        self._database_action()
        self._keystone_action()
        self._run_helm_package()
