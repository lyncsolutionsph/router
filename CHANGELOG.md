## [1.0.2] - 2025-12-05

### Added
- DHCP management scripts for device access control
- Temporal policy management system for time-based network access
- Automated installation script (`install.sh`)
- Device Automated Qualification (DAQ) testing utilities

### DHCP Features
- `cleanup_expired_blocks.sh` - Automatic cleanup of expired device blocks
- `list_blocked_devices.sh` - List all currently blocked devices
- `remove_device_complete.sh` - Complete device removal (leases + blocks)
- `remove_dhcp_leases_dnsmasq.sh` - DHCP lease management for dnsmasq
- `unblock_device_auto.sh` - Policy-based automatic device unblocking

### Temporal Policy Features
- Time-based access control enforcement engine
- Policy configuration via JSON files (`policies.json`, `net_policies.json`)
- Backend API stub for testing
- Automatic backend service startup
- Host import utilities
- Policy cleanup automation




