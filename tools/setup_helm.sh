#!/bin/bash -ex

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

. tools/helm_versions.sh 

curl "$HELM_URL" | sudo tar --strip-components 1 -C /usr/bin linux-amd64/helm -zxf -
sudo curl -o /usr/bin/helm https://raw.githubusercontent.com/jascott1/bins/master/helm/nethost/_dist/linux-amd64/helm-init
sudo chmod +x /usr/bin/helm-init
if [ ! -e ~/.kube/config ]; then
    mkdir -p ~/.kube
    sudo cat /etc/kubernetes/kubelet.conf > ~/.kube/config
fi

helm-init init --host-net

set +e
end=$(date +%s)
end=$((end + 120))
while true; do
    helm ls > /dev/null 2>&1
    [ $? -eq 0 ] && break
    sleep 1
    now=$(date +%s)
    [ $now -gt $end ] && echo Helm failed to init. && \
        exit -1
done
set -e
