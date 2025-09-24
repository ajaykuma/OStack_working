#!/bin/bash
set -euo pipefail
set -x

# -------------------------------
# Logging
# -------------------------------
LOGDIR=/var/log/microstack-vm-create || LOGDIR="./"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/vm-create-$(date +%Y%m%d-%H%M%S).log"

# prepend timestamps to tee output
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush(); }' | tee -a "$LOGFILE") 2>&1

echo "=== VM creation script started: $(date) ==="

# When script exits or errors, print helpful diagnostic summary
on_error() {
    rc=$?
    echo "!!! Script exited with code $rc at $(date) !!!"
    # print last lines of main log
    echo "---- Last 200 lines of log ($LOGFILE) ----"
    tail -n 200 "$LOGFILE" || true

    # If SERVER_ID is set, attempt to show server diagnostics
    if [ -n "${SERVER_ID:-}" ]; then
        echo "---- Server show (full) ----"
        microstack.openstack server show "$SERVER_ID" -f json || microstack.openstack server show "$SERVER_ID" || true

        echo "---- Server fault (value) ----"
        microstack.openstack server show "$SERVER_ID" -f value -c fault || true

        echo "---- Console log (last lines) ----"
        # try both console log commands in case one isn't available
        microstack.openstack console log show "$SERVER_ID" --length 200 || microstack.openstack console log show "$SERVER_ID" || true

        echo "---- Attempting to get server diagnostics (if permitted) ----"
        microstack.openstack server diagnostics show "$SERVER_ID" || true
    else
        echo "SERVER_ID not set; skipping server diagnostics."
    fi

    echo "---- List of servers (short) ----"
    microstack.openstack server list || true

    echo "---- Floating IPs ----"
    microstack.openstack floating ip list || true

    echo "---- Security groups ----"
    microstack.openstack security group list || true

    echo "Log file location: $LOGFILE"
}
trap on_error EXIT

# -------------------------------
# Configuration
# -------------------------------
source /var/snap/microstack/common/etc/microstack.rc || {
    echo "ERROR: Failed to source microstack.rc"
    exit 1
}

PROJECT_NAME=demo
USER_NAME=demo
PASSWORD=demo
VM_NAME=demo2-vm
FLAVOR=m1.tiny
IMAGE=cirros
EXTERNAL_NET=external
NETWORK_NAME=demo2-net
SUBNET_NAME=demo2-subnet
SUBNET_CIDR=10.10.10.0/24
ROUTER_NAME=demo2-router
COMPUTE_HOST=mac2
KEY_NAME=cirros-key
KEY_PRIVATE=~/cirros-key
KEY_PUBLIC=/var/snap/microstack/common/cirros-key.pub
USER_DATA=/var/snap/microstack/common/cirros-user-data.yaml

# useful small helper to run a command but continue on failures in some places
run_safe() {
    echo "+ $*"
    if ! "$@"; then
        echo "WARNING: command failed: $*"
    fi
}

# -------------------------------
# Prepare SSH key
# -------------------------------
if [ ! -f "$KEY_PRIVATE" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 2048 -f "$KEY_PRIVATE" -N "" || {
        echo "ERROR: ssh-keygen failed"
        exit 1
    }
fi
cp -f "$KEY_PRIVATE.pub" "$KEY_PUBLIC"

if ! microstack.openstack keypair show "$KEY_NAME" &>/dev/null; then
    microstack.openstack keypair create --public-key "$KEY_PUBLIC" "$KEY_NAME"
fi

# -------------------------------
# Create or reuse project/user
# -------------------------------
if ! microstack.openstack project show "$PROJECT_NAME" &>/dev/null; then
    microstack.openstack project create "$PROJECT_NAME"
fi

if ! microstack.openstack user show "$USER_NAME" &>/dev/null; then
    microstack.openstack user create --project "$PROJECT_NAME" --password "$PASSWORD" "$USER_NAME"
fi
microstack.openstack role add --user "$USER_NAME" --project "$PROJECT_NAME" admin || true

# -------------------------------
# Create network/subnet if missing
# -------------------------------
if ! microstack.openstack network show "$NETWORK_NAME" &>/dev/null; then
    echo "Creating network $NETWORK_NAME..."
    NETWORK_ID=$(microstack.openstack network create "$NETWORK_NAME" -f value -c id)
else
    NETWORK_ID=$(microstack.openstack network show "$NETWORK_NAME" -f value -c id)
    echo "Reusing network $NETWORK_NAME (ID: $NETWORK_ID)"
fi

if ! microstack.openstack subnet show "$SUBNET_NAME" &>/dev/null; then
    echo "Creating subnet $SUBNET_NAME with CIDR $SUBNET_CIDR..."
    SUBNET_ID=$(microstack.openstack subnet create --network "$NETWORK_ID" --subnet-range "$SUBNET_CIDR" "$SUBNET_NAME" -f value -c id)
else
    SUBNET_ID=$(microstack.openstack subnet show "$SUBNET_NAME" -f value -c id)
    echo "Reusing subnet $SUBNET_NAME (ID: $SUBNET_ID)"
fi

# -------------------------------
# Create router if missing
# -------------------------------
if ! microstack.openstack router show "$ROUTER_NAME" &>/dev/null; then
    echo "Creating router $ROUTER_NAME..."
    ROUTER_ID=$(microstack.openstack router create "$ROUTER_NAME" -f value -c id)
else
    ROUTER_ID=$(microstack.openstack router show "$ROUTER_NAME" -f value -c id)
    echo "Reusing router $ROUTER_NAME (ID: $ROUTER_ID)"
fi

# -------------------------------
# Set external gateway and attach subnet
# -------------------------------
microstack.openstack router set "$ROUTER_ID" --external-gateway "$EXTERNAL_NET"

if ! microstack.openstack router show "$ROUTER_ID" -f value -c interfaces_info | grep -q "$SUBNET_ID"; then
    microstack.openstack router add subnet "$ROUTER_ID" "$SUBNET_ID"
fi

# Give OpenStack a moment to propagate router and subnet
echo "Sleeping 5s to ensure router and subnet are ready..."
sleep 5

# -------------------------------
# Security group rules
# -------------------------------
if ! microstack.openstack security group rule list default | grep -q "icmp"; then
    microstack.openstack security group rule create --proto icmp default || true
fi
if ! microstack.openstack security group rule list default | grep -q "22"; then
    microstack.openstack security group rule create --proto tcp --dst-port 22 default || true
fi

# -------------------------------
# User-data for SSH key injection
# -------------------------------
cat > "$USER_DATA" <<EOF
#cloud-config
ssh_authorized_keys:
  - $(cat "$KEY_PUBLIC")
EOF
echo "Wrote user-data to $USER_DATA"

# -------------------------------
# Launch VM on compute node
# -------------------------------
echo "Launching VM $VM_NAME on $COMPUTE_HOST..."
SERVER_ID=$(microstack.openstack server create \
    --flavor "$FLAVOR" \
    --image "$IMAGE" \
    --network "$NETWORK_ID" \
    --key-name "$KEY_NAME" \
    --hint "force_hosts=$COMPUTE_HOST" \
    --user-data "$USER_DATA" \
    "$VM_NAME" \
    -f value -c id) || {
    echo "ERROR: server create command failed. Check $LOGFILE and the output above."
    exit 1
}


echo "Created server with ID: $SERVER_ID"

# -------------------------------
# Wait for VM ACTIVE
# -------------------------------
echo "Waiting for VM to become ACTIVE..."
START_TS=$(date +%s)
TIMEOUT=300  # seconds
while true; do
    STATUS=$(microstack.openstack server show "$SERVER_ID" -f value -c status 2>/dev/null || echo "UNKNOWN")
    echo "Current status: $STATUS"
    if [ "$STATUS" = "ACTIVE" ]; then
        echo "Server is ACTIVE"
        break
    elif [ "$STATUS" = "ERROR" ]; then
        echo "VM creation entered ERROR state - collecting diagnostics..."
        # Gather additional info immediately
        microstack.openstack server show "$SERVER_ID" -f json || true
        microstack.openstack server show "$SERVER_ID" -f value -c fault || true
        microstack.openstack console log show "$SERVER_ID" --length 200 || microstack.openstack console log show "$SERVER_ID" || true
        # exit with failure (trap will run)
        exit 1
    fi

    # timeout
    now=$(date +%s)
    if [ $((now - START_TS)) -gt $TIMEOUT ]; then
        echo "Timed out waiting for ACTIVE after ${TIMEOUT}s. Gathering diagnostics..."
        microstack.openstack server show "$SERVER_ID" -f json || true
        microstack.openstack server show "$SERVER_ID" -f value -c fault || true
        microstack.openstack console log show "$SERVER_ID" --length 200 || microstack.openstack console log show "$SERVER_ID" || true
        exit 1
    fi

    sleep 3
done

# -------------------------------
# Assign floating IP
# -------------------------------
echo "Sleeping 5s before assigning floating IP..."
sleep 5
FLOATING_IP=$(microstack.openstack floating ip create "$EXTERNAL_NET" -f value -c floating_ip_address)
microstack.openstack server add floating ip "$SERVER_ID" "$FLOATING_IP"

echo "VM $VM_NAME is ACTIVE with floating IP $FLOATING_IP"

# -------------------------------
# Validate SSH connectivity
# -------------------------------
echo "Validating VM connectivity..."
sleep 10
if ssh -o StrictHostKeyChecking=no -i "$KEY_PRIVATE" cirros@"$FLOATING_IP" "echo 'SSH OK'"; then
    echo "SSH connectivity OK"
else
    echo "SSH connectivity FAILED - fetching some extra info"
    microstack.openstack server show "$SERVER_ID" -f json || true
    microstack.openstack console log show "$SERVER_ID" --length 200 || microstack.openstack console log show "$SERVER_ID" || true
fi

# -------------------------------
# Show OpenStack resources
# -------------------------------
echo "Server list on $COMPUTE_HOST:"
microstack.openstack server list --host "$COMPUTE_HOST" || true
echo "Security groups:"
microstack.openstack security group list || true
echo "Floating IPs:"
microstack.openstack floating ip list || true

rm -f "$USER_DATA"
echo "Script completed successfully!"
echo "SSH command: ssh -i $KEY_PRIVATE cirros@$FLOATING_IP"

#In vm creation we could use : #--availability-zone "nova:$COMPUTE_HOST" \
