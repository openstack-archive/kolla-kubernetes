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

from cliff import command
from oslo_config import cfg
from oslo_log import log

from kolla_kubernetes import service

CONF = cfg.CONF
LOG = log.getLogger(__name__)


class _ServiceCommand(command.Command):

    _action = None  # must be set in derived classes

    def get_parser(self, prog_name):
        parser = super(_ServiceCommand, self).get_parser(prog_name)
        parser.add_argument('service')
        return parser

    def take_action(self, parsed_args):
        assert self._action is not None, (
            "code error: derived classes must set _action")
        service.execute_action(parsed_args.service, self._action)


class Bootstrap(_ServiceCommand):
    """Roll out configurations and bootstrap a service."""
    _action = 'bootstrap'


class Run(_ServiceCommand):
    """Run a service."""
    _action = 'run'


class Kill(_ServiceCommand):
    """Kill a service."""
    _action = 'kill'
