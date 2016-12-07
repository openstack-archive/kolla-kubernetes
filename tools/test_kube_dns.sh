#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

TOOLBOX=$(kolla-kubernetes resource-template create bootstrap neutron-create-db -o json | jq -r '.spec.template.spec.containers[0].image')

kubectl get nodes -o json | jq -r '.items[].metadata.name' | while read NODE; do
    RELEASE="test-dns-$NODE"
    kubectl create -f <(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $RELEASE
  namespace: default
spec:
  template:
    spec:
      nodeSelector:
          kubernetes.io/hostname: $NODE
      containers:
        - image: "$TOOLBOX"
          name: main
          command: ["sh", "-xec"]
          args:
            - python -c 'import socket; print socket.gethostbyname("google.com"), socket.gethostbyname("kubernetes.default")'
      restartPolicy: OnFailure
EOF
)
done

$DIR/wait_for_pods.sh default

kubectl get nodes -o json | jq -r '.items[].metadata.name' | while read NODE; do
    RELEASE="test-dns-$NODE"
    kubectl delete job $RELEASE
done

