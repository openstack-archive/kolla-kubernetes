#!/bin/bash -xe

PACKAGE_VERSION=0.6.0-1
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$7"
PIPELINE="$8"

trap 'tests/bin/gate_capture_logs.sh "$?"' ERR
mkdir -p $WORKSPACE/logs/
env > $WORKSPACE/logs/env

# TODO(sdake): install wget via ansible as per kolla-ansible deliverable
#              gating tools in the future
function install_wget {
    # NOTE(sdake) wget is far more reliable than curl
    if [ "$DISTRO" == "centos" -o "$DISTRO" == "oraclelinux" ]; then
        sudo yum -y install wget
    else
        sudo apt-get -y install wget
   fi
}

function prepare_images {
    if [ "x$PIPELINE" != "xperiodic" ]; then
        C=$CONFIG
        if [ "x$CONFIG" == "xexternal-ovs" -o "x$CONFIG" == "xceph-multi" -o \
            "x$CONFIG" == "xhelm-entrypoint" -o "x$CONFIG" == "xhelm-operator" \
            ]; then
            C="ceph"
        fi
    fi
    mkdir -p $WORKSPACE/DOWNLOAD_CONTAINERS
    BASE_URL=http://tarballs.openstack.org/kolla-kubernetes/gate/containers/

    # TODO(sdake): Cross-repo depends-on is completely broken

    FILENAME="$DISTRO-$TYPE-$BRANCH-$C.tar.bz2"

    # NOTE(sdake): This includes both a set of kubernetes containers
    #              for running kubernetes infrastructure as well as
    #              kolla containers for 2.0.2 and 3.0.2.  master images
    #              are not yet available via this mechanism.

    # NOTE(sdake): Obtain pre-built containers to load into docker
    #              via docker load

    wget -q -c -O \
        "$WORKSPACE/DOWNLOAD_CONTAINERS/$FILENAME" \
        "$BASE_URL/$FILENAME"
    wget -q -c -O \
          "$WORKSPACE/DOWNLOAD_CONTAINERS/kubernetes.tar.gz" \
        "$BASE_URL/containers/kubernetes.tar.gz"

    # NOTE(sdake): Obtain lists of containers
    wget -q -c -O \
        "$WORKSPACE/DOWNLOAD_CONTAINERS/$FILENAME-containers.txt" \
        "$BASE_URL/$FILENAME-containers.txt"
    wget -q -c -O \
        "$WORKSPACE/DOWNLOAD_CONTAINERS/kubernetes-containers.txt" \
        "$BASE_URL/containers/kubernetes-containers.txt"
}

if [ "x$BRANCH" == "xt" ]; then
    echo Version: $BRANCH is not implemented yet.
    exit -1
fi

# NOTE(sdake): This seems disturbing (see note at end of file)
if [ "x$PIPELINE" == "xperiodic" ]; then
    mkdir -p $WORKSPACE/UPLOAD_CONTAINERS
fi

install_wget
prepare_images

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
