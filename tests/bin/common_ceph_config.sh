function common_ceph_values {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      storage_provider: ceph"
    echo "      storage_provider_fstype: xfs"
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
}
