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


def env(*args, **kwargs):
    for arg in args:
        value = os.environ.get(arg)
        if value:
            return value
    return kwargs.get('default', '')


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
