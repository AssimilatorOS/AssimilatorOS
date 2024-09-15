# Assimilator OS - A small Linux distribution for "assimilating" machines

This small busybox-based Linux powered operating system is meant to allow prepping and imaging systems over a network, either through iPXE boot or booting via USB or lights-out management as an ISO.

The operating system, through symlinks adheres to the FHS, however, borrows from AltimatOS, in that the operating system root is under `/System` and not the traditional `/usr` heirarchy. Additionally, as the system uses BusyBox for its tools, some additional custom tools have been put together to ease using the system and allowing for other future uses.

## Included Tools

Currently, Assimilator OS uses the following components for the operating system:

- BusyBox
- The Linux Kernel
- GNU Grub v2 Bootloader
- JQ
- SQLite3
- Rsync
- PartClone
- GNU Nano Editor
- XFS Progs
