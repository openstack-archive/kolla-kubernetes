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

import datetime
import functools
import os.path
import subprocess
import tempfile
import time

from oslo_config import cfg
from oslo_log import log as logging
import yaml

from kolla_kubernetes.common import file_utils
from kolla_kubernetes.common import jinja_utils
from kolla_kubernetes import service_definition

LOG = logging.getLogger()
CONF = cfg.CONF
CONF.import_group('kolla', 'kolla_kubernetes.config')
CONF.import_group('kolla_kubernetes', 'kolla_kubernetes.config')


def execute_if_enabled(f):
    """Decorator for executing methods only if runner is enabled."""

    @functools.wraps(f)
    def wrapper(self, *args, **kwargs):
        if not self._enabled:
            return
        return f(self, *args, **kwargs)

    return wrapper


class File(object):
    def __init__(self, conf, name, service_name):
        self._conf = conf
        self._name = name
        self._service_name = service_name


class Command(object):
    def __init__(self, conf, name, service_name):
        self._conf = conf
        self._name = name
        self._service_name = service_name


class JvarsDict(dict):
    """Dict which can contain the 'global_vars' which are always preserved.

    They cannot be be overriden by any update nor single item setting.
    """

    def __init__(self, *args, **kwargs):
        super(JvarsDict, self).__init__(*args, **kwargs)
        self.global_vars = {}

    def __setitem__(self, key, value, force=False):
        if not force and key in self.global_vars:
            return
        return super(JvarsDict, self).__setitem__(key, value)

    def set_force(self, key, value):
        """Sets the variable even if it will override a global variable."""
        return self.__setitem__(key, value, force=True)

    def update(self, other_dict, force=False):
        if not force:
            other_dict = {key: value for key, value in other_dict.items()
                          if key not in self.global_vars}
        super(JvarsDict, self).update(other_dict)

    def set_global_vars(self, global_vars):
        self.update(global_vars)
        self.global_vars = global_vars


def _load_variables_from_file(service_dir, project_name):
    jvars = JvarsDict()
    f = file_utils.find_config_file('globals.yml')
    if os.path.exists(f):
        with open(f, 'r') as gf:
            jvars.set_global_vars(yaml.load(gf))
    f = file_utils.find_config_file('passwords.yml')
    if os.path.exists(f):
        with open(f, 'r') as gf:
            jvars.update(yaml.load(gf))
    # Apply the basic variables that aren't defined in any config file.
    jvars.update({
        'deployment_id': CONF.kolla.deployment_id,
        'node_config_directory': '',
        'timestamp': str(time.time())
    })

    dir = file_utils.get_shared_directory()
    if dir and os.path.exists(os.path.join(dir, 'ansible/group_vars/all.yml')):
        all_yml_name = os.path.join(dir, 'ansible/group_vars/all.yml')
        jinja_utils.yaml_jinja_render(all_yml_name, jvars)

    proj_yml_name = os.path.join(dir, 'ansible/roles',
                                 project_name, 'defaults', 'main.yml')
    if dir and os.path.exists(proj_yml_name):
        jinja_utils.yaml_jinja_render(proj_yml_name, jvars)
    else:
        LOG.warning('Path missing %s' % proj_yml_name)
    return jvars


def _build_runner(service_name, service_dir, variables=None):
    ts = time.time()
    ts = datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d_%H-%M-%S_')
    temp_dir = tempfile.mkdtemp(prefix='kolla-' + ts)
    working_dir = os.path.join(temp_dir, 'kubernetes')
    os.makedirs(working_dir)

    for filename in service_definition.find_service_files(service_name,
                                                          service_dir):
        proj_filename = filename.split('/')[-1].replace('.j2', '')
        proj_name = filename.split('/')[-2]
        LOG.debug(
            'proj_filename : %s proj_name: %s' % (proj_filename, proj_name))

        # is this a snapshot or from original src?
        variables = _load_variables_from_file(service_dir, proj_name)

        # 1. validate the definition with the given variables
        service_definition.validate(service_name, service_dir, variables)

        content = yaml.load(
            jinja_utils.jinja_render(filename, variables))
        with open(os.path.join(working_dir, proj_filename), 'w') as f:
            LOG.debug('_build_runner : service file : %s' %
                      os.path.join(working_dir, proj_filename))
            f.write(yaml.dump(content, default_flow_style=False))

    return working_dir


def run_service(service_name, service_dir, variables=None):
    directory = _build_runner(service_name, service_dir, variables=variables)
    _deploy_instance(directory, service_name)


def kill_service(service_name, service_dir, variables=None):
    directory = _build_runner(service_name, service_dir, variables=variables)
    _delete_instance(directory, service_name)


def _deploy_instance(directory, service_name):
    server = "--server=" + CONF.kolla_kubernetes.host

    cmd = [CONF.kolla_kubernetes.kubectl_path, server, "create", "configmap",
           '%s-configmap' % service_name]
    cmd = cmd + ['--from-file=%s' % f
                 for f in file_utils.get_service_config_files(service_name)]
    LOG.info('Command : %r' % cmd)
    subprocess.call(cmd)
    cmd = [CONF.kolla_kubernetes.kubectl_path, server, "create", "-f",
           directory]
    LOG.info('Command : %r' % cmd)
    subprocess.call(cmd)


def _delete_instance(directory, service_name):
    server = "--server=" + CONF.kolla_kubernetes.host
    cmd = [CONF.kolla_kubernetes.kubectl_path, server, "delete", "configmap",
           '%s-configmap' % service_name]
    LOG.info('Command : %r' % cmd)
    subprocess.call(cmd)
    cmd = [CONF.kolla_kubernetes.kubectl_path, server, "delete", "-f",
           directory]
    LOG.info('Command : %r' % cmd)
    subprocess.call(cmd)
