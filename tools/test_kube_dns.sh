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
    metadata:
      labels:
        test: dns
    spec:
      nodeSelector:
          kubernetes.io/hostname: $NODE
      containers:
        - image: "$TOOLBOX"
          name: main
          command: ["sh", "-xc"]
          args:
            - |
                curl -s http://172.16.128.100:6666/version
                cat > /tmp/dns-test.py << "EOEF"
                import socket
                import sys
                try:
                  print "kubernetes:", socket.gethostbyname("kubernetes.default")
                  print "google:", socket.gethostbyname("google.com")
                except:
                  print "Failed to resolve."
                  sys.exit(1)
                EOEF
                while true; do
                    python /tmp/dns-test.py && echo Resolved && exit;
                    sleep 1;
                done
      restartPolicy: OnFailure
EOF
)
done

$DIR/wait_for_pods.sh default

sudo ifconfig

kubectl get pods -l test=dns -o json | jq -r '.items[].metadata.name' | while read pod; do
    echo Pod: $pod
    kubectl logs $pod
done

kubectl get nodes -o json | jq -r '.items[].metadata.name' | while read NODE; do
    RELEASE="test-dns-$NODE"
    kubectl delete job $RELEASE
done

