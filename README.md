# Assimilator OS - A small Linux distribution for "assimilating" machines

This small busybox-based Linux powered operating system is meant to allow prepping and imaging systems over a network, either through iPXE boot or booting via USB or lights-out management as an ISO.

The operating system, through symlinks adheres to the FHS, however, borrows from AltimatOS, in that the operating system root is under `/System` and not the traditional `/usr` heirarchy. Additionally, as the system uses BusyBox for its tools, some additional custom tools have been put together to ease using the system and allowing for other future uses.

## Included Tools

Currently, Assimilator OS uses the following components for the operating system:

| Component | Version |
| --- | --- |
| BusyBox | 1.36.1 |
| Linux Kernel | 5.10.226 (LTS) |
| GNU Grub | 2.12 |
| JQ | 1.7.1 |
| SQLite3 | 3.46.1 |
| Rsync | 3.3.0 |
| PartClone | 0.3.32 |
| GNU Nano Editor | 8.2 |
| Dialog | 1.3 |
| XFS Progs | 6.9.0 |
