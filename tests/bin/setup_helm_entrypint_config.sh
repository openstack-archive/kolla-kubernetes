function helm_entrypoint_neutron {
    for x in neutron-create-keystone-service neutron-create-keystone-user \
    	 neutron-create-keystone-endpoint-internal \
    	 neutron-create-keystone-endpoint-admin neutron-create-db \
    	 neutron-manage-db neutron-server neutron-metadata-agent; \
        do
            echo "$x:"
            echo "    enable_kube_logger: false"
            echo "    kolla_base_distro: $base_distro"
    done
    for x in neutron-dhcp-agent neutron-l3-agent neutron-openvswitch-agent; \
        do
            echo "$x:"
            echo "    enable_kube_logger: false"
            echo "    kolla_base_distro: $base_distro"
            echo "    tunnel_interface: $tunnel_interface"
    done
    echo "neutron-create-keystone-endpoint-public:"
    echo "    enable_kube_logger: false"
    echo "    kolla_base_distro: $base_distro"
    echo "    kolla_kubernetes_external_vip: 172.18.0.1"
    echo "neutron-server-svc:"
    echo "    enable_kube_logger: false"
    echo "    kolla_base_distro: $base_distro"
    echo "    element_port_external: true"
    echo "    kolla_kubernetes_external_vip: 172.18.0.1"
}
