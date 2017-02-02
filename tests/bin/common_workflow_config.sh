function common_workflow_config {
    IP="$1"
    base_distro="$2"
    tunnel_interface="$3"
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      kube_logger: false"
    echo "      external_vip: $IP"
    echo "      base_distro: $base_distro"
    echo "      tunnel_interface: $tunnel_interface"
    echo "    keystone:"
    echo "      all:"
    echo "        admin_port_external: true"
    echo "        dns_name: $IP"
}
