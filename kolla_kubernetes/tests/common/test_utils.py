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

from kolla_kubernetes.common import utils
from kolla_kubernetes.tests import base


class TestDictUpdate(base.BaseTestCase):

    def test_flat_no_overwrites(self):
        a = {'a': 'foo', 'b': 'no'}
        b = {'c': 'foo', 'd': 'no'}
        expect = {'a': 'foo', 'c': 'foo', 'b': 'no', 'd': 'no'}
        self.assertEqual(expect, utils.dict_update(a, b))

    def test_flat_with_overwrites(self):
        a = {'a': 'foo', 'b': 'no'}
        b = {'c': 'foo', 'b': 'yes'}
        expect = {'a': 'foo', 'c': 'foo', 'b': 'yes'}
        self.assertEqual(expect, utils.dict_update(a, b))

    def test_nested_no_overwrites(self):
        a = {'a': 'foo', 'b': {'bb': 'no'}}
        b = {'c': 'foo'}
        expect = {'a': 'foo', 'c': 'foo', 'b': {'bb': 'no'}}
        self.assertEqual(expect, utils.dict_update(a, b))

    def test_nested_with_overwrites(self):
        a = {'a': 'foo', 'b': {'bb': 'no'}}
        b = {'c': 'foo', 'b': {'bb': 'yes'}}
        expect = {'a': 'foo', 'c': 'foo', 'b': {'bb': 'yes'}}
        self.assertEqual(expect, utils.dict_update(a, b))
