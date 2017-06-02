function common_workflow_config {
#  Passed parameters: $1 - IP, $2 - base_distro,
#                     $3 - tunnel_interface, $4 - branch
    IP="$1"
    base_distro="$2"
    tunnel_interface="$3"
    branch="$4"

    echo "global:"
    echo "  kolla:"
    echo "    keystone:"
    echo "      all:"
    echo "        admin_port_external: true"
    echo "        dns_name: $IP"
    echo "      public:"
    echo "        all:"
    echo "          port_external: true"
    echo "    rabbitmq:"
    echo "      all:"
    echo "        cookie: 67"
    echo "    glance:"
    echo "      api:"
    echo "        all:"
    echo "          port_external: true"
    echo "    cinder:"
    echo "      api:"
    echo "        all:"
    echo "          port_external: true"
    echo "    ironic:"
# Ironic should use default image tags with exception of Branch 3  
    if [ "x$branch" == "x3" ]; then
       echo "      all:"
       echo "        image_tag: 3.0.3-beta.1"
    fi
    echo "      conductor:"
    echo "        all:"
    echo "          initramfs_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.gz"
    echo "          kernel_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.vmlinuz"
    echo "          ironic_api_ip: 172.21.0.10"
    echo "          ironic_provision_cidr: 172.21.0.0/24"
    echo "      inspector:"
    echo "        all:"
    echo "          initramfs_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.gz"
    echo "          kernel_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.vmlinuz"
    echo "          ironic_dhcp_range: net2,172.22.0.10,172.22.0.20,255.255.255.0"
    echo "    helm-repo:"
    echo "      all:"
    echo "        image_tag: 3.0.3-beta.1"

# Disable nova placement API on 2.y.z and 3.y.z images as they don't exist
    if [ "x$branch" == "x2" -o "x$branch" == "x3" ]; then
        echo "    nova:"
        echo "      all:"
        echo "        placement_api_enabled: false"
        echo "        cell_enabled: false"
    fi

    echo "    all:"
    echo "      kube_logger: false"
    echo "      external_vip: $IP"
    echo "      base_distro: $base_distro"
    echo "      tunnel_interface: $tunnel_interface"
    echo "    openvswitch:"
    echo "      all:"
    echo "        ext_bridge_up: true"
}
