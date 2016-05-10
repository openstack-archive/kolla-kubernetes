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

import collections

from kolla_kubernetes.common import jinja_utils
from kolla_kubernetes.tests import base


class TestJinjaUtils(base.BaseTestCase):

    def test_dict_jinja_render(self):
        raw_dict = collections.OrderedDict([
            ('first_key', '{{ test_var }}_test',),
            ('second_key', '{{ first_key }}_test'),
        ])
        jvars = {'test_var': 'test'}
        jinja_utils.dict_jinja_render(raw_dict, jvars)
        self.assertEqual(jvars['first_key'], 'test_test')
        self.assertEqual(jvars['second_key'], 'test_test_test')
