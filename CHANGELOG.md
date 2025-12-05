# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

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

### Documentation
- Comprehensive README with installation instructions
- Repository structure documentation
- Usage examples and troubleshooting guide

---

## [Unreleased]

### Planned
- Enhanced logging and monitoring capabilities
- Web-based policy management interface
- Multi-router synchronization support
- Extended DAQ testing profiles

---

## Version History

- **1.0.2** - Current stable release
- **1.0.1** - Internal testing version
- **1.0.0** - Initial release

---

## Contributing

For contribution guidelines and version update procedures, please contact the repository maintainer.

## Support

For issues, questions, or feature requests, please open an issue on GitHub or contact [LYNC Solutions PH](https://github.com/lyncsolutionsph).
