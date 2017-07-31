#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"


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
        - image: "centos:7"
          name: main
          command: ["sh", "-xc"]
          args:
            - |
                cat /etc/resolv.conf
                ping -c 20 8.8.8.8
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

