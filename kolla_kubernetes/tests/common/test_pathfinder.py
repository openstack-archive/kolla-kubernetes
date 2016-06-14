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

from kolla_kubernetes.common.pathfinder import PathFinder
from kolla_kubernetes.tests import base

import os


class FindBaseDirTest(base.BaseTestCase):

    def test_find_project_root(self):
        root_dir = PathFinder.find_project_root()

        # check for non-null
        self.assertIsNotNone(root_dir)

        # check that project_root ends with 'kolla-kubernetes'
        self.assertEqual(os.path.basename(root_dir), 'kolla-kubernetes')
