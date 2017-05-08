LOGS="$1"
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$5"
PIPELINE="$6"

#FIXME move this to periodic only once done testing.
if [ "x$DISTRO" == "xcentos" ]; then
    yum install -y createrepo
    mkdir -p $WORKSPACE/UPLOAD_REPOS/kubernetes
    sudo cp -a /var/cache/yum/kubernetes/packages/*.rpm $WORKSPACE/UPLOAD_REPOS/kubernetes
    sudo chown $USER $WORKSPACE/UPLOAD_REPOS/kubernetes
    chmod 644 $WORKSPACE/UPLOAD_REPOS/kubernetes/
    createrepo $WORKSPACE/UPLOAD_REPOS/kubernetes
    tar -C $WORKSPACE/UPLOAD_REPOS/ -bcvf ../kubernetes.tar.bz2 kubernetes
    mv ../kubernetes.tar.bz2 $WORKSPACE/UPLOAD_REPOS/
    rm -rf WORKSPACE/UPLOAD_REPOS/kubernetes
    ls -l $WORKSPACE/UPLOAD_REPOS/
fi

if [ "x$PIPELINE" == "xperiodic" -a "x$DISTRO" == "xcentos" ]; then
    echo
fi
