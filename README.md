# [RELIANOID Load Balancer](https://www.relianoid.com)
This is the repository of **RELIANOID Load Balancer** Community Edition (**ZEVENET Load Balancer** & **Zen Load Balancer** CE next generation) and it'll guide you to install a development and testing instance of load balancer.

## Repository Contents
In this repository you'll find the source code usually placed into the folder `/usr/local/relianoid/` with the following structure:
- **app/**: Applications, binaries and libraries that RELIANOID Load Balancer requires.
- **bin/**: Additional application binaries directory. 
- **backups/**: Default folder where the configuration backups will be placed.
- **config/**: Default folder where the load balancing services, health checks and network configuration files will be placed.
- **etc/**: Some system files to configure RELIANOID Load Balancer services.
- **lib/**: Folder where RELIANOID funcionality library is located.
- **share/**: Folder for templates and other data.
- **www/**: Backend API source files of RELIANOID Load Balancer.
- *other*: License and this readme information.
And `/usr/share/perl5/Relianoid` with the entire RELIANOID backend core.

## RELIANOID Load Balancer Installation

Currently, there is only available package for Debian 12 Bookworm, the installation is not supported out of this operating system.

There are two options to deploy a RELIANOID load balancer: The first is deploying the RELIANOID CE ISO, and the other is deploying a Debian 12 Bookworm image and installing RELIANOID with its dependencies.

### ISO

RELIANOID Community Edition ISO is a Debian 12 Bookworm template with RELIANOID already installed. It can be got from the following link, clicking on the "Download ISO image" button.

https://www.relianoid.com/products/community/


### Installation on Debian 12 Bookworm

If you prefer install RELIANOID yourself, you should get a Debian ISO installable from [debian.org](https://www.debian.org/distrib/). This installation process has been only tested with the 64 bits version.

Please, take into account these **requirements** before installing the load balancer:

1. Uses 1,6 GB of disk space after installation.

2. Install a fresh and basic Debian 12 Bookworm (64 bits) system with *openssh* and the basic system tools package recommended during the distribution installation.

3. Configure the load balancer with a static IP address. RELIANOID Load Balancer doesn't support DHCP yet.

4. Configure the *apt* repositories in order to be able to install some dependencies.


This git repository only contains the source code, the installable packages based in this code are updated in our RELIANOID APT repos, you can use them configuring your Debian 12 Bookworm system as follows:

```
root@noid-ce-01# echo "deb http://repo.relianoid.com/ce/v7 bookworm main" > /etc/apt/sources.list.d/relianoid.list
root@noid-ce-01# wget -O - https://repo.relianoid.com/public/relianoid.asc > /etc/apt/trusted.gpg.d/relianoid.asc
```

Now, update the local APT database

```
root@noid-ce-01# apt-get update
```

And finally, install RELIANOID load balancer Community Edition

```
root@noid-ce-01# apt-get install relianoid relianoid-gui
```

## Updates

Please use the RELIANOID APT repo in order to check if updates are available.


## How to Contribute
You can contribute with the evolution of the RELIANOID Load Balancer in a wide variety of ways:

- **Creating content**: Documentation in the [GitHub project wiki](https://github.com/relianoid), doc translations, documenting source code, etc.
- **Help** to other users through the mailing lists.
- **Reporting** and **Resolving Bugs** from the [GitHub project Issues](https://github.com/relianoid).
- **Development** of new features.

### Reporting Bugs
Please use the [GitHub project Issues](https://github.com/relianoid) to report any issue or bug with the software. Try to describe the problem and a way to reproduce it. It'll be useful to attach the service and network configurations as well as system and services logs.

### Development & Resolving Bugs
In order to commit any change, as new features, bug fix or improvement, just perform a `git clone` of the repository, `git add` when all the changes has been made and `git commit` when you're ready to send the change.

During the submit, please ensure that every change is associated to a *logical change* in order to be easily identified every change.

In the commit description please use the following format:
```
[CATEGORY] CHANGE_SHORT_DESCRIPTION

OPTIONAL_LONGER_DESCRIPTION

SIGNED_OFFS

MODIFIED_FILES
```

Where:
- `CATEGORY` is either: **Bugfix** for resolving bugs or issues, **Improvement** for enhancements of already implemented features or **New Feature** for new developments that provides a new feature not implemented before.
- `CHANGE_SHORT_DESCRIPTION` is a brief description related with the change applied and allows to identify easily such modification. If it's related to a bug included in the Issues section it's recommended to include the identification reference for such bug.
- `OPTIONAL_LONGER_DESCRIPTION` is an optional longer description to explain details about the change applied.
- `SIGNED_OFFS` is the `Signed-off-by` entry where the username followed by the email can be placed.
- `MODIFIED_FILES` are the list of files that hace been modified, created or deleted with the commit.

Usually, executing `git commit -a -s` will create the fields described above.

Finally, just execute a `git push` and request a pull of your changes. In addition, you can use `git format-patch` to create your patches and send them through the official distribution list.

### Creating & Updating Documentation or Translations
In the official [GitHub wiki](https://github.com/relianoid) there is available a list of pages and it's translations. Please clone the wiki, apply your changes and request a pull in order to be applied.

### Community forum and support
For RELIANOID community discussions, announcements and support there is a forum at [RELIANOID Community Support](https://www.relianoid.com/community/support/).

## [www.relianoid.com](https://www.relianoid.com)
