function common_iscsi_config {
    echo "global:"
    echo "  kolla:"
    echo "    all:"
    echo "      image_tag: 3.0.3-beta.1"
    echo "      storage_provider: host"
    echo "      install_type: source"
    echo "      storage_provider_fstype: xfs"
    echo "      ceph_backend: false"
    echo "      lvm_backends:"
    echo "      - '172.18.0.1': 'cinder-volumes'"
    echo "    cinder:"
    echo "      all:"
    echo "        image_tag: 3.0.3-beta.1"
    echo "      volume_lvm:"
    echo "        all:"
    echo "          element_name: cinder-volume"
    echo "    nova:"
    echo "      all:"
    echo "        image_tag: 3.0.3-beta.1"
    echo "    ironic:"
    echo "      all:"
    echo "        image_tag: 3.0.3-beta.1"
    echo "      dnsmasq:
    echo "        all:
    echo "          initramf_url: "http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.gz"
    echo "          kernel_url: "http://tarballs.openstack.org/ironic-python-agent/tinyipa/files/tinyipa-stable-newton.vmlinuz"
    echo "          ironic_dhcp_range: net2,172.22.0.10,172.22.0.20,255.255.255.0,24h"
    echo "    horizon:"
    echo "      all:"
    echo "        image_tag: 3.0.3-beta.1"
}
