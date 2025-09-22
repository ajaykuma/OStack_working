#!/bin/bash
set -e

echo "=== Cleaning up DevStack Demo Environment (LinuxBridge) ==="

source ~/devstack/openrc admin admin

# Delete VM
VM_NAME="demo-vm"
if openstack server show $VM_NAME &>/dev/null; then
    openstack server delete $VM_NAME
fi

# Delete floating IPs
for IP in $(openstack floating ip list -f value -c "Floating IP Address"); do
    openstack floating ip delete $IP
done

# Delete keypair
KEY_NAME="cirros-key"
if openstack keypair show $KEY_NAME &>/dev/null; then
    openstack keypair delete $KEY_NAME
fi

# Delete router
ROUTER_NAME="demo-router"
if openstack router show $ROUTER_NAME &>/dev/null; then
    for PORT in $(openstack router show $ROUTER_NAME -f value -c interfaces_info | jq -r '.[].port_id'); do
        openstack router remove port $ROUTER_NAME $PORT
    done
    openstack router delete $ROUTER_NAME
fi

# Delete subnet & network
SUBNET_NAME="demo-subnet"
NETWORK_NAME="demo-net"
openstack subnet delete $SUBNET_NAME || true
openstack network delete $NETWORK_NAME || true

# Delete demo project
PROJECT_NAME="demo"
openstack project delete $PROJECT_NAME || true

echo "=== Cleanup complete ==="
