function common_iscsi_config {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      docker_registry: 127.0.0.1:30401"
    echo "      docker_namespace: lokolla"
    echo "      image_tag: 5.0.0"
    echo "      storage_provider: host"
    echo "      install_type: source"
    echo "      storage_provider_fstype: xfs"
    echo "      ceph_backend: false"
    echo "      kolla_toolbox_image_tag: 5.0.0"
    echo "      haproxy_image_tag: 5.0.0"
    echo "      fluentd_image_tag: 5.0.0"
    echo "      kubernetes_entrypoint_image_tag: 5.0.0"
    echo "      iscsi_helper: lioadm"
    echo "      lvm_backends:"
    echo "      - '172.18.0.1': 'cinder-volumes'"
    echo "    cinder:"
    echo "      all:"
    echo "        image_tag: 5.0.0"
    echo "      volume_lvm:"
    echo "        all:"
    echo "          element_name: cinder-volume"
    echo "    nova:"
    echo "      all:"
    echo "        image_tag: 5.0.0"
    echo "        placement_api_enabled: true"
    echo "        cell_enabled: true"
    echo "      api:"
    echo "        create_cell:"
    echo "          job:"
    echo "            cell_wait_compute: false"
    echo "    ironic:"
    echo "      all:"
    echo "        image_tag: 5.0.0"
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
    echo "        image_tag: 5.0.0"
}
