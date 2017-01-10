function registry_file {
    BASE_DISTRO=$1
    INSTALL_TYPE=$2
    filename=${BASE_DISTRO}-${INSTALL_TYPE}-registry-${ZUUL_BRANCH}.tar.gz
    echo $filename
}

function setup_registry {
    BASE_DISTRO=$1
    INSTALL_TYPE=$2
    KEEP_TAR=$3
    TAR_DIR=$4
    filename=$(registry_file $BASE_DISTRO $INSTALL_TYPE)
    if [ ! -f $TAR_DIR/$filename ]; then
        echo Downloading $filename
        wget -q -c -O $TAR_DIR/$filename \
            http://tarballs.openstack.org/kolla/images/$filename
    fi
    sudo mkdir /tmp/kolla_registry
    sudo chmod -R 644 /tmp/kolla_registry
    sudo tar xzf $TAR_DIR/$filename -C /tmp/kolla_registry
    [ "xKEEP_TAR" == "x" ] && rm -f $TAR_DIR/$filename
    sudo chmod -R +x /tmp/kolla_registry
    sudo docker run -d -p 4000:5000 --restart=always -v /tmp/kolla_registry/:/var/lib/registry --name registry registry:2
}
