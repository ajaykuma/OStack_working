#!/bin/bash
set -e

echo "Cleaning up OpenStack resources..."

# Source credentials
source /var/snap/microstack/common/etc/microstack.rc

# Delete floating IPs
for fip in $(microstack.openstack floating ip list -f value -c "ID"); do
    echo "Deleting floating IP $fip"
    microstack.openstack floating ip delete $fip
done

# Delete VM(s)
for vm in $(microstack.openstack server list -f value -c "ID"); do
    echo "Deleting VM $vm"
    microstack.openstack server delete $vm
done

# Delete router interfaces
for subnet in $(microstack.openstack subnet list -f value -c "ID"); do
    if microstack.openstack router show demo-router &>/dev/null; then
        echo "Removing subnet $subnet from router"
        microstack.openstack router remove subnet demo-router $subnet || true
    fi
done

# Delete router
if microstack.openstack router show demo-router &>/dev/null; then
    echo "Deleting router demo-router"
    microstack.openstack router delete demo-router
fi

# Delete network(s)
for net in $(microstack.openstack network list -f value -c "Name" | grep -v external); do
    echo "Deleting network $net"
    microstack.openstack network delete $net || true
done

# Delete keypairs
for key in $(microstack.openstack keypair list -f value -c "Name"); do
    echo "Deleting keypair $key"
    microstack.openstack keypair delete $key
done

# Delete project + user (demo)
if microstack.openstack project show demo &>/dev/null; then
    echo "Deleting project demo"
    microstack.openstack project delete demo
fi
if microstack.openstack user show demo &>/dev/null; then
    echo "Deleting user demo"
    microstack.openstack user delete demo
fi

echo "Cleanup complete"
