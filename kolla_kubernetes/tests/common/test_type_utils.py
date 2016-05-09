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

from kolla_kubernetes.common import type_utils
from kolla_kubernetes.tests import base


class StrToBoolTest(base.BaseTestCase):

    scenarios = [
        ('none', dict(text=None, expect=False)),
        ('empty', dict(text='', expect=False)),
        ('junk', dict(text='unlikely', expect=False)),
        ('no', dict(text='no', expect=False)),
        ('yes', dict(text='yes', expect=True)),
        ('0', dict(text='0', expect=False)),
        ('1', dict(text='1', expect=False)),
        ('True', dict(text='True', expect=True)),
        ('False', dict(text='False', expect=False)),
        ('true', dict(text='true', expect=True)),
        ('false', dict(text='false', expect=False)),
        ('shouty', dict(text='TRUE', expect=True)),
    ]

    def test_str_to_bool(self):
        self.assertEqual(self.expect, type_utils.str_to_bool(self.text))
