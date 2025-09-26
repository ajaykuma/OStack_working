#!/bin/bash
set -e

# ===============================
# Minimal DevStack + Ceph Setup
# ===============================

# Variables
DEVSTACK_DIR="$HOME/devstack"
ADMIN_PASS="secret"
CIRROS_URL="http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img"
IMAGE_NAME="cirros-0.6.2-x86_64-disk"
STACK_USER=$(whoami)

# 1. Install prerequisites
sudo apt update
sudo apt install -y git vim sudo lvm2 qemu-kvm libvirt-daemon-system libvirt-clients python3-openstackclient

# 2. Clone DevStack
if [ ! -d "$DEVSTACK_DIR" ]; then
    git clone https://opendev.org/openstack/devstack $DEVSTACK_DIR
fi
cd $DEVSTACK_DIR

# 3. Create local.conf for minimal services + Ceph
cat > local.conf <<EOF
[[local|localrc]]

ADMIN_PASSWORD=$ADMIN_PASS
DATABASE_PASSWORD=$ADMIN_PASS
RABBIT_PASSWORD=$ADMIN_PASS
SERVICE_PASSWORD=$ADMIN_PASS
SERVICE_TOKEN=tokentoken
HOST_IP=127.0.0.1

# Core OpenStack services
enable_service key g-api g-reg n-api n-sch n-cpu n-novnc horizon placement-api placement-client

# LinuxBridge networking
Q_AGENT=linuxbridge
enable_service q-svc q-agt q-dhcp q-l3 q-meta
disable_service q-ovn

# CirrOS image
IMAGE_URLS="$CIRROS_URL"

# Ceph (single-node)
enable_service r-ceph r-ceph-osd r-ceph-mon
GLANCE_STORE=ceph
GLANCE_CEPH_POOL=images
GLANCE_CEPH_USER=glance
GLANCE_CEPH_SECRET=$ADMIN_PASS

# Nova RBD support
VIRT_DRIVER=kvm
QEMU_USE_CEPH=true
RBD_POOL=images
RBD_USER=libvirt

# Logging
LOGFILE=\$DEST/logs/stack.sh.log
LOG_COLOR=True
EOF

# 4. Run DevStack
echo "Starting DevStack installation (this may take 30–60 minutes)..."
./stack.sh

# 5. Source admin credentials
source $DEVSTACK_DIR/openrc admin admin

# 6. Create demo project, user & network
echo "Creating demo project, user, network..."
openstack project create demo || true
openstack user create --project demo --password demo demo || true
openstack role add --user demo --project demo admin || true

openstack network create demo-net || true
openstack subnet create --network demo-net \
  --subnet-range 10.0.0.0/24 demo-subnet || true

if ! openstack router show demo-router &>/dev/null; then
    openstack router create demo-router
    openstack router set demo-router --external-gateway public
    openstack router add subnet demo-router demo-subnet
fi

# 7. Configure security group
openstack security group rule create --proto icmp default || true
openstack security group rule create --proto tcp --dst-port 22 default || true

# 8. Generate SSH keypair
if [ ! -f "$HOME/cirros-key" ]; then
    ssh-keygen -t rsa -b 2048 -f "$HOME/cirros-key" -N ""
fi
openstack keypair create --public-key "$HOME/cirros-key.pub" cirros-key || true

# 9. Launch CirrOS VM
openstack server create --flavor m1.tiny \
  --image $IMAGE_NAME \
  --network demo-net \
  --key-name cirros-key \
  demo-vm || true

# 10. Assign floating IP
FLOATING_IP=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip demo-vm $FLOATING_IP

echo "=============================================="
echo "Setup complete!"
echo "VM Name: demo-vm"
echo "Floating IP: $FLOATING_IP"
echo "SSH Command: ssh -i $HOME/cirros-key cirros@$FLOATING_IP"
echo "Horizon Dashboard: http://127.0.0.1/dashboard"
echo "=============================================="

