/*
 *  GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2013  Free Software Foundation, Inc.
 *
 *  GRUB is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  GRUB is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with GRUB.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef GRUB_ARM64_LINUX_HEADER
#define GRUB_ARM64_LINUX_HEADER 1

#include <grub/types.h>
#include <grub/efi/pe32.h>

#define GRUB_LINUX_ARM64_MAGIC_SIGNATURE 0x644d5241 /* 'ARM\x64' */

struct grub_arm64_linux_pe_header
{
  grub_uint32_t magic;
  struct grub_pe32_coff_header coff;
  struct grub_pe64_optional_header opt;
};

#if defined(__aarch64__)
# define GRUB_LINUX_ARMXX_MAGIC_SIGNATURE GRUB_LINUX_ARM64_MAGIC_SIGNATURE
# define GRUB_PE32_PEXX_MAGIC GRUB_PE32_PE64_MAGIC
# define grub_armxx_linux_pe_header grub_arm64_linux_pe_header
#endif

#endif /* ! GRUB_ARM64_LINUX_HEADER */
