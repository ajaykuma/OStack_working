#!/bin/bash
set -e

echo "=== Validating DevStack Setup ==="

# Source admin credentials
source ~/devstack/openrc admin admin

# Helper function to check service endpoints
check_service() {
    local svc=$1
    if openstack service list | grep -iq "$svc"; then
        echo "Service $svc: OK"
    else
        echo "Service $svc: MISSING"
    fi
}

# 1. Validate core services
echo "--- Checking core services ---"
for service in keystone nova glance placement; do
    check_service $service
done

# 2. Validate Neutron services for LinuxBridge
echo "--- Checking Neutron (LinuxBridge) ---"
for svc in network subnet router; do
    if [ "$svc" == "network" ]; then
        openstack network list | grep -q demo-net && echo "Network: OK" || echo "Network: MISSING"
    elif [ "$svc" == "subnet" ]; then
        openstack subnet list | grep -q demo-subnet && echo "Subnet: OK" || echo "Subnet: MISSING"
    elif [ "$svc" == "router" ]; then
        openstack router list | grep -q demo-router && echo "Router: OK" || echo "Router: MISSING"
    fi
done

# 3. Validate images
echo "--- Checking images ---"
if openstack image list | grep -q "cirros-0.6.2-x86_64-disk"; then
    echo "CirrOS image: OK"
else
    echo "CirrOS image: MISSING"
fi

# 4. Validate keypair
echo "--- Checking keypair ---"
if openstack keypair list | grep -q cirros-key; then
    echo "Keypair: OK"
else
    echo "Keypair: MISSING"
fi

# 5. Validate demo VM
echo "--- Checking demo VM ---"
if openstack server show demo-vm &>/dev/null; then
    STATUS=$(openstack server show demo-vm -f value -c status)
    echo "demo-vm status: $STATUS"
else
    echo "demo-vm: MISSING"
fi

# 6. Validate floating IP assignment
echo "--- Checking floating IP ---"
if openstack server show demo-vm -f value -c addresses | grep -q "public"; then
    FLOAT_IP=$(openstack server show demo-vm -f value -c addresses | awk '{print $2}')
    echo "Floating IP assigned: $FLOAT_IP"
else
    echo "Floating IP: NOT ASSIGNED"
fi

echo "=== Validation complete ==="
