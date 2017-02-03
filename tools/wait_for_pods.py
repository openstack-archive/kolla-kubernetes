import sys
import time
from kubernetes import config, client


def usage():
    print("wait_for_pods.py requires two arguments.  a list of pod prefixes to monitor \
           and a list of valid end states to wait for (such as completed and running)")
    return

if len(sys.argv) != 3:
    usage()
    exit(1)

prefix_list = sys.argv[1].lower().split(',')
end_status_list = sys.argv[2].lower().split(',')

config.load_kube_config()
v1 = client.CoreV1Api()

done = False
while not done:
    matches = 0
    finished = 0
    kolla_pods = v1.list_namespaced_pod('kolla')
    for pod in kolla_pods.items:
        pod_name = pod.metadata.name.lower()
        pod_status = pod.status.phase.lower()
        for prefix in prefix_list:
            if pod_name.startswith(prefix):
                matches += 1
                for end_state in end_status_list:
                    if pod_status == end_state:
                        finished += 1

    if matches == finished:
        done = True
    else:
        print('Waiting for pods to be ready. Total: ' + str(matches) + ' Ready:' + str(finished))
        time.sleep(5)
