# [RELIANOID Load Balancer Community Edition](https://www.relianoid.com)

![SourceForge Downloads](https://img.shields.io/sourceforge/dt/relianoid?label=SourceForge%20downloads)
![GitHub Downloads](https://img.shields.io/github/downloads/relianoid/adc-loadbalancer/total?label=GitHub%20downloads)
![GitHub Release Date](https://img.shields.io/github/release-date/relianoid/adc-loadbalancer)
![GitHub Release](https://img.shields.io/github/v/release/relianoid/adc-loadbalancer)
![Static Badge](https://img.shields.io/badge/perl-5.36-blue)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

Open-source load balancer that makes easy to make your websites and services always available, more secure and faster.

It does this by **sharing traffic** between multiple servers and **keeping your services running smoothly** even if one server goes down.

It is designed to be easy to use, with a simple web interface that lets you manage everything without needing advanced technical skills.

**Features**:

- Load balancing backends: Layer 4, HTTP and HTTPS.
- Load balancing algorithms: round-robin, least connections and others.
- HTTPS certificates and Let's Encrypt support.
- Monitoring of backend servers health status.
- Monitoring, statistics and SNMP suport.
- VLAN networking support.
- Stateless cluster support.
- Backups.

## Getting Started

- Download the latest ISO image at [SourceForge](https://sourceforge.net/projects/relianoid/files/latest/download) or [Github](https://github.com/relianoid/adc-loadbalancer/releases/latest).
- [Installation guide](https://www.relianoid.com/resources/knowledge-base/community-edition-v7-administration-guide/ce-v7-installation/).


### Requirements

- At least 512 MB of RAM is recommended.
- At least 4 GB of disk is recommended. Uses 1.6 GB after install.


## Support

- [Knowledge base](https://www.relianoid.com/resources/knowledge-base/)
  - [Community Edition](https://www.relianoid.com/resources/knowledge-base/community-edition/)
    - [Administration guide](https://www.relianoid.com/resources/knowledge-base/community-edition-v7-administration-guide/)
  - [HOWTOs](https://www.relianoid.com/resources/knowledge-base/howtos/)
  - [Troubleshooting](https://www.relianoid.com/resources/knowledge-base/troubleshooting/)
  - [API Reference](https://www.relianoid.com/apidoc/v4.0/)
- [Community support forum](https://www.relianoid.com/community/support/)

[Professional support](https://www.relianoid.com/services/support/) is also avalable.


## Contributing

- Before reporting a new issue, try to make sure it's not already in our knowledge base or is already reported in the forum.
- The best way to get your bug fixed is to provide a reduced test case.

### Project Structure

- **DEBIAN/**: Debian package files.
- **etc/**: System services and configuration files.
- **usr/share/perl5/**: Perl library.
- **usr/local/relianoid/**: Commands, configuration and data.
  - **api-model/**: API Specification files.
  - **app/**: Files to suppport the use dependencies, like Let's Encrypt or clustering via ucarp.
  - **bin/**: Relianoid commands.
  - **backups/**: Default directory where the configuration backups will be placed.
  - **config/**: Default directory where the load balancing services, health checks and network configuration files will be placed.
  - **share/**: Directory for templates and other data.
  - **www/**: API and web interface files.


## License

See [license.txt](https://github.com/relianoid/adc-loadbalancer/blob/master/usr/local/relianoid/license.txt).


---


More info at https://www.relianoid.com
