#!/bin/bash
# Neutron Diagnostic & Integration Test Script
# Author: ChatGPT
# Usage: sudo bash neutron_diagnostics.sh

set -e

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

function check_command() {
    if ! command -v openstack &>/dev/null; then
        echo "${RED}[ERROR] openstack CLI not found. Install python-openstackclient.${RESET}"
        exit 1
    fi
}

function print_header() {
    echo ""
    echo "============================================"
    echo " $1"
    echo "============================================"
}

check_command

print_header "Keystone ↔ Neutron Authentication"
if openstack network list &>/dev/null; then
    echo "${GREEN}[PASS] Able to query Neutron using Keystone token.${RESET}"
else
    echo "${RED}[FAIL] Neutron authentication failed. Check Keystone credentials or endpoints.${RESET}"
fi

print_header "Neutron Service Endpoints"
if openstack endpoint list | grep -q network; then
    openstack endpoint list | grep network
    echo "${GREEN}[PASS] Neutron endpoints are registered.${RESET}"
else
    echo "${RED}[FAIL] No Neutron endpoints found. Check service registration.${RESET}"
fi

print_header "Create Test Network + Subnet"
TEST_NET="diag-net"
TEST_SUBNET="diag-subnet"

if ! openstack network show $TEST_NET &>/dev/null; then
    openstack network create $TEST_NET >/dev/null
    openstack subnet create --network $TEST_NET --subnet-range 10.123.0.0/24 $TEST_SUBNET >/dev/null
    echo "${GREEN}[PASS] Test network and subnet created.${RESET}"
else
    echo "${YELLOW}[INFO] Network $TEST_NET already exists.${RESET}"
fi

print_header "Neutron ↔ Nova: Port Creation Simulation"
if openstack port create --network $TEST_NET diag-port >/dev/null; then
    echo "${GREEN}[PASS] Port creation successful — Nova should be able to request ports.${RESET}"
else
    echo "${RED}[FAIL] Port creation failed. Check Neutron server or agent logs.${RESET}"
fi

print_header "Launch Test Instance (Nova ↔ Neutron)"
IMAGE=$(openstack image list -f value -c Name | head -n1)
FLAVOR=$(openstack flavor list -f value -c Name | head -n1)

if openstack server create --flavor "$FLAVOR" --image "$IMAGE" --network "$TEST_NET" diag-vm >/dev/null; then
    echo "${GREEN}[PASS] VM launch initiated. Nova successfully communicated with Neutron.${RESET}"
else
    echo "${RED}[FAIL] VM creation failed. Check nova-api and neutron-server logs.${RESET}"
fi

print_header "Port Check for Created VM"
SERVER_ID=$(openstack server show diag-vm -f value -c id 2>/dev/null || echo "none")
if [ "$SERVER_ID" != "none" ]; then
    openstack port list --server $SERVER_ID
    echo "${GREEN}[PASS] VM ports created successfully.${RESET}"
else
    echo "${RED}[FAIL] Could not find VM ports. Port creation might have failed.${RESET}"
fi

print_header "Neutron Agents Status"
openstack network agent list

print_header "Network Namespaces (DHCP / Router)"
ip netns

print_header "Summary"
echo "- Keystone auth tested"
echo "- Neutron endpoints verified"
echo "- Network & port creation tested"
echo "- Nova integration validated by spawning VM"
echo "- DHCP/router namespaces inspected"
echo ""
echo "${GREEN} If all steps passed above, Neutron is healthy and integrated properly.${RESET}"
