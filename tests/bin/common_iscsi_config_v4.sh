function common_iscsi_config {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      image_tag: 4.0.0"
    echo "      storage_provider: host"
    echo "      install_type: source"
    echo "      storage_provider_fstype: xfs"
    echo "      ceph_backend: false"
    echo "      iscsi_helper: tgtadm"
    echo "      lvm_backends:"
    echo "      - '172.18.0.1': 'cinder-volumes'"
    echo "    cinder:"
    echo "      all:"
    echo "        image_tag: 4.0.0"
    echo "      volume_lvm:"
    echo "        daemonset:"
    echo "          element_name: cinder-volume"
    echo "      api:"
    echo "        all:"
    echo "          port_external: true"
    echo "          port: 8776"
    echo "    nova:"
    echo "      all:"
    echo "        image_tag: 4.0.0"
    echo "        placement_api_enabled: true"
    echo "        cell_enabled: true"
    echo "    ironic:"
    echo "      all:"
    echo "        image_tag: 4.0.0"
    echo "      conductor:"
    echo "        all:"
    echo "          ironic_api_ip: 172.21.0.10"
    echo "          ironic_provision_cidr: 172.21.0.0/24"
    echo "      inspector:"
    echo "        all:"
    echo "          initramfs_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.gz"
    echo "          kernel_url: http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.vmlinuz"
    echo "          ironic_dhcp_range: net2,172.22.0.10,172.22.0.20,255.255.255.0"
    echo "    horizon:"
    echo "      all:"
    echo "        image_tag: 4.0.0"
}
