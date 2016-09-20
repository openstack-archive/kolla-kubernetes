#!/usr/bin/python
import copy
import json

def process(json_file, key):
    try:
        j = json.load(open(json_file))
        a = []
        for v in j['config_files']:
            if v['source'] == '/var/lib/kolla/config_files/ceph.*':
                i = copy.deepcopy(v)
                i['source'] = "/var/lib/kolla/config_files/ceph.client.%s.keyring" % key
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
    except:
        pass

process('/etc/kolla/glance-api/config.json', 'glance')
process('/etc/kolla/cinder-volume/config.json', 'cinder')
process('/etc/kolla/nova-compute/config.json', 'nova')
