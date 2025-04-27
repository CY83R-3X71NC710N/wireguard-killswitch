#!/bin/bash

# ===========================================
# WireGuard Kill Switch for macOS (Auto MTU 1280 Detect) - v5 (No-Log IP Service)
# ===========================================
#
# This script creates a kill switch for WireGuard VPN on macOS using PF (Packet Filter).
# It automatically detects the 'utun' interface with MTU 1280.
# It ensures that traffic only flows through the VPN when active.
# It sends a macOS notification upon activation with interface name and public IP.
#
# Usage:
#   ./killswitch.sh
#
# Environment variables for configuration:
#   WIREGUARD_PORT - WireGuard server port (default: 51820)
#   PF_RULES_PATH - Path to PF rules file (default: /etc/pf.anchors/wireguard_killswitch)
#   PUBLIC_IP_SERVICE - URL to fetch public IP (default: https://api.ipify.org)
#
# Requirements:
#   - macOS operating system
#   - WireGuard installed
#   - Administrative privileges (sudo)
#   - curl (for public IP fetching)

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ Error: This script only works on macOS"
  exit 1
fi

# Configuration (can be overridden by environment variables)
TARGET_MTU="1280"
WIREGUARD_PORT="${WIREGUARD_PORT:-51820}"
PF_RULES_PATH="${PF_RULES_PATH:-/etc/pf.anchors/wireguard_killswitch}"
PUBLIC_IP_SERVICE="${PUBLIC_IP_SERVICE:-https://api.ipify.org}" # Changed to ipify.org

# --- Function Definitions ---

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

# Check for administrative privileges
check_sudo() {
  if [ "$EUID" -ne 0 ]; then
    echo "⚠️  Administrative privileges required. Please enter your password:"
    # Re-execute the script with sudo, passing along arguments if any
    sudo "$0" "$@"
    # Exit the original non-sudo script
    exit $?
  fi
}

# Function to find the VPN interface
find_vpn_interface() {
  echo "🔎 Searching for active 'utun' interface with MTU $TARGET_MTU..."
  # Use awk for more robust parsing: Find line starting with utun, containing 'mtu 1280', print first field, remove colon
  VPN_INTERFACE=$(ifconfig | awk '/^utun.*mtu '"$TARGET_MTU"'/ {gsub(/:$/, "", $1); print $1; exit}')

  if [ -z "$VPN_INTERFACE" ]; then
    echo "❌ Error: No active 'utun' interface with MTU $TARGET_MTU found."
    echo "   Available utun interfaces:"
    ifconfig | grep '^utun'
    exit 1
  fi
  echo "✅ Found VPN Interface: $VPN_INTERFACE"
}

# Create firewall rules function
create_pf_rules() {
  echo "🔧 Creating firewall rules for $VPN_INTERFACE..."
  # Use sudo tee to write the rules file, avoids permission issues if script runs as user first
  cat << EOF | sudo tee "$PF_RULES_PATH" > /dev/null
# Default: block all traffic, log first packet
block drop log all

# Allow local loopback traffic (quick skips further processing)
pass quick on lo0 all

# Allow DHCP (necessary for some network configs, often safe to keep commented)
# pass quick inet proto udp from any port 67 to any port 68 keep state
# pass quick inet proto udp from any port 68 to any port 67 keep state

# Allow essential ICMP (like echo requests - ping) for network diagnostics
# Note: Explicitly state 'inet' for icmp-type and 'inet6' for icmp6-type
pass quick inet proto icmp from any to any icmp-type echoreq keep state
pass quick inet6 proto icmp6 from any to any icmp6-type echoreq keep state


# Allow DNS queries (UDP and TCP on port 53) - Essential
# Consider locking down 'to any' if you have specific DNS servers
# Specifying inet/inet6 might be safer, but often inferred correctly for ports.
pass quick inet proto udp to any port 53 keep state
pass quick inet proto tcp to any port 53 keep state
# pass quick inet6 proto udp to any port 53 keep state # Optional: If IPv6 DNS needed
# pass quick inet6 proto tcp to any port 53 keep state # Optional: If IPv6 DNS needed

# Allow WireGuard connection itself to the server (outbound UDP)
# Assuming WireGuard server is IPv4. Add inet6 if server has IPv6 address.
pass out quick inet proto udp to any port $WIREGUARD_PORT keep state
# pass out quick inet6 proto udp to any port $WIREGUARD_PORT keep state # Optional: If IPv6 WG server


# Allow ALL traffic through the dynamically found VPN interface (critical rule)
# This handles both IPv4 and IPv6 over the VPN tunnel implicitly
pass quick on $VPN_INTERFACE all keep state
EOF

  # Verify file creation
  if [ ! -f "$PF_RULES_PATH" ]; then
    echo "❌ Error: Failed to create PF rules file at $PF_RULES_PATH"
    exit 1
  fi
  # Set secure permissions
  sudo chmod 600 "$PF_RULES_PATH"
}

# Fetch public IP address
get_public_ip() {
  echo "🌐 Fetching public IP address from $PUBLIC_IP_SERVICE..."
  # Use curl with a timeout and silent mode (-s)
  local ip
  ip=$(curl -s --max-time 5 "$PUBLIC_IP_SERVICE")

  if [ -z "$ip" ]; then
    echo "⚠️ Warning: Could not fetch public IP address from $PUBLIC_IP_SERVICE."
    echo "N/A" # Return N/A if fetching fails
  else
    echo "$ip"
  fi
}

# Send macOS notification
send_notification() {
  local title="$1"
  local message="$2"
  echo "📨 Sending notification: '$title' - '$message'"
  # Use osascript to send the notification
  osascript -e "display notification \"$message\" with title \"$title\""
}


# VPN connection check function (uses dynamic VPN_INTERFACE)
check_vpn() {
  # Check interface existence
  if ! ifconfig "$VPN_INTERFACE" &>/dev/null; then
    echo "⚠️ VPN is disconnected! (Interface '$VPN_INTERFACE' not found)"
    return 1
  fi

  # Check for IP address on interface (basic check for IPv4)
  if ! ifconfig "$VPN_INTERFACE" | grep -q "inet "; then
    # Also check for IPv6 if IPv4 fails, as some VPNs might only assign IPv6 tunnel IPs
    if ! ifconfig "$VPN_INTERFACE" | grep -q "inet6 "; then
      echo "⚠️ VPN seems disconnected! (No IPv4 or IPv6 address on '$VPN_INTERFACE')"
      return 1
    fi
  fi
  return 0
}


# --- Main Script Logic ---

# Trap interrupt signals for cleanup
trap cleanup SIGINT SIGTERM

# Ensure script runs with root privileges
check_sudo

# Reset firewall before starting
reset_firewall

# Find the target VPN interface
find_vpn_interface
# The VPN_INTERFACE variable is now set globally for the rest of the script

# Print final configuration
echo "📝 Using Configuration:"
echo "  - VPN Interface: $VPN_INTERFACE (Dynamically Found)"
echo "  - WireGuard Port: $WIREGUARD_PORT"
echo "  - Rules File: $PF_RULES_PATH"
echo "  - Public IP Service: $PUBLIC_IP_SERVICE"

# Create the PF rules using the found interface
create_pf_rules

# Enable firewall and load rules
echo "🔒 Activating firewall rules..."
# Enable PF if not already enabled
sudo pfctl -e 2>/dev/null
# Load the rules, print errors if any
# Use -q option to suppress non-error messages like ALTQ notices
sudo pfctl -q -f "$PF_RULES_PATH"
if [ $? -ne 0 ]; then
  echo "❌ Error: Failed to load PF rules from $PF_RULES_PATH"
  # Show the content of the failed rules file for debugging
  echo "--- Content of $PF_RULES_PATH ---"
  sudo cat "$PF_RULES_PATH"
  echo "--- End of Content ---"
  # Show verbose loading attempt for detailed errors
  sudo pfctl -v -n -f "$PF_RULES_PATH" # -n = test syntax without loading
  exit 1
fi

echo "✅ Kill Switch activated. Traffic is now restricted."

# Fetch public IP and send notification
PUBLIC_IP=$(get_public_ip)
NOTIFICATION_TITLE="WireGuard Killswitch Active"
NOTIFICATION_BODY="Killswitch locked to interface $VPN_INTERFACE. Public IP: $PUBLIC_IP"
send_notification "$NOTIFICATION_TITLE" "$NOTIFICATION_BODY"

# Main monitoring loop
echo "👀 VPN connection monitoring started for $VPN_INTERFACE. Press Ctrl+C to stop."
echo "📜 Current firewall rules active:"
sudo pfctl -sr # Show loaded rules concisely

while true; do
  if ! check_vpn; then
    # Optional: Implement action if VPN drops (e.g., re-notify, attempt reconnect?)
    : # No operation, just continue loop
  fi
  sleep 10 # Check every 10 seconds
done
