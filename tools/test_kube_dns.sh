#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

TOOLBOX=$(kolla-kubernetes resource-template create bootstrap neutron-create-db -o json | jq -r '.spec.template.spec.containers[0].image')

kubectl get nodes -o json | jq -r '.items[].metadata.name' | while read NODE; do
    RELEASE="test-dns-$NODE"
    kubectl create -f <(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $RELEASE
spec:
  template:
    spec:
      nodeSelector:
          kubernetes.io/hostname: $NODE
      containers:
        - image: {{ include "kolla_toolbox_image_full" . | quote }}
          name: main
          command: ["sh", "-xec"]
          args:
            - python -c 'import socket; print socket.gethostbyname("google.com")'
      restartPolicy: OnFailure
EOF
)
done

$DIR/tools/wait_for_pods.sh kube-system
 
kubectl get nodes -o json | jq -r '.items[].metadata.name' | while read NODE; do
    RELEASE="test-dns-$NODE"
    kubectl delete job $RELEASE
done

