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
import os

from oslo_utils import importutils

from kolla_kubernetes import exception


LOG = logging.getLogger(__name__)


def find_config_file(filename):
    filepath = os.path.join('/etc/kolla', filename)
    if os.access(filepath, os.R_OK):
        return filepath
    raise exception.KollaDirNotFoundException(
        'Unable to detect kolla-kubernetes directory'
    )


def get_service_config_files(service):
    directory = os.path.join('/etc/kolla/', service)
    for dirpath, _, filenames in os.walk(directory):
        for f in filenames:
            yield os.path.abspath(os.path.join(dirpath, f))


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
    raise exception.KollaDirNotFoundException(
        'Unable to detect kolla-kubernetes directory'
    )


def find_base_dir():
    if os.path.exists('/usr/local/share/kolla'):
        return '/usr/local/share/kolla'
    elif os.path.exists('/usr/share/kolla'):
        return '/usr/share/kolla'
    else:
        return get_src_dir()
