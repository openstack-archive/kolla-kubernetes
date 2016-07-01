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
import os
import time

from kolla_kubernetes.common.utils import FileUtils
from kolla_kubernetes.common.utils import JinjaUtils
from kolla_kubernetes.common.utils import YamlUtils
from kolla_kubernetes.tests import base


test_yaml = '''
    openstack_auth:
      auth_url: "http://10.10.10.254:35357"
      password: "aILs81T3MFt8jkboBnhYZoSKLGve0XOMmLiQeagX"
      project_name: "admin"
      username: "admin"
    openstack_logging_debug: "False"
    openstack_region_name: "RegionOne"
    openstack_release: "3.0.0"
'''

test_conf1 = '''
    "n1":
      "nn1": "n1_nn1_v"
      "nn2": "{{ n3.nn1 }}"
    "n2": "{{ n1.nn1 }}"
    "n3":
      "nn1": "a {{- n6 }}"
    "n4": "n4_v"
'''

test_conf2 = '''
    "n3":
      "nn1": "n3_nn1_v"
      "nn2": "n3_nn2_v"
    "n4": "n4_v"
    "n5":
      "nn1": "n5_nn1_v"
    "n6": "n6_v"
'''

test_conf12_merged = '''
    "n1":
      "nn1": "n1_nn1_v"
      "nn2": "{{ n3.nn1 }}"
    "n2": "{{ n1.nn1 }}"
    "n3":
      "nn1": "n3_nn1_v"
      "nn2": "n3_nn2_v"
    "n4": "n4_v"
    "n5":
      "nn1": "n5_nn1_v"
    "n6": "n6_v"
'''

test_conf12_merged_rendered = '''
    "n1":
      "nn1": "n1_nn1_v"
      "nn2": "n3_nn1_v"
    "n2": "n1_nn1_v"
    "n3":
      "nn1": "n3_nn1_v"
      "nn2": "n3_nn2_v"
    "n4": "n4_v"
    "n5":
      "nn1": "n5_nn1_v"
    "n6": "n6_v"
'''


class UtilsTestCase(base.BaseTestCase):
    _test_dir = None

    @staticmethod
    def get_test_dir():
        if UtilsTestCase._test_dir is None:
            UtilsTestCase._test_dir = UtilsTestCase._create_test_dir()
        return UtilsTestCase._test_dir

    @staticmethod
    def _create_test_dir():
        test_dir = os.path.join(
            "/tmp",
            'kolla-kubernetes-tests_' +
            datetime.datetime.fromtimestamp(
                time.time()).strftime('%Y%m%d%H%M%S'))
        os.makedirs(test_dir)
        return test_dir


class TestFileUtils(UtilsTestCase):

    def test_write_and_read_file(self):
        write_content = "Hello\nWorld\n"
        filename = os.path.join(UtilsTestCase.get_test_dir(),
                                self.__class__.__name__ +
                                "test_write_and_read.txt")
        FileUtils.write_string_to_file(write_content, filename)
        read_content = FileUtils.read_string_from_file(filename)
        self.assertEqual(write_content, read_content)


class TestJinjaUtils(UtilsTestCase):

    def test_merge_configs_and_self_render(self):
        file1 = os.path.join(UtilsTestCase.get_test_dir(),
                             self.__class__.__name__ +
                             "_file1_test_write_and_read.txt")
        file2 = os.path.join(UtilsTestCase.get_test_dir(),
                             self.__class__.__name__ +
                             "_file2_test_write_and_read.txt")
        FileUtils.write_string_to_file(test_conf1, file1)
        FileUtils.write_string_to_file(test_conf2, file2)

        d = JinjaUtils.merge_configs_to_dict([file1, file2])
        d2 = YamlUtils.yaml_dict_from_string(test_conf12_merged)
        self.assertEqual(YamlUtils.yaml_dict_to_string(d),
                         YamlUtils.yaml_dict_to_string(d2))

        d3 = JinjaUtils.dict_self_render(d2)
        d4 = YamlUtils.yaml_dict_from_string(test_conf12_merged_rendered)
        self.assertEqual(YamlUtils.yaml_dict_to_string(d3),
                         YamlUtils.yaml_dict_to_string(d4))


class TestYamlUtils(UtilsTestCase):

    def test_write_and_read_string(self):
        dict1 = YamlUtils.yaml_dict_from_string(test_yaml)
        str1 = YamlUtils.yaml_dict_to_string(dict1)
        dict2 = YamlUtils.yaml_dict_from_string(str1)
        str2 = YamlUtils.yaml_dict_to_string(dict2)
        self.assertEqual(str1, str2)

    def test_write_and_read_file(self):
        filename = os.path.join(
            UtilsTestCase.get_test_dir(),
            "test_yaml_write_and_read_file.txt")
        dict1 = YamlUtils.yaml_dict_from_string(test_yaml)
        YamlUtils.yaml_dict_to_file(dict1, filename)
        dict2 = YamlUtils.yaml_dict_from_file(filename)
        str1 = YamlUtils.yaml_dict_to_string(dict1)
        str2 = YamlUtils.yaml_dict_to_string(dict2)
        self.assertEqual(str1, str2)
