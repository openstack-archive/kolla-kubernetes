#!/usr/bin/env python
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

import logging
import sys

from cliff import app
from cliff import commandmanager
from cliff.help import HelpAction

from kolla_kubernetes.version import version_info

PROJECT = 'kolla_kubernetes'
VERSION = version_info.version_string_with_vcs()

# Silence debug messages from particular modules
logging.getLogger("requests").setLevel(logging.INFO)
logging.getLogger("stevedore.extension").setLevel(logging.INFO)


class KollaKubernetesApp(app.App):
    _singleton = None

    @staticmethod
    def Get():
        if KollaKubernetesApp._singleton is None:
            KollaKubernetesApp._singleton = KollaKubernetesApp()
        return KollaKubernetesApp._singleton

    def __init__(self, ty='kolla_kubernetes.cli'):
        super(KollaKubernetesApp, self).__init__(
            description='Kolla-Kubernetes command-line interface',
            version=VERSION,
            command_manager=commandmanager.CommandManager(ty),
            deferred_help=True)

    def _print_help(self):
        """Generate the help string using cliff.help.HelpAction."""

        action = HelpAction(None, None, default=self)
        action(self.parser, self.options, None, None)

    def initialize_app(self, argv):
        """Overrides: cliff.app.initialize_app

        The cliff.app.run automatically assumes and starts
        interactive mode if launched with no arguments.  Short
        circuit to disable interactive mode, and print help instead.
        """

        if len(argv) == 0:
            self._print_help()

    def build_option_parser(self, description, version):
        """Parse global cli options

        Overrides: cliff.app.build_option_parser

        This class inherits from the cliff.app.App class.  The app.App
        run method will first parse its own options with the parser
        created in this method.  These parsed options end up in its
        own argparse namespace accessible by self.options.  These are
        considered global options.

        The leftover (aka. remainder) command line options that are
        not recognized by this parser are then passed directly to
        subcommand parser located in each subcommand at
        command.Command.get_parser().  That argparse namepace is then
        handed directly to the command.Command.take_action() method of
        each subcommand.  Subcommands may access global options by
        calling KollaKubernetesApp.Get().get_parsed_options().

        """
        parser = super(KollaKubernetesApp, self).build_option_parser(
            description,
            version)

        parser.add_argument(
            '--kube-context',
            metavar='<kube-context>',
            # TODO(when_we_implement_auto_kube_config):
            #  default=KubeUtils.get_current_context(),
            help=('The kubectl context which to use'),
        )
        return parser

    def get_parsed_options(self):
        """Provide a method to allow access to parsed global options"""
        return self.options


class KollaKubeApp(KollaKubernetesApp):

    _singleton = None

    @staticmethod
    def Get():
        if KollaKubeApp._singleton is None:
            KollaKubeApp._singleton = KollaKubeApp()
        return KollaKubeApp._singleton

    def __init__(self, ty='kolla_kube.cli'):
        super(KollaKubeApp, self).__init__(ty)


def main(argv=sys.argv[1:]):
    kks = KollaKubernetesApp().Get()
    return kks.run(argv)


def main_kube(argv=sys.argv[1:]):
    kks = KollaKubeApp().Get()
    return kks.run(argv)

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
