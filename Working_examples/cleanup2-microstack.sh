#!/bin/bash
set -e

echo "Starting MicroStack cleanup..."

# Source MicroStack credentials
source /var/snap/microstack/common/etc/microstack.rc

# Delete floating IPs
for fip in $(microstack.openstack floating ip list -f value -c "ID"); do
    echo "Deleting floating IP $fip"
    microstack.openstack floating ip delete $fip || true
done

# Delete all VMs
for vm in $(microstack.openstack server list -f value -c "ID"); do
    echo "Deleting VM $vm"
    microstack.openstack server delete $vm || true
done

# Wait a few seconds for VMs to fully disappear
sleep 5

# Remove router interfaces
for router in $(microstack.openstack router list -f value -c "Name"); do
    for subnet in $(microstack.openstack subnet list -f value -c "ID"); do
        echo "Removing subnet $subnet from router $router"
        microstack.openstack router remove subnet $router $subnet || true
    done
done

# Delete routers
for router in $(microstack.openstack router list -f value -c "Name"); do
    echo "Deleting router $router"
    microstack.openstack router delete $router || true
done

# Delete ports on networks to avoid ConflictException
for net in $(microstack.openstack network list -f value -c "Name" | grep -v external); do
    for port in $(microstack.openstack port list --network $net -f value -c "ID"); do
        echo "Deleting port $port on network $net"
        microstack.openstack port delete $port || true
    done
done

# Delete networks
for net in $(microstack.openstack network list -f value -c "Name" | grep -v external); do
    echo "Deleting network $net"
    microstack.openstack network delete $net || true
done

# Delete keypairs
for key in $(microstack.openstack keypair list -f value -c "Name"); do
    echo "Deleting keypair $key"
    microstack.openstack keypair delete $key || true
done

# Delete projects and users (demo)
for proj in $(microstack.openstack project list -f value -c "Name" | grep demo); do
    echo "Deleting project $proj"
    microstack.openstack project delete $proj || true
done

for user in $(microstack.openstack user list -f value -c "Name" | grep demo); do
    echo "Deleting user $user"
    microstack.openstack user delete $user || true
done

echo "MicroStack cleanup complete!"
