#!/bin/bash

function is_arch {
    [[ "$(uname -m)" == "$1" ]]
}

if is_arch "x86_64"; then
    ARCH="amd64"
elif is_arch "aarch64"; then
    ARCH="arm64"
elif is_arch "ppc64le"; then
    ARCH="ppc64le"
else
    ARCH=$(uname -m)
    exit "Kolla Kubernetes unsupported architecture $ARCH"
fi
