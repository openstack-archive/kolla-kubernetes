function common_workflow_config {
    IP="$1"
    base_distro="$2"
    tunnel_interface="$3"
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
    echo "      all:"
    echo "        image_tag: 3.0.3-beta.1"
    echo "      conductor:"
    echo "        all:"
    echo "          initramfs_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.gz"
    echo "          kernel_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.vmlinuz"
    echo "          ironic_api_ip: 172.21.0.10"
    echo "          ironic_tftp_server: 172.21.0.10"
    echo "      dnsmasq:"
    echo "        all:"
    echo "          initramfs_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.gz"
    echo "          kernel_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.vmlinuz"
    echo "          ironic_dhcp_range: net2,172.22.0.10,172.22.0.20,255.255.255.0,24h"
    echo "    helm-repo:"
    echo "      all:"
    echo "        image_tag: 3.0.3-beta.1"
    echo "    all:"
    echo "      kube_logger: false"
    echo "      external_vip: $IP"
    echo "      base_distro: $base_distro"
    echo "      tunnel_interface: $tunnel_interface"
    echo "    openvswitch:"
    echo "      all:"
    echo "        interface_up: true"
}
