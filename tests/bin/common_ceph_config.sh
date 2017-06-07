function common_ceph_config {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      ceph_backend: true"
    echo "      storage_provider: ceph"
    echo "      storage_provider_fstype: xfs"
#FIXME this probably needs its own test...
    echo "      enable_tls: true"
    echo "      ceph:"
    echo "         monitors:"
    addr=172.17.0.1
    if [ "x$1" == "xceph-multi" ]; then
        addr=$(cat /etc/nodepool/primary_node_private)
    fi
    echo "             - $addr"
    echo "         pool: kollavolumes"
    echo "         secret_name: ceph-kolla"
    echo "         user: kolla"
    echo "    glance:"
    echo "      all:"
    echo "        ceph_backend: true"
    echo "    nova:"
    echo "      all:"
    echo "        ceph_backend: true"
}
