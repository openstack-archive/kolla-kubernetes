#!/bin/bash -ex

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/" && pwd )"

REPODIR="$1"

if [ "x$REPODIR" == "x" ]; then
    echo You must specify a repo dir.
    exit 1
fi

mkdir -p "$REPODIR"

$DIR/helm_prebuild_microservices.py
$DIR/helm_build_microservices.py "$REPODIR"

$DIR/helm_prebuild_services.py
$DIR/helm_build_services.py "$REPODIR"

$DIR/helm_prebuild_compute_kits.py
$DIR/helm_build_compute_kits.py "$REPODIR"

helm repo index "$REPODIR"
helm repo update

helm search | grep '^kollabuild/'
