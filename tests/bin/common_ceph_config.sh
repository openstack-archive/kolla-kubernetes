function common_ceph_config {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    if [ "x$2" == "xt" ]; then
      echo "      docker_registry: 127.0.0.1:30401"
      echo "      docker_namespace: lokolla"
      echo "      image_tag: 5.0.0"
    fi
    echo "      ceph_backend: true"
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
    echo "    glance:"
    echo "      all:"
    echo "        ceph_backend: true"
    echo "    nova:"
    echo "      all:"
    echo "        ceph_backend: true"
}
