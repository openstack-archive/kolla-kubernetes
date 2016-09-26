#!/usr/bin/env python
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

import copy
import json


def process(json_file, key):
    try:
        j = json.load(open(json_file))
        a = []
        for v in j['config_files']:
            if v['source'] == '/var/lib/kolla/config_files/ceph.*':
                i = copy.deepcopy(v)
                f = "/var/lib/kolla/config_files/ceph.client.%s.keyring" % key
                i['source'] = f
                i['dest'] = "/etc/ceph/ceph.client.%s.keyring" % key
                a.append(i)
                i = copy.deepcopy(v)
                i['source'] = '/var/lib/kolla/config_files/ceph.conf'
                i['dest'] = '/etc/ceph/ceph.conf'
                a.append(i)
            else:
                a.append(v)
        if len(a) != len(j['config_files']):
            j['config_files'] = a
            f = open(json_file, 'w')
            f.write(json.dumps(j, indent=4))
            f.close()
    except Exception:
        pass

process('/etc/kolla/glance-api/config.json', 'glance')
process('/etc/kolla/cinder-volume/config.json', 'cinder')
process('/etc/kolla/nova-compute/config.json', 'nova')
