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

from __future__ import print_function

from oslo_log import log

from kolla_kubernetes.commands.base_command import KollaKubernetesBaseCommand
from kolla_kubernetes.service_resources import KollaKubernetesResources
from kolla_kubernetes.service_resources import Service

LOG = log.getLogger(__name__)

KKR = KollaKubernetesResources.Get()


class _ServiceCommand(KollaKubernetesBaseCommand):

    _action = None  # must be set in derived classes

    def get_parser(self, prog_name):
        parser = super(_ServiceCommand, self).get_parser(prog_name)
        parser.add_argument(
            "service_name",
            metavar="<service-name>",
            help=("One of [%s]" % ("|".join(KKR.getServices().keys())))
        )
        return parser

    def take_action(self, args):
        assert self._action is not None, (
            "code error: derived classes must set _action")

        if args.service_name not in KKR.getServices().keys():
            msg = ("service_name [{}] not in valid service_names [{}]".format(
                args.service_name,
                "|".join(KKR.getServices().keys())))
            raise Exception(msg)

        service = KKR.getServiceByName(args.service_name)
        if (self._action == 'bootstrap'):
            service.do_apply('create', Service.LEGACY_BOOTSTRAP_RESOURCES)
        elif (self._action == 'run'):
            service.do_apply('create', Service.LEGACY_RUN_RESOURCES)
        elif (self._action == 'kill'):
            service.do_apply('delete', Service.VALID_RESOURCE_TYPES)
        else:
            raise Exception("Code Error")


class Bootstrap(_ServiceCommand):
    """Roll out configurations and bootstrap a service."""
    _action = 'bootstrap'


class Run(_ServiceCommand):
    """Run a service."""
    _action = 'run'


class Kill(_ServiceCommand):
    """Kill a service."""
    _action = 'kill'
