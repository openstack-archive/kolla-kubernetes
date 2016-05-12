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


import os
import shlex
import sys

from cliff import app
from cliff import commandmanager
from cliff import interactive
from oslo_config import cfg
from oslo_log import log

PROJECT_ROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.realpath(__file__)), '../..'))

if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from kolla_kubernetes.common import utils

PROJECT = 'kolla_kubernetes'
VERSION = '1.0'

CONF = cfg.CONF
CONF.import_group('kolla', 'kolla_kubernetes.config')
CONF.import_group('kolla_kubernetes', 'kolla_kubernetes.config')

log.register_options(CONF)
log.set_defaults(
    default_log_levels='requests.packages.urllib3.connectionpool=WARNING')

cli_opts = [
    cfg.StrOpt('service-dir',
               default=utils.env('K8S_SERVICE_DIR'),
               help='Directory with services, (Env: K8S_SERVICE_DIR)'),
]
CONF.register_cli_opts(cli_opts)


class KollaKubernetesInteractiveApp(interactive.InteractiveApp):
    def do_run(self, arg):
        self.default(arg)

    def do_help(self, arg):
        line_parts = shlex.split(arg)
        try:
            self.command_manager.find_command(line_parts)
            return self.default(self.parsed('help ' + arg))
        except ValueError:
            # There is a builtin cmd2 command
            pass
        return interactive.InteractiveApp.do_help(self, arg)


class KollaKubernetesShell(app.App):
    def __init__(self):
        super(KollaKubernetesShell, self).__init__(
            description='Kolla-kubernetes command-line interface',
            version=VERSION,
            command_manager=commandmanager.CommandManager(
                'kolla_kubernetes.cli'),
            deferred_help=True,
            interactive_app_factory=KollaKubernetesInteractiveApp
        )

    def configure_logging(self):
        return

    def print_help(self):
        outputs = []
        max_len = 0
        self.stdout.write('\nCommands :\n')

        for name, ep in sorted(self.command_manager):
            factory = ep.load()
            cmd = factory(self, None)
            one_liner = cmd.get_description().split('\n')[0]
            outputs.append((name, one_liner))
            max_len = max(len(name), max_len)

        for name, one_liner in outputs:
            self.stdout.write('  %s  %s\n' % (name.ljust(max_len), one_liner))


def _separate_args(argv):
    conf_opts = _config_opts_map()
    config_args = []
    command_args = argv[:]
    while command_args:
        nargs = conf_opts.get(command_args[0])
        if nargs:
            config_args.extend(command_args[:nargs])
            command_args = command_args[nargs:]
        else:
            break
    return config_args, command_args


def _config_opts_map():
    opts = {'--help': 1, '-h': 1, '--config-dir': 2, '--config-file': 2,
            '--version': 1}
    for opt in CONF._all_cli_opts():
        if opt[1]:
            arg = '%s-%s' % (opt[1].name, opt[0].name)
        else:
            arg = opt[0].name

        if isinstance(opt[0], cfg.BoolOpt):
            nargs = 1
            opts['--no%s' % arg] = 1
        else:
            nargs = 2
        opts['--%s' % arg] = nargs

        if opt[0].short:
            opts['-%s' % opt[0].short] = nargs

        for dep_opt in opt[0].deprecated_opts:
            if getattr(dep_opt, 'group'):
                opts['--%s-%s' % (dep_opt.group, dep_opt.name)] = nargs
            else:
                opts['--%s' % dep_opt.name] = nargs

    return opts


def main(argv=sys.argv[1:]):
    config_args, command_args = _separate_args(argv)

    need_help = (['help'] == command_args or '-h' in config_args or
                 '--help' in config_args)
    if need_help:
        CONF([], project=PROJECT, version=VERSION)
        CONF.print_help()
        return KollaKubernetesShell().print_help()

    CONF(config_args, project=PROJECT, version=VERSION)
    log.setup(CONF, PROJECT, VERSION)

    if '-d' in config_args or '--debug' in config_args:
        command_args.insert(0, '--debug')
        CONF.log_opt_values(
            log.getLogger(PROJECT), log.INFO)

    return KollaKubernetesShell().run(command_args)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
