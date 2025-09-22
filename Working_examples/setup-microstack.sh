#!/bin/bash
set -e

echo "Setting up OpenStack demo environment..."

# Source credentials
source /var/snap/microstack/common/etc/microstack.rc

# Paths
KEY_DIR=/var/snap/microstack/common
KEY_NAME=cirros-key
KEY_PRIVATE=~/cirros-key
KEY_PUBLIC=$KEY_DIR/cirros-key.pub

# Create project & user
echo "Creating project and user..."
microstack.openstack project create demo || true
microstack.openstack user create --project demo --password demo demo || true
microstack.openstack role add --user demo --project demo admin || true

# Create network, subnet & router
echo "Setting up networking..."
microstack.openstack network create demo-net || true
microstack.openstack subnet create --network demo-net --subnet-range 10.0.0.0/24 demo-subnet || true

if ! microstack.openstack router show demo-router &>/dev/null; then
    microstack.openstack router create demo-router
    microstack.openstack router set demo-router --external-gateway external
fi

# Ensure subnet is attached to router
if ! microstack.openstack router show demo-router -f value -c interfaces | grep -q demo-subnet; then
    microstack.openstack router add subnet demo-router demo-subnet
fi

# Security group rules
echo "Configuring security groups..."
microstack.openstack security group rule create --proto icmp default || true
microstack.openstack security group rule create --proto tcp --dst-port 22 default || true

# Generate SSH keypair
echo "Generating SSH keypair..."
if [ ! -f "$KEY_PRIVATE" ]; then
    ssh-keygen -t rsa -b 2048 -f "$KEY_PRIVATE" -N ""
fi

# Copy public key to snap-accessible path
cp -f "$KEY_PRIVATE.pub" "$KEY_PUBLIC"

# Create keypair in OpenStack (idempotent)
if ! microstack.openstack keypair show $KEY_NAME &>/dev/null; then
    microstack.openstack keypair create --public-key "$KEY_PUBLIC" $KEY_NAME
fi

# Launch CirrOS VM
echo "Launching CirrOS VM..."
SERVER_ID=$(microstack.openstack server create --flavor m1.tiny \
  --image cirros \
  --network demo-net \
  --key-name $KEY_NAME \
  demo-vm -f value -c id)

# Wait until server is ACTIVE
echo "Waiting for VM to become ACTIVE..."
#microstack.openstack server wait --active $SERVER_ID

echo "Waiting for VM to become ACTIVE..."
while true; do
    STATUS=$(microstack.openstack server show $SERVER_ID -f value -c status)
    echo "Current status: $STATUS"
    if [ "$STATUS" == "ACTIVE" ]; then
        break
    elif [ "$STATUS" == "ERROR" ]; then
        echo "VM creation failed!"
        exit 1
    fi
    sleep 3
done

# Assign floating IP
echo "Assigning floating IP..."
FLOATING_IP=$(microstack.openstack floating ip create external -f value -c floating_ip_address)
microstack.openstack server add floating ip $SERVER_ID $FLOATING_IP

echo "Setup complete!"
echo "   VM Name: demo-vm"
echo "   Floating IP: $FLOATING_IP"
echo "   SSH Command: ssh -i $KEY_PRIVATE cirros@$FLOATING_IP"
