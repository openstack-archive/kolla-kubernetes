#!/bin/bash -xe

PACKAGE_VERSION=0.6.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$7"
PIPELINE="$8"

if [ "x$4" == "xceph-reboot" ]; then
    exec tests/bin/gate_reboot_master.sh `pwd` "$WORKSPACE/logs" "$BRANCH"
fi

trap 'tests/bin/gate_capture_logs.sh "$?";' ERR

function cleanup {
    jobs -p | xargs -n 1 pstree -p
    j=$(jobs -p)
    if [ "x$j" != "x" ]; then
        kill $j
    fi
}
trap cleanup EXIT

mkdir -p $WORKSPACE/logs/
env > $WORKSPACE/logs/env

if [ "x$PIPELINE" == "xperiodic" ]; then
    mkdir -p $WORKSPACE/UPLOAD_CONTAINERS
fi

if [ "x$BRANCH" == "xt" ]; then
    echo Version: $BRANCH is not implemented yet.
    exit -1
fi

if [ "x$BRANCH" == "x3" ]; then
    sed -i 's/2\.0\.2/3.0.2/g' helm/all_values.yaml
    sed -i 's/2\.0\.2/3.0.2/g' tests/conf/ceph-all-in-one/kolla_config
fi

if [ "x$4" == "xiscsi" ]; then
    tools/setup_gate_iscsi.sh $1 $2 $3 $4 $5 $BRANCH $PIPELINE
    exit 0
fi

if [ "x$4" == "xhelm-operator" ]; then
    echo "helm operator job is not yet implemented..."
    exit -1
fi

if [ "x$4" == "xhelm-compute-kit" ]; then
    tools/setup_gate_iscsi.sh $1 $2 $3 $4 $5 $BRANCH $PIPELINE
    exit 0
fi

#
# Starting default config CEPH
#

echo "1 "$1 "2 "$2 "3 "$3 "4 "$4 "5 "$5 "BRANCH "$BRANCH "PIPELINE "$PIPELINE
tools/setup_gate_ceph.sh $1 $2 $3 $4 $5 $BRANCH $PIPELINE
exit 0
