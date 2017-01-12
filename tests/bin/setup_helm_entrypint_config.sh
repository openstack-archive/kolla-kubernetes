function helm_entrypoint_general {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      kube_logger: false"
    echo "      kolla_base_distro: $base_distro"
    echo "      tunnel_interface: $tunnel_interface"
    echo "      external_vip: 172.18.0.1"
    echo "      external_vip: $IP"
    echo "    neutron:"
    echo "      server:"
    echo "        svc:"
    echo "          port_external: true"
}
