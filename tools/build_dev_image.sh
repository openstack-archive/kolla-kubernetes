#!/bin/bash -xe
TMP_BUILD_DIR=/tmp/kolla-kubernetes-build
DEV_BASE=~/devel
BUILD_ARGS="--tag kolla/k8s-devenv:latest"

# Set the below environment variables if you are running behind a proxy
if [ ! "x$http_proxy" == "x" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg http_proxy=$http_proxy"
fi

if [ ! "x$https_proxy" == "x" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg https_proxy=$https_proxy"
fi

# Set the below environment variable if your dev base is not ~/devel
if [ ! "x$dev_path" == "x" ]; then
    DEV_BASE = $dev_path
fi

# delete old build environment if it is still there
cleanup_build_dir () {
    if [ -d ${TMP_BUILD_DIR} ];
    then
        rm -rf ${TMP_BUILD_DIR}
    fi
}

# create build environment and run
do_build () {
    if [ ! -d ${TMP_BUILD_DIR} ];
    then
        mkdir ${TMP_BUILD_DIR}
        mkdir ${TMP_BUILD_DIR}/repos
    fi

    HALCYON_TMP=${TMP_BUILD_DIR}/repos/halcyon-vagrant-kubernetes
    cp ${DEV_BASE}/kolla-kubernetes/tools/Dockerfile ${TMP_BUILD_DIR}
    cp -R ${DEV_BASE}/kolla-kubernetes ${TMP_BUILD_DIR}/repos/
    cp -R ${DEV_BASE}/kolla-ansible ${TMP_BUILD_DIR}/repos/
    cp -R ${DEV_BASE}/halcyon-vagrant-kubernetes ${TMP_BUILD_DIR}/repos/
    pushd ${HALCYON_TMP}
    vagrant ssh-config > ssh-config
    sed -ie "s/\/tmp\/kolla-kubernetes-build\/repos\/halcyon-vagrant-kubernetes/\/opt\/halcyon-vagrant-kubernetes/g"  ssh-config
    cp -R ~/.kube ${TMP_BUILD_DIR}/kube

    cd ${TMP_BUILD_DIR}; docker build ${BUILD_ARGS} .
}

cleanup_build_dir
do_build
