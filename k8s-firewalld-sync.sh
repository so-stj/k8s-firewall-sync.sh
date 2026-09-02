#!/bin/bash

set -euo pipefail

ZONE="kubernetes"

# Networks that should ALWAYS be allowed in the Kubernetes zone.
# Change these if your cluster uses different networks.
NODE_NETWORK="192.168.100.0/24"
POD_NETWORK="10.200.0.0/16"
SERVICE_NETWORK="10.96.0.0/12"

echo "======================================"
echo " Kubernetes firewalld reconciliation"
echo "======================================"

# Check firewalld
if ! systemctl is-active --quiet firewalld; then
    echo "ERROR: firewalld is not running."
    exit 1
fi


# Check Kubernetes API
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Kubernetes API is not available."
    exit 1
fi

echo "Kubernetes API is available."


# Make sure enp0s8 belongs to kubernetes zone
if ! firewall-cmd --zone="$ZONE" --query-interface=enp0s8 >/dev/null; then
    echo "Adding enp0s8 to $ZONE..."
    firewall-cmd --zone="$ZONE" --add-interface=enp0s8
fi


# Function: add source if missing
add_source() {

    local SOURCE="$1"

    if firewall-cmd \
        --zone="$ZONE" \
        --query-source="$SOURCE" >/dev/null 2>&1; then

        echo "Already allowed: $SOURCE"

    else

        echo "Adding source: $SOURCE"

        firewall-cmd \
            --zone="$ZONE" \
            --add-source="$SOURCE"

    fi
}


# Static Kubernetes networks
echo ""
echo "Adding Kubernetes networks..."

add_source "$NODE_NETWORK"
add_source "$POD_NETWORK"
add_source "$SERVICE_NETWORK"

# Detect node Pod CIDRs
echo ""
echo "Detecting node Pod CIDRs..."

NODE_CIDRS=$(kubectl get nodes \
    -o jsonpath='{range .items[*]}{.spec.podCIDRs[*]}{"\n"}{end}' \
    2>/dev/null || true)

while read -r CIDR; do

    if [[ -n "$CIDR" ]]; then
        add_source "$CIDR"
    fi

done <<< "$NODE_CIDRS"

# Detect Service ClusterIPs
echo ""
echo "Detecting Kubernetes Service IPs..."

SERVICE_IPS=$(kubectl get svc -A \
    -o jsonpath='{range .items[*]}{.spec.clusterIP}{"\n"}{end}' \
    2>/dev/null || true)

while read -r IP; do

    if [[ -n "$IP" && "$IP" != "None" ]]; then
        add_source "$IP"
    fi

done <<< "$SERVICE_IPS"


# Detect EndpointSlice addresses
echo ""
echo "Detecting EndpointSlice addresses..."

ENDPOINT_IPS=$(kubectl get endpointslices -A \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[*]}{"\n"}{end}' \
    2>/dev/null || true)

while read -r IP; do

    if [[ -n "$IP" ]]; then
        add_source "$IP"
    fi

done <<< "$ENDPOINT_IPS"

# Show result
echo ""
echo "======================================"
echo " Kubernetes firewall sources"
echo "======================================"

firewall-cmd --zone="$ZONE" --list-sources

echo ""
echo "Kubernetes firewalld reconciliation complete."