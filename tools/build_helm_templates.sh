#!/bin/bash
mkdir -p /tmp/.helmbuild.$$
cd /tmp/.helmbuild.$$
export GOPATH=`pwd`
export PATH="$PATH:$(pwd)/bin"
mkdir -p $GOPATH/src/github.com/technosophos/
cd $GOPATH/src/github.com/technosophos/
git clone --depth=1 https://github.com/technosophos/helm-template.git
cd helm-template
make install
cd
rm -rf /tmp/.helmbuild.$$
