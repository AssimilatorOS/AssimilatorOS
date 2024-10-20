# Assimilator OS - A small Linux distribution for "assimilating" machines

This small busybox-based Linux powered operating system is meant to allow prepping and imaging systems over a network, either through iPXE boot or booting via USB or lights-out management as an ISO.

The operating system, through symlinks adheres to the FHS, however, borrows from AltimatOS, in that the operating system root is under `/System` and not the traditional `/usr` heirarchy. Additionally, as the system uses BusyBox for its tools, some additional custom tools have been put together to ease using the system and allowing for other future uses.

## Distribution Tools

Assimilator OS currently is designed to use the following first-party tools for certain core OS functions:

| Component | License | Description |
| --- | --- | --- |
| mkinitramfs | [GPLv2](LICENSE) | A replacement initramfs creation tool |
| svcmgr | [GPLv2](LICENSE) | A replacement service manager that works with the simple init daemon that BusyBox ships. This adds run target support, service dependency management, CGroup and Linux Namespace support, and JSON based service description files |
| svcctl | [GPLv2](LICENSE) | A small CLI tool for managing the Assimilator OS Service Manager, including requesting start or stop of requested service |
| initctl | [GPLv2](LICENSE) | A replacement set of tools for managing the simple init daemon in the operating system. This includes a rewrite of the `halt`, `reboot`, and `shutdown` commands as well as the `initctl` tool |

Most of these tools are written in Golang. All of them are licensed under the GNU Public License, version 2.

## Included 3rd-Party Tools

Currently, Assimilator OS uses the following components for the operating system:

| Component | Version | License | URL |
| --- | --- | --- | --- |
| BusyBox | 1.36.1 | [GPLv2](3rdparty/busybox-1.37.0/LICENSE) | https://www.busybox.net/ |
| Linux Kernel | 5.10.226 (LTS) | [GPLv2](3rdparty/linux-5.10.226/COPYING) | https://www.kernel.org/ |
| GNU Grub | 2.12 | [GPLv3](3rdparty/grub-2.12) | https://www.gnu.org/software/grub/ |
| EFI Variables library | 39 | [LGPLv2.1](3rdparty/efivar-39/COPYING) | https://github.com/rhboot/efivar |
| EFI Boot Manager | 18 | [GPLv2](3rdparty/efibootmgr-18/COPYING) | https://github.com/rhboot/efibootmgr |
| Intel Processor Microcode | 20240910 | [Proprietary](3rdparty/Intel-Linux-Processor-Microcode-Data-Files-microcode-20240910/license) | https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files |
| Linux PAM | 1.6.1 | [GPLv2/BSD-3 Clause](3rdparty/Linux-PAM-1.6.1/COPYING) | https://github.com/linux-pam/linux-pam |
| JQ | 1.7.1 | [CC-BY-3.0/MIT](3rdparty/jq-1.7.1/COPYING) | https://jqlang.github.io/jq/ |
| SQLite3 | 3.46.1 | [Public Domain](https://sqlite.org/copyright.html) | https://sqlite.org/index.html |
| Rsync | 3.3.0 | [GPLv3](3rdparty/rsync-3.3.0/COPYING) | https://rsync.samba.org/ |
| GNU Nano Editor | 8.2 | [GPLv3](3rdparty/nano-8.2/COPYING) | https://www.nano-editor.org/ |
| NCurses | 6.5 | [MIT](3rdparty/ncurses-6.5/COPYING) | https://invisible-island.net/ncurses/ |
| Dialog | 1.3 | [LGPLv2.1](3rdparty/dialog-1.3-20240619/COPYING) | https://invisible-island.net/dialog/ |
| XFS Progs | 6.10.1 | [GPLv2](3rdparty/xfsprogs-6.10.1/LICENSES/GPL-2.0) | https://xfs.wiki.kernel.org/ |

Individual 3rd-party components are licensed under their own terms and conditions. This project "vendors" components to ensure that the system is buildable at any time. Periodically, the vendored versions will be replaced with newer versions or replacement libraries and tooling designed for smaller installations.
