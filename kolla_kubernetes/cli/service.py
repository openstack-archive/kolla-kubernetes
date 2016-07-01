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

import os

from cliff import command
from oslo_config import cfg
from oslo_log import log

from kolla_kubernetes.common.utils import FileUtils
from kolla_kubernetes.common.utils import JinjaUtils
from kolla_kubernetes.common.utils import YamlUtils
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


class JinjaTemplate(command.Command):
    """Jinja process a service template file to stdout"""

    def get_parser(self, prog_name):
        parser = super(JinjaTemplate, self).get_parser(prog_name)
        parser.add_argument(
            "file_path",
            metavar="<file_path>",
            help=("Full file path to the jinja template file")
        )
        return parser

    def take_action(self, args):
        proj_name = os.path.abspath(args.file_path).split('/')[-2]
        variables = service._load_variables_from_file(proj_name)

        # process the template
        print(JinjaUtils.render_jinja(
            variables,
            FileUtils.read_string_from_file(args.file_path)))


class JinjaVars(command.Command):
    """Print jinja dict to stdout"""

    def get_parser(self, prog_name):
        parser = super(JinjaVars, self).get_parser(prog_name)
        parser.add_argument(
            "service_name",
            metavar="<service_name>",
            help=("Kolla-kubernetes service_name (e.g. mariadb)"
                  "  for which to generate the jinja dict")
        )
        parser.add_argument(
            '--debug-key-re',
            metavar='<debug_key_re>',
            type=str,
            default=None,
            help=("If this regex string is set, jinja dict creation, which"
                  "  merges configuration files from several sources before"
                  "  applying the dict to itself, will print keys that match"
                  "  the regex as it encounters keys within each"
                  "  configuration file"),
        )
        return parser

    def take_action(self, args):
        variables = service._load_variables_from_file(
            args.service_name, args.debug_key_re)
        print(YamlUtils.yaml_dict_to_string(variables))
