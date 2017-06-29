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
from kubernetes import client
from kubernetes import config
import sys
import time


def usage():
    print("wait_for_pods.py requires three arguments.  a namespace name \
           a list of comma separated pod prefixes to monitor and a \
           comma separated list of valid end states to wait for \
           (such as completed and running)")
    return

if len(sys.argv) != 4:
    usage()
    exit(1)

namespace = sys.argv[1]
prefix_list = sys.argv[2].lower().split(',')
end_status_list = sys.argv[3].lower().split(',')

try:
    config.load_incluster_config()
except:
    config.load_kube_config()

v1 = client.CoreV1Api()

done = False
while not done:
    matches = 0
    finished = 0
    # sleep at the start to give pods time to exist before polling
    time.sleep(5)
    kolla_pods = v1.list_namespaced_pod(namespace)
    for pod in kolla_pods.items:
        pod_name = pod.metadata.name.lower()
        pod_status = pod.status.phase.lower()
        for prefix in prefix_list:
            if pod_name.startswith(prefix):
                matches += 1
                if pod_status in end_status_list:
                    finished += 1

    if matches == finished:
        done = True
    else:
        print('Waiting for pods to be ready. Total: ' + str(matches) +
              ' Ready:' + str(finished))
