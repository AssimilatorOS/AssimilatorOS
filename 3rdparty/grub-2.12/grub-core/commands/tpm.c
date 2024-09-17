/*
 *  GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2018  Free Software Foundation, Inc.
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
 *
 *  Core TPM support code.
 */

#include <grub/err.h>
#include <grub/i18n.h>
#include <grub/misc.h>
#include <grub/mm.h>
#include <grub/tpm.h>
#include <grub/term.h>
#include <grub/verify.h>
#include <grub/dl.h>
#include <grub/extcmd.h>
#ifdef GRUB_MACHINE_EFI
#include <grub/tpm2/tpm2.h>
#include <grub/efi/efi.h>
#endif

GRUB_MOD_LICENSE ("GPLv3+");

static grub_err_t
grub_tpm_verify_init (grub_file_t io,
		      enum grub_file_type type __attribute__ ((unused)),
		      void **context, enum grub_verify_flags *flags)
{
  *context = io->name;
  *flags |= GRUB_VERIFY_FLAGS_SINGLE_CHUNK;
  return GRUB_ERR_NONE;
}

static grub_err_t
grub_tpm_verify_write (void *context, void *buf, grub_size_t size)
{
  grub_err_t status = grub_tpm_measure (buf, size, GRUB_BINARY_PCR, context);

  if (status == GRUB_ERR_NONE)
    return GRUB_ERR_NONE;

  grub_dprintf ("tpm", "Measuring buffer failed: %d\n", status);
  return grub_is_tpm_fail_fatal () ? status : GRUB_ERR_NONE;
}

static grub_err_t
grub_tpm_verify_string (char *str, enum grub_verify_string_type type)
{
  const char *prefix = NULL;
  char *description;
  grub_err_t status;

  switch (type)
    {
    case GRUB_VERIFY_KERNEL_CMDLINE:
      prefix = "kernel_cmdline: ";
      break;
    case GRUB_VERIFY_MODULE_CMDLINE:
      prefix = "module_cmdline: ";
      break;
    case GRUB_VERIFY_COMMAND:
      prefix = "grub_cmd: ";
      break;
    }
  description = grub_malloc (grub_strlen (str) + grub_strlen (prefix) + 1);
  if (!description)
    return grub_errno;
  grub_memcpy (description, prefix, grub_strlen (prefix));
  grub_memcpy (description + grub_strlen (prefix), str,
	       grub_strlen (str) + 1);
  status =
    grub_tpm_measure ((unsigned char *) str, grub_strlen (str),
		      GRUB_STRING_PCR, description);
  grub_free (description);
  if (status == GRUB_ERR_NONE)
    return GRUB_ERR_NONE;

  grub_dprintf ("tpm", "Measuring string %s failed: %d\n", str, status);
  return grub_is_tpm_fail_fatal () ? status : GRUB_ERR_NONE;
}

struct grub_file_verifier grub_tpm_verifier = {
  .name = "tpm",
  .init = grub_tpm_verify_init,
  .write = grub_tpm_verify_write,
  .verify_string = grub_tpm_verify_string,
};

static const struct grub_arg_option grub_tpm_record_pcrs_options[] =
  {
    {
      .longarg  = "efivar",
      .shortarg = 'E',
      .flags    = 0,
      .arg      = NULL,
      .type     = ARG_TYPE_STRING,
      .doc      =
        N_("The EFI variable to publish the PCRs to (default GrubPcrSnapshot)"),
    },

    {0, 0, 0, 0, 0, 0}
  };

#ifdef GRUB_MACHINE_EFI

/*
 * Preserve current PCR values and record them to an EFI variable
 */
#define GRUB2_PCR_BITMASK_DEFAULT	((1 << 16) - 1)
#define GRUB2_PCR_BITMASK_ALL		((1 << 24) - 1)

static grub_err_t
grub_tpm_parse_pcr_index (const char *word, const char **end_ret, unsigned int *index)
{
  const char *end;

  if (!grub_isdigit (word[0]))
    return GRUB_ERR_BAD_NUMBER;

  *index = grub_strtoul(word, &end, 0);
  if (*index > 32)
    return GRUB_ERR_BAD_NUMBER;

  *end_ret = end;
  return GRUB_ERR_NONE;
}

static grub_err_t
grub_tpm_parse_pcr_list (const char *arg, grub_uint32_t *bitmask)
{
  const char *word, *end;
  unsigned int index, last_index = 0;

  if (!grub_strcmp (arg, "all"))
    {
      *bitmask = GRUB2_PCR_BITMASK_ALL;
      return GRUB_ERR_NONE;
    }

  word = arg;
  while (1)
    {
      if (grub_tpm_parse_pcr_index (word, &end, &index))
	goto bad_pcr_index;

      if (*end == '-')
	{
          if (grub_tpm_parse_pcr_index (end + 1, &end, &last_index) || last_index < index)
	    goto bad_pcr_index;

	  while (index <= last_index)
	    *bitmask |= (1 << (index++));
	}
      else
	*bitmask |= (1 << index);

      if (*end == '\0')
	break;

      if (*end != ',')
	goto bad_pcr_index;

       word = end + 1;
    }

  return GRUB_ERR_NONE;

bad_pcr_index:
  return grub_error (GRUB_ERR_BAD_ARGUMENT, N_("cannot parse PCR list \"%s\""), arg);
}

static inline unsigned int
nbits(grub_uint32_t mask)
{
  unsigned int r = 0;

  for (; mask != 0; mask >>= 1)
    r += (mask & 1);
  return r;
}

static grub_err_t
grub_tpm_snapshot_pcrs (grub_uint32_t pcr_bitmask, const char *algo,
	       		void **buffer_ret, grub_size_t *size_ret)
{
  char *buffer;
  grub_size_t size = 65536;
  unsigned int wpos = 0;
  grub_uint8_t pcr;

  buffer = grub_malloc (size);
  for (pcr = 0; pcr < 32; ++pcr)
    {
      struct grub_tpm_digest *d;
      unsigned int need, k;

      if (!(pcr_bitmask & (1 << pcr)))
	continue;

      d = grub_tpm_read_pcr (pcr, algo);
      if (d == NULL)
        {
	  grub_error (GRUB_ERR_BAD_DEVICE, N_("unable to read PCR %d from TPM"), pcr);
	  continue;
        }

      /* We need room for the PCR index, 2 spaces, newline, NUL. 16 should be enough. */
      need = 16 + grub_strlen(d->algorithm) + 2 * d->size;
      if (wpos + need > size)
        {
	  buffer = grub_realloc (buffer, size + need);
	  if (buffer == NULL)
	    return grub_error (GRUB_ERR_OUT_OF_MEMORY, N_("Not enough memory when dumping PCR registers"));
        }

      grub_snprintf (buffer + wpos, size - wpos, "%02d %s ", pcr, d->algorithm);
      wpos = grub_strlen(buffer);

      for (k = 0; k < d->size; ++k)
        {
	  grub_snprintf (buffer + wpos, size - wpos, "%02x", d->value[k]);
	  wpos += 2;
        }

      buffer[wpos++] = '\n';
      buffer[wpos] = '\0';

      grub_tpm_digest_free (d);
    }

  *buffer_ret = buffer;
  *size_ret = wpos;

  return GRUB_ERR_NONE;
}

static grub_err_t
grub_tpm_write_pcrs_to_efi (void *data, grub_size_t size, const char *var_name)
{
  grub_guid_t vendor_guid = { 0x7ce323f2, 0xb841, 0x4d30, { 0xa0, 0xe9, 0x54, 0x74, 0xa7, 0x6c, 0x9a, 0x3f }};
  grub_err_t rc;

  rc = grub_efi_set_variable_with_attributes(var_name, &vendor_guid,
                                              data, size,
                                              GRUB_EFI_VARIABLE_BOOTSERVICE_ACCESS | GRUB_EFI_VARIABLE_RUNTIME_ACCESS);

  if (rc)
    return grub_error (GRUB_ERR_BAD_DEVICE, N_("Failed to publish PCR snapshot to UEFI variable %s"), var_name);

  return GRUB_ERR_NONE;
}

static grub_err_t
grub_tpm_record_pcrs (grub_extcmd_context_t ctxt, int argc, char **args)
{
  struct grub_arg_list *state = ctxt->state;
  grub_uint32_t pcr_bitmask = 0;
  const char *efivar;
  void *buffer = NULL;
  grub_size_t size = 0;
  int n, rv = 1;

  /* To prevent error: unable to read PCR from TPM, if no TPM device available */
  if (!grub_tpm_present())
    return GRUB_ERR_NONE;

  if (argc == 0)
    pcr_bitmask = GRUB2_PCR_BITMASK_DEFAULT;
  else
    {
      for (n = 0; n < argc; ++n)
	if (grub_tpm_parse_pcr_list (args[n], &pcr_bitmask))
	  return 1;
    }

  if (grub_tpm_snapshot_pcrs (pcr_bitmask, NULL, &buffer, &size))
    goto out;

  if (state[0].set)
    efivar = state[0].arg;
  else
    efivar = "GrubPcrSnapshot";

  if (grub_tpm_write_pcrs_to_efi (buffer, size, efivar))
    goto out;

  rv = 0;

out:
  if (buffer)
    grub_free (buffer);
  return rv;
}

#else

static grub_err_t
grub_tpm_record_pcrs (grub_extcmd_context_t ctxt __attribute__((unused)),
    int argc __attribute__((unused)),
    char **args __attribute__((unused)))
{
  return GRUB_ERR_NONE;
}

#endif

static grub_extcmd_t cmd;

GRUB_MOD_INIT (tpm)
{
  cmd = grub_register_extcmd ("tpm_record_pcrs", grub_tpm_record_pcrs, 0,
			      N_("LIST_OF_PCRS"),
			      N_("Snapshot one or more PCR values and record them in an EFI variable."),
			      grub_tpm_record_pcrs_options);
  /*
   * Even though this now calls ibmvtpm's grub_tpm_present() from GRUB_MOD_INIT(),
   * it does seem to call it late enough in the initialization sequence so
   * that whatever discovered "device nodes" before this GRUB_MOD_INIT() is
   * called, enables the ibmvtpm driver to see the device nodes.
   */
  if (!grub_tpm_present())
    return;
  grub_verifier_register (&grub_tpm_verifier);
}

GRUB_MOD_FINI (tpm)
{
  grub_unregister_extcmd (cmd);
  if (!grub_tpm_present())
    return;
  grub_verifier_unregister (&grub_tpm_verifier);
}
