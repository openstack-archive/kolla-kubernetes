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

import os
import re

from kolla_kubernetes.utils import ExecUtils
from kolla_kubernetes.utils import YamlUtils


class KubeResourceTemplate(object):
    """KubeResourceTemplate

       A KubeResourceTemplate is a jinja template, which when processed may
       generate a stream of kube resource definitions.  In most cases, the
       output consists of a single kube resource yaml blob.  Sometimes, the
       template may print nothing or whitespace (NO-OP).  In other cases, the
       template may generate a stream of kube resource yaml blobs separated by
       "^---".  We must handle all of these cases.
    """

    def __init__(self, service_name, resource_type,
                 kube_resource_template_path):
        # Check input args
        assert os.path.exists(kube_resource_template_path)

        # Initialize internal vars
        self.service_name = service_name
        self.resource_type = resource_type
        self.file_ = kube_resource_template_path

        self.errors = []
        self.oks = []
        self.kube_resources = []

        self.doCheck()

    def getFile(self):
        return self.file_

    def getStatus(self):
        if len(self.errors) != 0:
            return 'error'
        for kr in self.kube_resources:
            if kr.getStatus() != 'ok':
                return 'error'
        return 'ok'

    def asDict(self):
        res = {}
        res['status'] = self.getStatus()
        res['errors'] = self.errors
        res['ok'] = self.oks

        res['file'] = self.file_
        res['segments'] = []
        for kr in self.kube_resources:
            res['segments'].append(kr.asDict())
        return res

    def doCheck(self):

        # Build the templating command
        cmd = "kolla-kubernetes resource-template {} {} {} {}".format(
            'create', self.resource_type, self.service_name, self.file_)

        # Execute the command
        template_out, err = ExecUtils.exec_command(cmd)

        # Skip templates which which produce no-ops (100% whitespace)
        #   (e.g. pv templates for AWS should not use persistent
        #   volumes because AWS uses experimental
        #   auto-provisioning)
        if (err is not None):
            self.errors.append(
                'error processing template file: {}'.format(str(err)))
            return
        elif re.match("^\s+$", template_out):
            msg = "template {} produced empty output (NO-OP)".format(
                self.file_)
            self.oks.append(msg)
            return

        # Split the stream of kube resource yaml definitions
        definitions = re.split("^---", template_out, re.MULTILINE)
        for definition in definitions:
            kr = KubeResource(definition)
            self.kube_resources.append(kr)


class KubeResource(object):

    def __init__(self, kube_resource_definition_yaml):
        # Check input args
        assert len(kube_resource_definition_yaml) > 0

        # Initialize internal vars
        self.y = YamlUtils.yaml_dict_from_string(kube_resource_definition_yaml)
        self.definition = kube_resource_definition_yaml

        self.errors = []
        self.oks = []

        self.doDescribeAndCheck()

    def getStatus(self):
        if len(self.errors) == 0:
            return 'ok'
        else:
            return 'error'

    def getKind(self):
        assert 'kind' in self.y
        return self.y['kind']

    def getName(self):
        assert 'metadata' in self.y
        assert 'name' in self.y['metadata']
        return self.y['metadata']['name']

    def asDict(self):
        res = {}
        res['status'] = self.getStatus()
        res['errors'] = self.errors
        res['ok'] = self.oks
        return res

    def doDescribeAndCheck(self):

        cmd = ('echo \'{}\' | kubectl describe -f -'.format(
            self.definition.replace("'","'\\''")))

        out, err = ExecUtils.exec_command(cmd)

        self.describe = out

        if err is not None:
            # If kubectl returns non-zero exit status we may end up here.
            self.errors.append('resource does not exist or input yaml invalid')
            return

        # For all resource types
        name = KubeResource._matchSingleLineField('Name', out)
        if name is None or name != self.getName():
            self.errors.append(
                'No resource with name {} exists'.format(self.getName()))
        else:
            self.oks.append(
                'Verified resource with name {} exists'.format(self.getName()))

        # For PersistentVolumes and PersistentVolumeClaims
        if self.getKind() == 'PersistentVolume' or (
            self.getKind() == 'PersistentVolumeClaim'):

            # Verify that it is bound
            status = KubeResource._matchSingleLineField('Status', out)
            if status is None or status != "Bound":
                self.errors.append("{} not Bound".format(self.getKind()))
            else:
                self.oks.append("{} Bound".format(self.getKind()))

        # For Services
        if self.getKind() == 'Service':
            # Verify the service has an IP
            ip = KubeResource._matchSingleLineField('IP', out)
            if ip is None or len(ip) == 0:
                self.errors.append("{} has no IP".format(self.getKind()))
            else:
                self.oks.append("{} has IP".format(self.getKind()))

        # For ReplicationControllers
        # Replicas:       1 current / 1 desired
        # Pods Status:    1 Running / 0 Waiting / 0 Succeeded / 0 Failed
        if self.getKind() == 'ReplicationController':

            # Verify the rc has the right number of replicas
            replicas = KubeResource._matchSingleLineField('Replicas', out)
            if replicas is None:
                self.errors.append(
                    "{} replicas not found".format(self.getKind()))
            else:
                self.oks.append(
                    "{} replicas found".format(self.getKind()))
                replicas_detail = KubeResource._matchReturnGroups(
                    '^(\d+) current / (\d+) desired', replicas)
                if replicas_detail is not None:
                    current, desired = replicas_detail
                    if current != desired:
                        self.errors.append(
                            "current != desired: {}".format(replicas))
                    else:
                        self.oks.append(
                            "current == desired: {}".format(replicas))

            # Verify the rc has the right number of pod_status
            pod_status = KubeResource._matchSingleLineField('Pods Status', out)
            if pod_status is None:
                self.errors.append(
                    "{} pod_status not found".format(self.getKind()))
            else:
                self.oks.append(
                    "{} pod_status found".format(self.getKind()))
                pod_status_detail = KubeResource._matchReturnGroups(
                    '^(\d+) Running / (\d+) Waiting /'
                    ' (\d+) Succeeded / (\d+) Failed', pod_status)
                if pod_status_detail is not None:
                    running, waiting, succeeded, failed = pod_status_detail
                    if (int(running) == 0 or int(waiting) > 0 or (
                            int(failed) > 0)):
                        self.errors.append(
                            "pod_status has errors {}".format(pod_status))
                    else:
                        self.oks.append(
                            "pod_status has no errors: {}".format(pod_status))

    @staticmethod
    def _matchSingleLineField(field_name, haystack):
        """Returns field name's value"""
        match = re.search('^{}:\s+(?P<MY_VAL>.*)$'.format(field_name),
                          haystack,
                          re.MULTILINE)
        if match is None:
            return None
        else:
            return match.group('MY_VAL').strip()

    @staticmethod
    def _matchReturnGroups(regex, haystack):
        """Returns all groups matching regex"""

        match = re.search(regex,
                          haystack,
                          re.MULTILINE)
        if match is None:
            return None
        else:
            return match.groups()
