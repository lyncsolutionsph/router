# Router Configuration Management

This repository contains scripts and configuration files for managing router DHCP and temporal policies.

## Repository Structure

```
router/
├── dhcp/                           # DHCP management scripts
│   ├── cleanup_expired_blocks.sh   # Remove expired device blocks
│   ├── daqtest                     # DAQ testing utilities
│   ├── daqtest-static              # Static DAQ test configuration
│   ├── list_blocked_devices.sh     # List currently blocked devices
│   ├── remove_device_complete.sh   # Complete device removal
│   ├── remove_dhcp_leases_dnsmasq.sh # Remove DHCP leases from dnsmasq
│   └── unblock_device_auto.sh      # Automatic device unblocking
│
├── temporal/                       # Temporal policy management
│   ├── auto_start_backend.sh       # Backend auto-start script
│   ├── backend_stub.py             # Backend stub implementation
│   ├── cleanup_policies.sh         # Policy cleanup script
│   ├── import_hosts.sh             # Host import utility
│   ├── install_temporal.sh         # Temporal installation script
│   ├── net_policies.json           # Network policies configuration
│   ├── policies.json               # General policies configuration
│   ├── Policy.py                   # Policy class implementation
│   ├── requirements.txt            # Python dependencies
│   ├── run_backend.bat             # Windows backend launcher
│   ├── temporal                    # Main temporal binary
│   ├── temporal_policy.py          # Temporal policy implementation
│   └── temporal_policy.state       # Policy state file
│
├── install.sh                      # Installation script
└── version.txt                     # Version information
```

## Installation

### Quick Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/lyncsolutionsph/router.git
   cd router
   ```

2. Run the installation script:
   ```bash
   sudo bash install.sh
   ```

The installation script will:
- Install temporal files to `/usr/local/bin/temporal/`
- Install DHCP scripts to `/usr/local/bin/`
- Set appropriate permissions (755) on all installed files
- Clean up the cloned repository after successful installation

### Manual Installation

If you prefer to install manually:

#### Temporal Files
```bash
sudo mkdir -p /usr/local/bin/temporal
sudo cp temporal/* /usr/local/bin/temporal/
sudo chmod -R 755 /usr/local/bin/temporal/*
```

#### DHCP Files
```bash
sudo cp dhcp/* /usr/local/bin/
sudo chmod 755 /usr/local/bin/cleanup_expired_blocks.sh \
             /usr/local/bin/daqtest \
             /usr/local/bin/daqtest-static \
             /usr/local/bin/list_blocked_devices.sh \
             /usr/local/bin/remove_device_complete.sh \
             /usr/local/bin/remove_dhcp_leases_dnsmasq.sh \
             /usr/local/bin/unblock_device_auto.sh
```

## Components

### DHCP Management (`dhcp/`)

Scripts for managing DHCP leases and device access control:

- **cleanup_expired_blocks.sh**: Automatically removes expired device blocks from the system
- **list_blocked_devices.sh**: Displays a list of all currently blocked devices
- **remove_device_complete.sh**: Completely removes a device from the system including DHCP leases and blocks
- **remove_dhcp_leases_dnsmasq.sh**: Removes DHCP leases from the dnsmasq configuration
- **unblock_device_auto.sh**: Automatically unblocks devices based on policy rules
- **daqtest/daqtest-static**: Device Automated Qualification (DAQ) testing utilities

### Temporal Policy Management (`temporal/`)

Scripts and configurations for time-based policy management:

- **temporal_policy.py**: Main policy engine that enforces time-based access controls
- **Policy.py**: Policy class definition and utilities
- **policies.json**: General policy rules configuration
- **net_policies.json**: Network-specific policy rules
- **import_hosts.sh**: Import host configurations from external sources
- **cleanup_policies.sh**: Clean up expired or invalid policies
- **backend_stub.py**: Backend API stub for testing
- **auto_start_backend.sh**: Automatically starts the backend service

## Usage

### DHCP Scripts

List blocked devices:
```bash
/usr/local/bin/list_blocked_devices.sh
```

Remove a specific device:
```bash
/usr/local/bin/remove_device_complete.sh <device_mac_address>
```

Clean up expired blocks:
```bash
/usr/local/bin/cleanup_expired_blocks.sh
```

### Temporal Policy Management

The temporal policy system runs as a service and automatically enforces time-based access rules defined in the policy configuration files.

Start the temporal policy service (if installed as a systemd service):
```bash
sudo systemctl start temporal-policy
```

Check service status:
```bash
sudo systemctl status temporal-policy
```

## Requirements

- Linux-based operating system
- Root/sudo access
- Python 3.x (for temporal policy scripts)
- dnsmasq (for DHCP management)

### Python Dependencies

For temporal policy management, install Python dependencies:
```bash
cd /usr/local/bin/temporal
pip3 install -r requirements.txt
```

## Configuration

### Policy Configuration

Edit policy files in `/usr/local/bin/temporal/`:
- `policies.json`: General access policies
- `net_policies.json`: Network-specific policies

### DHCP Configuration

DHCP scripts integrate with dnsmasq. Ensure dnsmasq is properly configured on your system.

## Version

Check the installed version:
```bash
cat version.txt
```

Current version: 1.0.0

## Troubleshooting

### Installation Issues

If installation fails:
1. Ensure you have sudo privileges
2. Check that all required directories are accessible
3. Verify Python 3.x is installed for temporal components

### Permission Errors

If you encounter permission errors, verify file permissions:
```bash
ls -la /usr/local/bin/temporal/
ls -la /usr/local/bin/*.sh
```

All scripts should have 755 permissions.

## Support

For issues or questions, please contact the repository maintainer or open an issue on GitHub.

## License

[Add your license information here]
