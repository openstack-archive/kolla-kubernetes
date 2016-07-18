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

from kolla_kubernetes.pathfinder import PathFinder
from kolla_kubernetes.tests import base


class FindBaseDirTest(base.BaseTestCase):

    def test_find_installed_root(self):
        d = PathFinder.find_installed_root()

        # check for non-null
        self.assertIsNotNone(d)

        # check that project_root is not empty
        self.assertTrue(len(d) > 0)

    def test_find_development_root(self):
        d = PathFinder.find_development_root()

        # check for non-null
        self.assertIsNotNone(d)

        # check that project_root is not empty
        self.assertTrue(len(d) > 0)
