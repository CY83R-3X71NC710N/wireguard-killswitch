# WireGuard Kill Switch for macOS

A bash script that creates a kill switch for WireGuard VPN on macOS using PF (Packet Filter). It ensures that your internet traffic only flows through the VPN, preventing any leaks if the VPN connection drops

## Features

- Blocks all traffic when VPN is disconnected
- Allows traffic only through WireGuard VPN interface
- Monitors VPN connection status
- Configurable through environment variables
- Automatic cleanup on script termination
- User-friendly status messages

## Requirements

- macOS operating system
- WireGuard installed
- Administrative privileges (sudo)

## Installation

1. Clone this repository or download the `killswitch.sh` script:

```bash
git clone https://github.com/Alexandrshy/wireguard-killswitch.git

cd wireguard-killswitch
```

2. Make the script executable:
```bash
chmod +x killswitch.sh
```

## Usage

### Basic Usage

Simply run the script:

```bash
./killswitch.sh
```

### Configuration

You can configure the script using environment variables:

- `VPN_INTERFACE`: WireGuard interface name (default: utun4)
- `WIREGUARD_PORT`: WireGuard server port (default: 51820)
- `PF_RULES_PATH`: Path to PF rules file (default: /etc/pf.anchors/wireguard_killswitch)

Example:

```bash
export VPN_INTERFACE=utun4
export WIREGUARD_PORT=51820
export PF_RULES_PATH=/etc/pf.anchors/wireguard_killswitch
```

### Finding WireGuard Interface

To determine which interface your WireGuard VPN is using:

1. First, check all available interfaces:

```bash
ifconfig | grep utun
```

2. Note the current interfaces, then connect to your WireGuard VPN

3. Run the same command again:

```bash
ifconfig | grep utun
```

4. The new utun interface that appears is your WireGuard interface. Example output:
```
Before VPN connection:
utun0: flags=8031<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1490
utun1: flags=8031<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 2000

After VPN connection:
utun0: flags=8031<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1490
utun1: flags=8031<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 2000
utun3: flags=8031<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1690  <- This is your WireGuard interface
```

5. Update the VPN_INTERFACE variable in the script or set it via environment variable:

```bash
export VPN_INTERFACE="utun3"
```

## Automatic Startup Configuration

To make the kill switch start automatically after system reboot, follow these steps:

1. Copy the script to a permanent location:

```bash
sudo cp killswitch.sh /usr/local/sbin/killswitch.sh

sudo chmod +x /usr/local/sbin/killswitch.sh
```

2. Create a launch daemon configuration:

```bash
sudo mkdir -p /Library/LaunchDaemons
```

3. Create the launch daemon file:

```bash
cat << 'EOF' | sudo tee /Library/LaunchDaemons/com.wireguard.killswitch.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wireguard.killswitch</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/sbin/killswitch.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/killswitch.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/killswitch.error.log</string>
</dict>
</plist>
EOF
```

4. Set correct permissions:

```bash
sudo chown root:wheel /Library/LaunchDaemons/com.wireguard.killswitch.plist
sudo chmod 644 /Library/LaunchDaemons/com.wireguard.killswitch.plist
```

5. Load the launch daemon:

```bash
sudo launchctl load -w /Library/LaunchDaemons/com.wireguard.killswitch.plist
```

6. Verify the launch daemon is running:

```bash
sudo launchctl list | grep com.wireguard.killswitch
```

### Managing Autostart

- To stop the service:

```bash
launchctl unload /Library/LaunchDaemons/com.wireguard.killswitch.plist
```

- To disable autostart:

```bash
launchctl unload /Library/LaunchDaemons/com.wireguard.killswitch.plist
```

## Troubleshooting

### Logs
Check the log files for any issues:

```bash
tail -f /var/log/killswitch.log
tail -f /var/log/killswitch.error.log
```

### Common Issues

1. **Script doesn't start automatically**
   - Check permissions: `chmod +x /path/to/your/killswitch.sh`
   - Verify the path in the plist file
   - Check log files for errors

2. **Permission denied errors**
   - Ensure the script has proper ownership: `sudo chown root:wheel /path/to/your/killswitch.sh`
   - Make sure the script is executable: `chmod +x /path/to/your/killswitch.sh`

## Security Considerations

- The script requires root privileges to modify firewall rules
- All traffic is blocked if the VPN connection drops
- DNS queries are allowed to facilitate VPN connection

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details
