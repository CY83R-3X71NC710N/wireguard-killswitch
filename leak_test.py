import requests
import time
import os
import socket

def get_public_ip():
    try:
        response = requests.get("https://ipinfo.io/ip", timeout=2)
        response.raise_for_status()
        return response.text.strip()
    except requests.exceptions.RequestException as e:
        print(f"Error getting public IP from ipinfo.io: {e}")
        return None

def get_local_ip():
    try:
        hostname = socket.gethostname()
        local_ip = socket.gethostbyname(hostname)
        return local_ip
    except socket.gaierror:
        return None

local_network_ip = get_local_ip()
vpn_active = False  # You'll need to manage this based on your testing
check_interval = 0.1

print("Starting AGGRESSIVE CONTINUOUS IP Monitor (using ipinfo.io). Connect to VPN now.")

try:
    while True:
        current_public_ip = get_public_ip()

        if current_public_ip:
            print(f"Current public IP: {current_public_ip}")
            if not vpn_active and current_public_ip == local_network_ip:
                notification_title = "Internet (No VPN) (CONTINUOUS)"
                notification_body = f"Public IP is your local network IP: {current_public_ip}"
                os.system(f'osascript -e \'display notification "{notification_body}" with title "{notification_title}" sound name "Sosumi"\'')
                vpn_active = False # Ensure vpn_active reflects the state
            elif vpn_active and current_public_ip == local_network_ip:
                notification_title = "POTENTIAL VPN LEAK DETECTED! (CONTINUOUS)"
                notification_body = f"WARNING! Public IP has reverted to local: {current_public_ip}"
                os.system(f'osascript -e \'display notification "{notification_body}" with title "{notification_title}" sound name "Glass"\'')
                vpn_active = False # Ensure vpn_active reflects the state
            elif vpn_active and current_public_ip != local_network_ip:
                # Assuming still on VPN
                pass
            elif not vpn_active and current_public_ip != local_network_ip:
                # Public IP is changing while not on VPN (could be normal network behavior)
                pass
        else:
            print("Could not retrieve public IP.")

        time.sleep(check_interval)

except KeyboardInterrupt:
    print("\nStopping CONTINUOUS IP Monitor.")
