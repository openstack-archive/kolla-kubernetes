LOGS="$1"
DISTRO="$2"
TYPE="$3"
CONFIG="$4"
BRANCH="$5"
PIPELINE="$6"

#FIXME move this to periodic only once done testing.
if [ "x$DISTRO" == "xcentos" ]; then
    sudo yum install -y createrepo
    mkdir -p $WORKSPACE/UPLOAD_REPOS/kubernetes/
    sudo find /var/cache/yum;
    sudo /bin/cp -a '/var/cache/yum/x86_64/7/kubernetes/packages/' $WORKSPACE/UPLOAD_REPOS/kubernetes/
    sudo chown --recursive $USER $WORKSPACE/UPLOAD_REPOS/kubernetes
    sudo chmod --recursive 644 $WORKSPACE/UPLOAD_REPOS/kubernetes/
    createrepo $WORKSPACE/UPLOAD_REPOS/kubernetes
    tar -C $WORKSPACE/UPLOAD_REPOS/ -jcvf ../kubernetes.tar.bz2 kubernetes
    mv ../kubernetes.tar.bz2 $WORKSPACE/UPLOAD_REPOS/
    rm -rf WORKSPACE/UPLOAD_REPOS/kubernetes
    ls -l $WORKSPACE/UPLOAD_REPOS/
#FIXME
    mv $WORKSPACE/UPLOAD_REPOS/kubernetes.tar.bz2 $WORKSPACE/logs/
fi

if [ "x$PIPELINE" == "xperiodic" -a "x$DISTRO" == "xcentos" ]; then
    echo
fi
