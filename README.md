# Assimilator OS - A small Linux distribution for "assimilating" machines

This small busybox-based Linux powered operating system is meant to allow prepping and imaging systems over a network, either through iPXE boot or booting via USB or lights-out management as an ISO.

The operating system, through symlinks adheres to the FHS, however, borrows from AltimatOS, in that the operating system root is under `/System` and not the traditional `/usr` heirarchy. Additionally, as the system uses BusyBox for its tools, some additional custom tools have been put together to ease using the system and allowing for other future uses.

## Included Tools

Currently, Assimilator OS uses the following components for the operating system:

| Component | Version | License | URL |
| --- | --- | --- | --- |
| BusyBox | 1.36.1 | [GPLv2](3rdparty/busybox-1.36.1/LICENSE) | https://www.busybox.net/ |
| Linux Kernel | 5.10.226 (LTS) | [GPLv2](3rdparty/linux-5.10.226/COPYING) | https://www.kernel.org/ |
| GNU Grub | 2.12 | [GPLv3](3rdparty/grub-2.12) | https://www.gnu.org/software/grub/ |
| EFI Variables library | 39 | [LGPLv2.1](3rdparty/efivar-39/COPYING) | https://github.com/rhboot/efivar |
| EFI Boot Manager | 18 | [GPLv2](3rdparty/efibootmgr-18/COPYING) | https://github.com/rhboot/efibootmgr |
| Linux PAM | 1.6.1 | [GPLv2/BSD-3 Clause](3rdparty/Linux-PAM-1.6.1/COPYING) | https://github.com/linux-pam/linux-pam |
| JQ | 1.7.1 | | |
| SQLite3 | 3.46.1 | | |
| Rsync | 3.3.0 | | |
| PartClone | 0.3.32 | | |
| GNU Nano Editor | 8.2 | | |
| Dialog | 1.3 | | |
| XFS Progs | 6.9.0 | | |

Individual 3rd-party components are licensed under their own terms and conditions. This project "vendors" components to ensure that the system is buildable at any time. Periodically, the vendored versions will be replaced with newer versions or replacement libraries and tooling designed for smaller installations.
