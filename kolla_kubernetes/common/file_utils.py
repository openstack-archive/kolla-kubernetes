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

import errno
import logging
import os
import platform
import sys

from oslo_utils import importutils

from kolla_kubernetes import exception


LOG = logging.getLogger(__name__)


def find_os_type():
    return platform.linux_distribution()[0]


def mkdir_p(path):
    try:
        os.makedirs(path)
    except OSError as exc:  # Python >2.5
        if exc.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else:
            raise


def get_services_dir(base_dir):
    if os.path.exists(os.path.join(base_dir, 'services')):
        return os.path.join(base_dir, 'services')
    elif os.path.exists(os.path.join(get_src_dir(), 'services')):
        return os.path.join(get_src_dir(), 'services')
    raise exception.KollaDirNotFoundException(
        'Unable to detect kolla-kubernetes directory'
    )


def get_src_dir():
    kolla_kubernetes = importutils.import_module('kolla_kubernetes')
    mod_path = os.path.abspath(kolla_kubernetes.__file__)
    # remove the file and module to get to the base.
    return os.path.dirname(os.path.dirname(mod_path))


def get_shared_directory():
    if os.path.exists('/usr/local/share/kolla'):
        return '/usr/local/share/kolla'
    elif os.path.exists('/usr/share/kolla'):
        return '/usr/share/kolla'
    return None


def find_base_dir():
    script_path = os.path.dirname(os.path.realpath(sys.argv[0]))
    base_script_path = os.path.basename(script_path)
    if base_script_path == 'kolla-kubernetes':
        return script_path
    if base_script_path == 'kolla_kubernetes':
        return os.path.join(script_path, '..')
    if base_script_path == 'cmd':
        return os.path.join(script_path, '..', '..')
    if base_script_path == 'subunit':
        return get_src_dir()
    if base_script_path == 'bin':
        if os.path.exists('/usr/local/share/kolla'):
            return '/usr/local/share/kolla'
        elif os.path.exists('/usr/share/kolla'):
            return '/usr/share/kolla'
        else:
            return get_src_dir()
    raise exception.KollaDirNotFoundException(
        'Unable to detect kolla-kubernetes directory'
    )


def find_config_file(filename):
    filepath = os.path.join('/etc/kolla-kubernetes', filename)
    if os.access(filepath, os.R_OK):
        config_file = filepath
    else:
        config_file = os.path.join(find_base_dir(),
                                   'etc', filename)
    return config_file


POSSIBLE_PATHS = {'/usr/share/kolla-kubernetes',
                  get_src_dir(),
                  find_base_dir()}


def find_file(filename):
    for path in POSSIBLE_PATHS:
        file_path = os.path.join(path, filename)
        if os.path.exists(file_path):
            return file_path
    raise exception.KollaNotFoundException(filename, entity='file')
