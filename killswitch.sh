#!/bin/bash

# ===========================================
# WireGuard Kill Switch for macOS
# ===========================================
#
# This script creates a kill switch for WireGuard VPN on macOS using PF (Packet Filter).
# It ensures that traffic only flows through the VPN when active.
#
# Usage:
#   ./killswitch.sh
#
# Environment variables for configuration:
#   VPN_INTERFACE - WireGuard interface name (default: utun4)
#   WIREGUARD_PORT - WireGuard server port (default: 51820)
#   PF_RULES_PATH - Path to PF rules file (default: /etc/pf.anchors/wireguard_killswitch)
#
# Requirements:
#   - macOS operating system
#   - WireGuard installed
#   - Administrative privileges (sudo)

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ Error: This script only works on macOS"
    exit 1
fi

# Configuration (can be overridden by environment variables)
VPN_INTERFACE="${VPN_INTERFACE:-utun4}"
WIREGUARD_PORT="${WIREGUARD_PORT:-51820}"
PF_RULES_PATH="${PF_RULES_PATH:-/etc/pf.anchors/wireguard_killswitch}"

# Print configuration
echo "📝 Configuration:"
echo "   - VPN Interface: $VPN_INTERFACE"
echo "   - WireGuard Port: $WIREGUARD_PORT"
echo "   - Rules File: $PF_RULES_PATH"

# Cleanup function
cleanup() {
    echo "🛑 Disabling Kill Switch..."
    sudo pfctl -F all 2>/dev/null
    sudo pfctl -d 2>/dev/null
    echo "✅ Kill Switch disabled. Internet access restored."
    exit 0
}

# Reset firewall function
reset_firewall() {
    echo "🔄 Resetting firewall rules..."
    sudo pfctl -F all 2>/dev/null
    sudo pfctl -d 2>/dev/null
    sudo rm -f "$PF_RULES_PATH" 2>/dev/null
}

# Trap interrupt signals
trap cleanup SIGINT SIGTERM

# Check for administrative privileges
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo "⚠️  Administrative privileges required. Please enter your password:"
        sudo "$0" "$@"
        exit $?
    fi
}

# Check privileges
check_sudo

# Reset firewall first
reset_firewall

echo "🔧 Configuring Kill Switch for WireGuard..."

# Create firewall rules
create_pf_rules() {
    cat << EOF > "$PF_RULES_PATH"
# Default: block all traffic
block all

# Allow local traffic
pass quick on lo0 all

# Allow DHCP
pass quick proto udp from port 67 to port 68
pass quick proto udp from port 68 to port 67

# Allow DNS queries
pass quick proto udp to any port 53
pass quick proto tcp to any port 53

# Allow WireGuard connection
pass out quick proto udp to any port $WIREGUARD_PORT

# Allow traffic through VPN
pass quick on $VPN_INTERFACE all
EOF
}

# Create rules
create_pf_rules

# Enable firewall and load rules
echo "🔒 Activating firewall rules..."
sudo pfctl -e 2>/dev/null
sudo pfctl -f "$PF_RULES_PATH" 2>/dev/null

echo "✅ Kill Switch activated. Traffic is now only allowed through VPN."

# VPN connection check function
check_vpn() {
    # Check interface existence
    if ! ifconfig "$VPN_INTERFACE" &>/dev/null; then
        echo "⚠️  VPN is disconnected! (interface not found)"
        return 1
    fi

    # Check for IP address on interface
    if ! ifconfig "$VPN_INTERFACE" | grep -q "inet "; then
        echo "⚠️  VPN is disconnected! (no IP address)"
        return 1
    fi

    # Show current IP for diagnostics
    CURRENT_IP=$(ifconfig "$VPN_INTERFACE" | grep "inet " | awk '{print $2}')
    echo "✅ VPN is connected and active (interface: $VPN_INTERFACE, IP: $CURRENT_IP)"
    return 0
}

# Main monitoring loop
echo "🔍 VPN connection monitoring started. Press Ctrl+C to stop"
echo "📋 Current firewall rules:"
sudo pfctl -s rules

while true; do
    check_vpn
    sleep 5
done