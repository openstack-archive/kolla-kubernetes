#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../helm" && pwd )"

repo="$1"

if [ "x$repo" == "x" ]; then
    echo You must specify the repo directory to build in.
    exit -1
fi

if [ ! -d "$repo" ]; then
    echo The specified build dir does not exist.
    exit -1
fi

mkdir /tmp/.kolla$$

packages=openstack-neutron

TMPDIR=/tmp/.kollahelmbuild$$

pushd $repo 2> /dev/null

helm package $DIR/openstack-kolla-common

for package in $packages; do 
mkdir -p $TMPDIR/$package/charts
cp -a $DIR/$package/* $TMPDIR/$package
cp -a openstack-kolla-common*.tgz $TMPDIR/$package/charts
helm package $TMPDIR/$package
done

popd 2> /dev/null

rm -rf /tmp/.kollahelmbuild$$
