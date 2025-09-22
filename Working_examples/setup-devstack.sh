#!/bin/bash
set -e

echo "=== DevStack Minimal Demo Setup (LinuxBridge) ==="

# Source admin credentials
source ~/devstack/openrc admin admin

# --- 1. Create demo project and user ---
echo "--- Creating project and user ---"
openstack project show demo &>/dev/null || openstack project create demo
openstack user show demo &>/dev/null || openstack user create --project demo --password demo demo
openstack role add --user demo --project demo admin || true

# --- 2. Create network, subnet, router ---
echo "--- Setting up networking ---"
openstack network show demo-net &>/dev/null || openstack network create demo-net
openstack subnet show demo-subnet &>/dev/null || \
    openstack subnet create --network demo-net --subnet-range 10.0.0.0/24 demo-subnet

# Router setup only if LinuxBridge public network exists
if ! openstack router show demo-router &>/dev/null; then
    openstack router create demo-router
    # Replace 'public' with your actual LinuxBridge external network name if different
    openstack router set demo-router --external-gateway public
    openstack router add subnet demo-router demo-subnet
fi

# --- 3. Configure security group ---
echo "--- Configuring security group rules ---"
openstack security group rule list default &>/dev/null || {
    openstack security group rule create --proto icmp default || true
    openstack security group rule create --proto tcp --dst-port 22 default || true
}

# --- 4. Generate SSH keypair ---
echo "--- Generating SSH keypair ---"
KEY_NAME="cirros-key"
KEY_PATH=~/cirros-key
if [ ! -f $KEY_PATH ]; then
    ssh-keygen -t rsa -b 2048 -f $KEY_PATH -N ""
fi
openstack keypair show $KEY_NAME &>/dev/null || \
    openstack keypair create --public-key $KEY_PATH.pub $KEY_NAME

# --- 5. Launch CirrOS VM ---
echo "--- Launching CirrOS VM ---"
VM_NAME="demo-vm"
if ! openstack server show $VM_NAME &>/dev/null; then
    openstack server create --flavor m1.tiny \
        --image cirros-0.6.3-x86_64-disk \
        --network demo-net \
        --key-name $KEY_NAME \
        $VM_NAME
fi

# --- 6. Assign floating IP ---
echo "--- Assigning floating IP ---"
FLOATING_IP=$(openstack floating ip list -f value -c "Floating IP Address" | head -n 1)
if [ -z "$FLOATING_IP" ]; then
    FLOATING_IP=$(openstack floating ip create public -f value -c floating_ip_address)
fi
openstack server add floating ip $VM_NAME $FLOATING_IP || true

echo "=== Setup complete! ==="
echo "VM Name: $VM_NAME"
echo "Floating IP: $FLOATING_IP"
echo "SSH: ssh -i $KEY_PATH cirros@$FLOATING_IP"
