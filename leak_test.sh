import requests
import time
import os

def get_public_ip():
    try:
        response = requests.get("https://api.ipify.org", timeout=5)
        response.raise_for_status()
        return response.text
    except requests.exceptions.RequestException as e:
        print(f"Error getting IP: {e}")
        return None

vpn_active = True  # You'd need a way to dynamically track this
previous_ip = None

while True:
    current_ip = get_public_ip()
    if current_ip and previous_ip and current_ip != previous_ip and vpn_active:
        os.system(f'osascript -e \'display notification "Potential Kill Switch Failure! IP address changed to: {current_ip}" with title "VPN Monitor"\'')
    previous_ip = current_ip
    time.sleep(10) # Check every 10 seconds
