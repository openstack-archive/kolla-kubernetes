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

import os
import yaml
from kolla_kubernetes.common import jinja_utils

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


class Template(command.Command):
    """Template process a service template file to stdout"""

    def get_parser(self, prog_name):
        parser = super(Template, self).get_parser(prog_name)
        parser.add_argument('template')
        return parser

    def take_action(self, parsed_args):
        proj_name = parsed_args.template.split('/')[-2]
        variables = service._load_variables_from_file(proj_name)

        # Use std jinja2 lib since the one in this program
        #   does not handle multiple documents in single stream.  We need to fix that.
        from jinja2 import Template

        # process the template
        t = Template(Utils.read_string_from_file(parsed_args.template))
        print(t.render(variables))

class CreateConfigMaps(command.Command):
    """CreateConfigMaps"""

    def get_parser(self, prog_name):
        parser = super(CreateConfigMaps, self).get_parser(prog_name)
        parser.add_argument('service')
        return parser

    def take_action(self, parsed_args):
        from kolla_kubernetes import service_definition
        from kolla_kubernetes.common.pathfinder import PathFinder


        pod_list = service_definition.get_pod_definition(parsed_args.service)
        for pod in pod_list:
            container_list = service_definition.get_container_definition(pod)
            for container in container_list:
                cmd = ["kubectl", "create",
                       "configmap", '%s-configmap' % container]
                for f in PathFinder.find_kolla_service_config_files(container):
                    cmd = cmd + ['--from-file=%s=%s' % (
                        os.path.basename(f).replace("_", "-"), f)]
                LOG.info('Command : %r' % cmd)
                print Utils.exec_command(" ".join(cmd))


import subprocess
class Utils(object):
    @staticmethod
    def write_string_to_file(s, file):
        with open (file, "w") as f:
            f.write(s)
            f.close()

    @staticmethod
    def read_string_from_file(file):
        data = ""
        with open (file, "r") as f:
            data=f.read()
            f.close()
        return data

    @staticmethod
    def yaml_dict_write_to_file(dict, file):
        s = yaml.safe_dump(dict, default_flow_style=False)
        return Utils.write_string_to_file(s, file)

    @staticmethod
    def yaml_dict_read_from_file(file):
        s = Utils.read_string_from_file(file)
        d = yaml.load(s)
        return d

    @staticmethod
    def exec_command(cmd):
        try:
            #print("executing cmd[{}]".format(cmd))
            res = subprocess.check_output(cmd, shell=True, executable='/bin/bash')

            try: # pretty print json if the output happens to be
                res = json.dumps(json.loads(res), indent=2, sort_keys=True)
            except Exception as e:
                pass

            #print("executing cmd[{}] returned[{}]".format(cmd, res))
            return (res, None)
        except Exception as e:
            return ('<Error>', str(e))
