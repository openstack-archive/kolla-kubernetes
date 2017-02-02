function common_entrypoint_config {
    $IP="$1"
    $base_distro="$2"
    $tunnel_interface="$3"
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      kube_logger: false"
    echo "      external_vip: $IP"
    echo "      base_distro: $base_distro"
    echo "      tunnel_interface: $tunnel_interface"
    echo "      storage_provider: ceph"
    echo "      storage_provider_fstype: xfs"
    echo "      ceph:"
    echo "         monitors:"
    ### NOTE (sbezverk)  172.17.0.1 is default ip address used by Docker
    addr=172.17.0.1
    if [ "x$4" == "xceph-multi" ]; then
        addr=$(cat /etc/nodepool/primary_node_private)
    fi
    echo "             - $addr"
    echo "         pool: kollavolumes"
    echo "         secret_name: ceph-kolla"
    echo "         user: kolla"
    echo "    keystone:"
    echo "      all:"
    echo "        admin_port_external: true"
    echo "        dns_name: $IP"
}
