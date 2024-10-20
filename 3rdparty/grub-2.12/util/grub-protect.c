/*
 *  GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2022 Microsoft Corporation
 *  Copyright (C) 2023 SUSE LLC
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

#include <config.h>

#include <errno.h>
#include <fcntl.h>
#include <libtasn1.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <grub/crypto.h>
#include <grub/emu/getroot.h>
#include <grub/emu/hostdisk.h>
#include <grub/emu/misc.h>
#include <grub/tpm2/buffer.h>
#include <grub/tpm2/internal/args.h>
#include <grub/tpm2/mu.h>
#include <grub/tpm2/tcg2.h>
#include <grub/tpm2/tpm2.h>
#include <grub/util/misc.h>

#pragma GCC diagnostic ignored "-Wmissing-prototypes"
#pragma GCC diagnostic ignored "-Wmissing-declarations"
#include <argp.h>
#pragma GCC diagnostic error "-Wmissing-prototypes"
#pragma GCC diagnostic error "-Wmissing-declarations"

#include "progname.h"

/* Unprintable option keys for argp */
typedef enum grub_protect_opt
{
  /* General */
  GRUB_PROTECT_OPT_ACTION      = 'a',
  GRUB_PROTECT_OPT_PROTECTOR   = 'p',
  /* TPM2 */
  GRUB_PROTECT_OPT_TPM2_DEVICE = 0x100,
  GRUB_PROTECT_OPT_TPM2_PCRS,
  GRUB_PROTECT_OPT_TPM2_ASYMMETRIC,
  GRUB_PROTECT_OPT_TPM2_BANK,
  GRUB_PROTECT_OPT_TPM2_SRK,
  GRUB_PROTECT_OPT_TPM2_KEYFILE,
  GRUB_PROTECT_OPT_TPM2_OUTFILE,
  GRUB_PROTECT_OPT_TPM2_EVICT,
  GRUB_PROTECT_OPT_TPM2_TPM2KEY
} grub_protect_opt;

/* Option flags to keep track of specified arguments */
typedef enum grub_protect_arg
{
  /* General */
  GRUB_PROTECT_ARG_ACTION          = 1 << 0,
  GRUB_PROTECT_ARG_PROTECTOR       = 1 << 1,
  /* TPM2 */
  GRUB_PROTECT_ARG_TPM2_DEVICE     = 1 << 2,
  GRUB_PROTECT_ARG_TPM2_PCRS       = 1 << 3,
  GRUB_PROTECT_ARG_TPM2_ASYMMETRIC = 1 << 4,
  GRUB_PROTECT_ARG_TPM2_BANK       = 1 << 5,
  GRUB_PROTECT_ARG_TPM2_SRK        = 1 << 6,
  GRUB_PROTECT_ARG_TPM2_KEYFILE    = 1 << 7,
  GRUB_PROTECT_ARG_TPM2_OUTFILE    = 1 << 8,
  GRUB_PROTECT_ARG_TPM2_EVICT      = 1 << 9,
  GRUB_PROTECT_ARG_TPM2_TPM2KEY    = 1 << 10
} grub_protect_arg_t;

typedef enum grub_protect_protector
{
  GRUB_PROTECT_TYPE_ERROR,
  GRUB_PROTECT_TYPE_TPM2
} grub_protect_protector_t;

typedef enum grub_protect_action
{
  GRUB_PROTECT_ACTION_ERROR,
  GRUB_PROTECT_ACTION_ADD,
  GRUB_PROTECT_ACTION_REMOVE
} grub_protect_action_t;

struct grub_protect_args
{
  grub_protect_arg_t args;
  grub_protect_action_t action;
  grub_protect_protector_t protector;

  const char *tpm2_device;
  grub_uint8_t tpm2_pcrs[TPM_MAX_PCRS];
  grub_uint8_t tpm2_pcr_count;
  TPM_ALG_ID tpm2_asymmetric;
  TPM_KEY_BITS rsa_bits;
  TPM_ECC_CURVE ecc_curve;
  TPM_ALG_ID tpm2_bank;
  TPM_HANDLE tpm2_srk;
  const char *tpm2_keyfile;
  const char *tpm2_outfile;
  int tpm2_evict;
  int tpm2_tpm2key;
};

static struct argp_option grub_protect_options[] =
  {
    /* Top-level options */
   {
      .name  = "action",
      .key   = 'a',
      .arg   = "add|remove",
      .flags = 0,
      .doc   =
	N_("Add or remove a key protector to or from a key."),
      .group = 0
    },
    {
      .name  = "protector",
      .key   = 'p',
      .arg   = "tpm2",
      .flags = 0,
      .doc   =
	N_("Key protector to use (only tpm2 is currently supported)."),
      .group = 0
    },
    /* TPM2 key protector options */
    {
      .name = "tpm2-device",
      .key   = GRUB_PROTECT_OPT_TPM2_DEVICE,
      .arg   = "FILE",
      .flags = 0,
      .doc   =
	N_("Path to the TPM2 device (default is /dev/tpm0)."),
      .group = 0
    },
    {
      .name = "tpm2-pcrs",
      .key   = GRUB_PROTECT_OPT_TPM2_PCRS,
      .arg   = "0[,1]...",
      .flags = 0,
      .doc   =
	N_("Comma-separated list of PCRs used to authorize key release "
	   "(e.g., '7,11', default is 7."),
      .group = 0
    },
    {
      .name = "tpm2-bank",
      .key  = GRUB_PROTECT_OPT_TPM2_BANK,
      .arg   = "ALG",
      .flags = 0,
      .doc   =
	N_("Bank of PCRs used to authorize key release: "
	   "SHA1, SHA256 (default), or SHA512."),
      .group = 0
    },
    {
      .name = "tpm2-keyfile",
      .key   = GRUB_PROTECT_OPT_TPM2_KEYFILE,
      .arg   = "FILE",
      .flags = 0,
      .doc   =
	N_("Path to a file that contains the cleartext key to protect."),
      .group = 0
    },
    {
      .name = "tpm2-outfile",
      .key   = GRUB_PROTECT_OPT_TPM2_OUTFILE,
      .arg   = "FILE",
      .flags = 0,
      .doc   =
	N_("Path to the file that will contain the key after sealing (must be "
	   "accessible to GRUB during boot)."),
      .group = 0
    },
    {
      .name = "tpm2-srk",
      .key   = GRUB_PROTECT_OPT_TPM2_SRK,
      .arg   = "NUM",
      .flags = 0,
      .doc   =
	N_("The SRK handle if the SRK is to be made persistent."),
      .group = 0
    },
    {
      .name = "tpm2-asymmetric",
      .key   = GRUB_PROTECT_OPT_TPM2_ASYMMETRIC,
      .arg   = "TYPE",
      .flags = 0,
      .doc   =
	N_("The type of SRK: RSA (RSA2048), RSA3072, RSA4096, "
	   "ECC (ECC_NIST_P256), ECC_NIST_P384, ECC_NIST_P521, "
	   "ECC_BN_P256, ECC_BN_P638, and ECC_SM2_P256. "
	   "(default is RSA2048)"),
      .group = 0
    },
    {
      .name = "tpm2-evict",
      .key   = GRUB_PROTECT_OPT_TPM2_EVICT,
      .arg   = NULL,
      .flags = 0,
      .doc   =
	N_("Evict a previously persisted SRK from the TPM, if any."),
      .group = 0
    },
    {
      .name = "tpm2key",
      .key   = GRUB_PROTECT_OPT_TPM2_TPM2KEY,
      .arg   = NULL,
      .flags = 0,
      .doc   =
	N_("Use TPM 2.0 Key File format instead of the raw format."),
      .group = 0
    },
    /* End of list */
    { 0, 0, 0, 0, 0, 0 }
  };

static int grub_protector_tpm2_fd = -1;

static grub_err_t
grub_protect_read_file (const char *filepath, void **buffer,
			size_t *buffer_size)
{
  grub_err_t err;
  FILE *f;
  long len;
  void *buf;

  f = fopen (filepath, "rb");
  if (f == NULL)
    return GRUB_ERR_FILE_NOT_FOUND;

  if (fseek (f, 0, SEEK_END))
    {
       err = GRUB_ERR_FILE_READ_ERROR;
       goto exit1;
    }

  len = ftell (f);
  if (len == 0)
    {
       err = GRUB_ERR_FILE_READ_ERROR;
       goto exit1;
    }

  rewind (f);

  buf = grub_malloc (len);
  if (buf == NULL)
    {
       err = GRUB_ERR_OUT_OF_MEMORY;
       goto exit1;
    }

  if (fread (buf, len, 1, f) != 1)
    {
       err = GRUB_ERR_FILE_READ_ERROR;
       goto exit2;
    }

  *buffer = buf;
  *buffer_size = len;

  buf = NULL;
  err = GRUB_ERR_NONE;

exit2:
  grub_free (buf);

exit1:
  fclose (f);

  return err;
}

static grub_err_t
grub_protect_write_file (const char *filepath, void *buffer, size_t buffer_size)
{
  grub_err_t err;
  FILE *f;

  f = fopen (filepath, "wb");
  if (f == NULL)
    return GRUB_ERR_FILE_NOT_FOUND;

  if (fwrite (buffer, buffer_size, 1, f) != 1)
  {
    err = GRUB_ERR_WRITE_ERROR;
    goto exit1;
  }

  err = GRUB_ERR_NONE;

exit1:
  fclose (f);

  return err;
}

static grub_err_t
grub_protect_get_grub_drive_for_file (const char *filepath, char **drive)
{
  grub_err_t err = GRUB_ERR_IO;
  char *disk;
  char **devices;
  char *grub_dev;
  char *grub_path;
  char *efi_drive;
  char *partition;
  char *grub_drive;
  grub_device_t dev;
  grub_size_t grub_drive_len;
  int n;

  grub_path = grub_canonicalize_file_name (filepath);
  if (grub_path == NULL)
    goto exit1;

  devices = grub_guess_root_devices (grub_path);
  if (devices == NULL || devices[0] == NULL)
    goto exit2;

  disk = devices[0];

  grub_util_pull_device (disk);

  grub_dev = grub_util_get_grub_dev (disk);
  if (grub_dev == NULL)
    goto exit3;

  dev = grub_device_open (grub_dev);
  if (dev == NULL)
    goto exit4;

  efi_drive = grub_util_guess_efi_drive (disk);
  if (efi_drive == NULL)
    goto exit5;

  partition = grub_partition_get_name (dev->disk->partition);
  if (partition == NULL)
    goto exit6;

  grub_drive_len = grub_strlen (efi_drive) + grub_strlen (partition) + 3;
  grub_drive = grub_malloc (grub_drive_len + 1);
  if (grub_drive == NULL)
    goto exit7;

  n = grub_snprintf (grub_drive, grub_drive_len + 1, "(%s,%s)", efi_drive,
		     partition);
  if (n != grub_drive_len)
    goto exit8;

  *drive = grub_drive;
  grub_drive = NULL;
  err = GRUB_ERR_NONE;

exit8:
  grub_free (grub_drive);

exit7:
  grub_free (partition);

exit6:
  grub_free (efi_drive);

exit5:
  grub_device_close (dev);

exit4:
  grub_free (grub_dev);

exit3:
  grub_free (devices);

exit2:
  grub_free (grub_path);

exit1:
  return err;
}

grub_err_t
grub_tcg2_get_max_output_size (grub_size_t *size)
{
  if (size == NULL)
    return GRUB_ERR_BAD_ARGUMENT;

  *size = GRUB_TPM2_BUFFER_CAPACITY;

  return GRUB_ERR_NONE;
}

grub_err_t
grub_tcg2_submit_command (grub_size_t input_size, grub_uint8_t *input,
			  grub_size_t output_size, grub_uint8_t *output)
{
  static const grub_size_t header_size = sizeof (grub_uint16_t) +
					 (2 * sizeof(grub_uint32_t));

  if (write (grub_protector_tpm2_fd, input, input_size) != input_size)
    return GRUB_ERR_BAD_DEVICE;

  if (read (grub_protector_tpm2_fd, output, output_size) < header_size)
    return GRUB_ERR_BAD_DEVICE;

  return GRUB_ERR_NONE;
}

static grub_err_t
grub_protect_tpm2_open_device (const char *dev_node)
{
  if (grub_protector_tpm2_fd != -1)
    return GRUB_ERR_NONE;

  grub_protector_tpm2_fd = open (dev_node, O_RDWR);
  if (grub_protector_tpm2_fd == -1)
    {
      fprintf (stderr, _("Could not open TPM device (Error: %u).\n"), errno);
      return GRUB_ERR_FILE_NOT_FOUND;
    }

  return GRUB_ERR_NONE;
}

static grub_err_t
grub_protect_tpm2_close_device (void)
{
  int err;

  if (grub_protector_tpm2_fd == -1)
    return GRUB_ERR_NONE;

  err = close (grub_protector_tpm2_fd);
  if (err != GRUB_ERR_NONE)
  {
    fprintf (stderr, _("Could not close TPM device (Error: %u).\n"), errno);
    return GRUB_ERR_IO;
  }

  grub_protector_tpm2_fd = -1;
  return GRUB_ERR_NONE;
}

static grub_err_t
grub_protect_tpm2_get_policy_digest (struct grub_protect_args *args,
				     TPM2B_DIGEST *digest)
{
  TPM_RC rc;
  TPML_PCR_SELECTION pcr_sel = {
    .count = 1,
    .pcrSelections = {
      {
	.hash = args->tpm2_bank,
	.sizeOfSelect = 3,
	.pcrSelect = { 0 }
      },
    }
  };
  TPML_PCR_SELECTION pcr_sel_out = { 0 };
  TPML_DIGEST pcr_values = { 0 };
  grub_uint8_t *pcr_digest;
  grub_size_t pcr_digest_len;
  grub_uint8_t *pcr_concat;
  grub_size_t pcr_concat_len;
  grub_uint8_t *pcr_cursor;
  const gcry_md_spec_t *hash_spec;
  TPM2B_NONCE nonce = { 0 };
  TPM2B_ENCRYPTED_SECRET salt = { 0 };
  TPMT_SYM_DEF symmetric = { 0 };
  TPMI_SH_AUTH_SESSION session = 0;
  TPM2B_DIGEST pcr_digest_in = {
    .size = TPM_SHA256_DIGEST_SIZE,
    .buffer = { 0 }
  };
  TPM2B_DIGEST policy_digest = { 0 };
  grub_uint8_t i;
  grub_err_t err;

  /* PCR Read */
  for (i = 0; i < args->tpm2_pcr_count; i++)
    TPMS_PCR_SELECTION_SelectPCR (&pcr_sel.pcrSelections[0], args->tpm2_pcrs[i]);

  rc = TPM2_PCR_Read (NULL, &pcr_sel, NULL, &pcr_sel_out, &pcr_values, NULL);
  if (rc != TPM_RC_SUCCESS)
    {
      fprintf (stderr, _("Failed to read PCRs (TPM2_PCR_Read: 0x%x).\n"), rc);
      return GRUB_ERR_BAD_DEVICE;
    }

  if ((pcr_sel_out.count != pcr_sel.count) ||
       (pcr_sel.pcrSelections[0].sizeOfSelect !=
	pcr_sel_out.pcrSelections[0].sizeOfSelect))
    {
      fprintf (stderr, _("Could not read all the specified PCRs.\n"));
      return GRUB_ERR_BAD_DEVICE;
    }

  /* Compute PCR Digest */
  switch (args->tpm2_bank)
    {
    case TPM_ALG_SHA1:
      pcr_digest_len = TPM_SHA1_DIGEST_SIZE;
      hash_spec = GRUB_MD_SHA1;
      break;
    case TPM_ALG_SHA256:
      pcr_digest_len = TPM_SHA256_DIGEST_SIZE;
      hash_spec = GRUB_MD_SHA256;
      break;
    case TPM_ALG_SHA512:
      pcr_digest_len = TPM_SHA512_DIGEST_SIZE;
      hash_spec = GRUB_MD_SHA512;
      break;
    /* Although SHA384 can be parsed by grub_tpm2_protector_parse_bank(),
       it's not supported by the built-in libgcrypt, and we won't be able to
       calculate the PCR digest, so SHA384 is marked as unsupported. */
    default:
      return GRUB_ERR_BAD_ARGUMENT;
    }

  pcr_digest = grub_malloc (pcr_digest_len);
  if (!pcr_digest)
    {
      fprintf (stderr, _("Failed to allocate PCR digest buffer.\n"));
      return GRUB_ERR_OUT_OF_MEMORY;
    }

  pcr_concat_len = pcr_digest_len * args->tpm2_pcr_count;
  pcr_concat = grub_malloc (pcr_concat_len);
  if (pcr_concat == NULL)
    {
      err = GRUB_ERR_OUT_OF_MEMORY;
      fprintf (stderr, _("Failed to allocate PCR concatenation buffer.\n"));
      goto exit1;
    }

  pcr_cursor = pcr_concat;
  for (i = 0; i < args->tpm2_pcr_count; i++)
    {
      if (pcr_values.digests[i].size != pcr_digest_len)
	{
	  fprintf (stderr,
		   _("Bad PCR value size: expected %" PRIuGRUB_SIZE " bytes but got %u bytes.\n"),
		   pcr_digest_len, pcr_values.digests[i].size);
	  goto exit2;
	}

      grub_memcpy (pcr_cursor, pcr_values.digests[i].buffer, pcr_digest_len);
      pcr_cursor += pcr_digest_len;
    }

  grub_crypto_hash (hash_spec, pcr_digest, pcr_concat, pcr_concat_len);

  /* Start Trial Session */
  nonce.size = TPM_SHA256_DIGEST_SIZE;
  symmetric.algorithm = TPM_ALG_NULL;

  rc = TPM2_StartAuthSession (TPM_RH_NULL, TPM_RH_NULL, 0, &nonce, &salt,
			      TPM_SE_TRIAL, &symmetric, TPM_ALG_SHA256,
			      &session, NULL, 0);
  if (rc != TPM_RC_SUCCESS)
    {
      fprintf (stderr,
	       _("Failed to start trial policy session (TPM2_StartAuthSession: 0x%x).\n"),
	       rc);
      err = GRUB_ERR_BAD_DEVICE;
      goto exit2;
    }

  /* PCR Policy */
  memcpy (pcr_digest_in.buffer, pcr_digest, TPM_SHA256_DIGEST_SIZE);

  rc = TPM2_PolicyPCR (session, NULL, &pcr_digest_in, &pcr_sel, NULL);
  if (rc != TPM_RC_SUCCESS)
    {
      fprintf (stderr, _("Failed to submit PCR policy (TPM2_PolicyPCR: 0x%x).\n"),
	       rc);
      err = GRUB_ERR_BAD_DEVICE;
      goto exit3;
    }

  /* Retrieve Policy Digest */
  rc = TPM2_PolicyGetDigest (session, NULL, &policy_digest, NULL);
  if (rc != TPM_RC_SUCCESS)
    {
      fprintf (stderr, _("Failed to get policy digest (TPM2_PolicyGetDigest: 0x%x).\n"),
	       rc);
      err = GRUB_ERR_BAD_DEVICE;
      goto exit3;
    }

  /* Epilogue */
  *digest = policy_digest;
  err = GRUB_ERR_NONE;

exit3:
  TPM2_FlushContext (session);

exit2:
  grub_free (pcr_concat);

exit1:
  grub_free (pcr_digest);

  return err;
}

static grub_err_t
grub_protect_tpm2_get_srk (struct grub_protect_args *args, TPM_HANDLE *srk)
{
  TPM_RC rc;
  TPM2B_PUBLIC public;
  TPMS_AUTH_COMMAND authCommand = { 0 };
  TPM2B_SENSITIVE_CREATE inSensitive = { 0 };
  TPM2B_PUBLIC inPublic = { 0 };
  TPM2B_DATA outsideInfo = { 0 };
  TPML_PCR_SELECTION creationPcr = { 0 };
  TPM2B_PUBLIC outPublic = { 0 };
  TPM2B_CREATION_DATA creationData = { 0 };
  TPM2B_DIGEST creationHash = { 0 };
  TPMT_TK_CREATION creationTicket = { 0 };
  TPM2B_NAME srkName = { 0 };
  TPM_HANDLE srkHandle;

  if (args->tpm2_srk != 0)
    {
      /* Find SRK */
      rc = TPM2_ReadPublic (args->tpm2_srk, NULL, &public);
      if (rc == TPM_RC_SUCCESS)
	{
	  printf (_("Read SRK from 0x%x\n"), args->tpm2_srk);
	  *srk = args->tpm2_srk;
	  return GRUB_ERR_NONE;
	}

      /* The handle exists but its public area could not be read. */
      if ((rc & ~TPM_RC_N_MASK) != TPM_RC_HANDLE)
	{
	  fprintf (stderr,
		   _("Failed to retrieve SRK from 0x%x (TPM2_ReadPublic: 0x%x).\n"),
		   args->tpm2_srk, rc);
	  return GRUB_ERR_BAD_DEVICE;
	}
    }

  /* Create SRK */
  authCommand.sessionHandle = TPM_RS_PW;
  inPublic.publicArea.type = args->tpm2_asymmetric;
  inPublic.publicArea.nameAlg  = TPM_ALG_SHA256;
  inPublic.publicArea.objectAttributes.restricted = 1;
  inPublic.publicArea.objectAttributes.userWithAuth = 1;
  inPublic.publicArea.objectAttributes.decrypt = 1;
  inPublic.publicArea.objectAttributes.fixedTPM = 1;
  inPublic.publicArea.objectAttributes.fixedParent = 1;
  inPublic.publicArea.objectAttributes.sensitiveDataOrigin = 1;
  inPublic.publicArea.objectAttributes.noDA = 1;

  switch (args->tpm2_asymmetric)
    {
    case TPM_ALG_RSA:
      inPublic.publicArea.parameters.rsaDetail.symmetric.algorithm = TPM_ALG_AES;
      inPublic.publicArea.parameters.rsaDetail.symmetric.keyBits.aes = 128;
      inPublic.publicArea.parameters.rsaDetail.symmetric.mode.aes = TPM_ALG_CFB;
      inPublic.publicArea.parameters.rsaDetail.scheme.scheme = TPM_ALG_NULL;
      inPublic.publicArea.parameters.rsaDetail.keyBits = args->rsa_bits;
      inPublic.publicArea.parameters.rsaDetail.exponent = 0;
      break;

    case TPM_ALG_ECC:
      inPublic.publicArea.parameters.eccDetail.symmetric.algorithm = TPM_ALG_AES;
      inPublic.publicArea.parameters.eccDetail.symmetric.keyBits.aes = 128;
      inPublic.publicArea.parameters.eccDetail.symmetric.mode.aes = TPM_ALG_CFB;
      inPublic.publicArea.parameters.eccDetail.scheme.scheme = TPM_ALG_NULL;
      inPublic.publicArea.parameters.eccDetail.curveID = args->ecc_curve;
      inPublic.publicArea.parameters.eccDetail.kdf.scheme = TPM_ALG_NULL;
      break;

    default:
      return GRUB_ERR_BAD_ARGUMENT;
    }

  rc = TPM2_CreatePrimary (TPM_RH_OWNER, &authCommand, &inSensitive, &inPublic,
			   &outsideInfo, &creationPcr, &srkHandle, &outPublic,
			   &creationData, &creationHash, &creationTicket,
			   &srkName, NULL);
  if (rc != TPM_RC_SUCCESS)
    {
      fprintf (stderr, _("Failed to create SRK (TPM2_CreatePrimary: 0x%x).\n"), rc);
      return GRUB_ERR_BAD_DEVICE;
    }

  /* Persist SRK */
  if (args->tpm2_srk != 0)
    {
      rc = TPM2_EvictControl (TPM_RH_OWNER, srkHandle, &authCommand,
			      args->tpm2_srk, NULL);
      if (rc == TPM_RC_SUCCESS)
	{
	  TPM2_FlushContext (srkHandle);
	  srkHandle = args->tpm2_srk;
	}
      else
	fprintf (stderr,
		 _("Warning: Failed to persist SRK (0x%x) (TPM2_EvictControl: 0x%x\n). "
		   "Continuing anyway...\n"), args->tpm2_srk, rc);
    }

  /* Epilogue */
  *srk = srkHandle;

  return GRUB_ERR_NONE;
}

static grub_err_t
grub_protect_tpm2_seal (TPM2B_DIGEST *policyDigest, TPM_HANDLE srk,
			grub_uint8_t *clearText, grub_size_t clearTextLength,
			TPM2_SEALED_KEY *sealed_key)
{
  TPM_RC rc;
  TPMS_AUTH_COMMAND authCommand = { 0 };
  TPM2B_SENSITIVE_CREATE inSensitive = { 0 };
  TPM2B_PUBLIC inPublic  = { 0 };
  TPM2B_DATA outsideInfo = { 0 };
  TPML_PCR_SELECTION pcr_sel = { 0 };
  TPM2B_PRIVATE outPrivate = { 0 };
  TPM2B_PUBLIC outPublic = { 0 };

  /* Seal Data */
  authCommand.sessionHandle = TPM_RS_PW;

  inSensitive.sensitive.data.size = clearTextLength;
  memcpy(inSensitive.sensitive.data.buffer, clearText, clearTextLength);

  inPublic.publicArea.type = TPM_ALG_KEYEDHASH;
  inPublic.publicArea.nameAlg = TPM_ALG_SHA256;
  inPublic.publicArea.parameters.keyedHashDetail.scheme.scheme = TPM_ALG_NULL;
  inPublic.publicArea.authPolicy = *policyDigest;

  rc = TPM2_Create (srk, &authCommand, &inSensitive, &inPublic, &outsideInfo,
		    &pcr_sel, &outPrivate, &outPublic, NULL, NULL, NULL, NULL);
  if (rc != TPM_RC_SUCCESS)
    {
      fprintf (stderr, _("Failed to seal key (TPM2_Create: 0x%x).\n"), rc);
      return GRUB_ERR_BAD_DEVICE;
    }

  /* Epilogue */
  sealed_key->public = outPublic;
  sealed_key->private = outPrivate;

  return GRUB_ERR_NONE;
}

extern asn1_static_node tpm2key_asn1_tab[];

static grub_err_t
grub_protect_tpm2_export_tpm2key (const struct grub_protect_args *args,
				  TPM2_SEALED_KEY *sealed_key)
{
  const char *sealed_key_oid = "2.23.133.10.1.5";
  asn1_node asn1_def = NULL;
  asn1_node tpm2key = NULL;
  grub_uint32_t parent;
  grub_uint32_t cmd_code;
  struct grub_tpm2_buffer pol_buf;
  TPML_PCR_SELECTION pcr_sel = {
    .count = 1,
    .pcrSelections = {
      {
	.hash = args->tpm2_bank,
	.sizeOfSelect = 3,
	.pcrSelect = { 0 }
      },
    }
  };
  struct grub_tpm2_buffer pub_buf;
  struct grub_tpm2_buffer priv_buf;
  void *der_buf = NULL;
  int der_buf_size = 0;
  int i;
  int ret;
  grub_err_t err;

  for (i = 0; i < args->tpm2_pcr_count; i++)
    TPMS_PCR_SELECTION_SelectPCR (&pcr_sel.pcrSelections[0], args->tpm2_pcrs[i]);

  /*
   * Prepare the parameters for TPM_CC_PolicyPCR:
   * empty pcrDigest and the user selected PCRs
   */
  grub_tpm2_buffer_init (&pol_buf);
  grub_tpm2_buffer_pack_u16 (&pol_buf, 0);
  grub_tpm2_mu_TPML_PCR_SELECTION_Marshal (&pol_buf, &pcr_sel);

  grub_tpm2_buffer_init (&pub_buf);
  grub_tpm2_mu_TPM2B_PUBLIC_Marshal (&pub_buf, &sealed_key->public);
  grub_tpm2_buffer_init (&priv_buf);
  grub_tpm2_mu_TPM2B_Marshal (&priv_buf, sealed_key->private.size,
			      sealed_key->private.buffer);
  if (pub_buf.error != 0 || priv_buf.error != 0)
    return GRUB_ERR_BAD_ARGUMENT;

  ret = asn1_array2tree (tpm2key_asn1_tab, &asn1_def, NULL);
  if (ret != ASN1_SUCCESS)
    return GRUB_ERR_BAD_ARGUMENT;

  ret = asn1_create_element (asn1_def, "TPM2KEY.TPMKey" , &tpm2key);
  if (ret != ASN1_SUCCESS)
    return GRUB_ERR_BAD_ARGUMENT;

  /* Set 'type' to "sealed key" */
  ret = asn1_write_value (tpm2key, "type", sealed_key_oid, 1);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  /* Set 'emptyAuth' to TRUE */
  ret = asn1_write_value (tpm2key, "emptyAuth", "TRUE", 1);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  /* Set 'policy' */
  ret = asn1_write_value (tpm2key, "policy", "NEW", 1);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }
  cmd_code = grub_cpu_to_be32 (TPM_CC_PolicyPCR);
  ret = asn1_write_value (tpm2key, "policy.?LAST.CommandCode", &cmd_code,
			  sizeof (cmd_code));
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }
  ret = asn1_write_value (tpm2key, "policy.?LAST.CommandPolicy", &pol_buf.data,
			  pol_buf.size);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  /* Remove 'secret' */
  ret = asn1_write_value (tpm2key, "secret", NULL, 0);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  /* Remove 'authPolicy' */
  ret = asn1_write_value (tpm2key, "authPolicy", NULL, 0);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  /* Use TPM_RH_OWNER as the default parent handle */
  parent = grub_cpu_to_be32 (TPM_RH_OWNER);
  ret = asn1_write_value (tpm2key, "parent", &parent, sizeof (parent));
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  /* Set the pubkey */
  ret = asn1_write_value (tpm2key, "pubkey", pub_buf.data, pub_buf.size);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  /* Set the privkey */
  ret = asn1_write_value (tpm2key, "privkey", priv_buf.data, priv_buf.size);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  /* Create the DER binary */
  der_buf_size = 0;
  ret = asn1_der_coding (tpm2key, "", NULL, &der_buf_size, NULL);

  der_buf = grub_malloc (der_buf_size);
  if (der_buf == NULL)
    {
      err = GRUB_ERR_OUT_OF_MEMORY;
      goto error;
    }

  ret = asn1_der_coding (tpm2key, "", der_buf, &der_buf_size, NULL);
  if (ret != ASN1_SUCCESS)
    {
      err = GRUB_ERR_BAD_ARGUMENT;
      goto error;
    }

  err = grub_protect_write_file (args->tpm2_outfile, der_buf, der_buf_size);
  if (err != GRUB_ERR_NONE)
    fprintf (stderr, _("Could not write tpm2key file (Error: %u).\n"),
	     errno);

error:
  grub_free (der_buf);

  if (tpm2key)
    asn1_delete_structure (&tpm2key);

  return err;
}

static grub_err_t
grub_protect_tpm2_export_sealed_key (const char *filepath,
				     TPM2_SEALED_KEY *sealed_key)
{
  grub_err_t err;
  struct grub_tpm2_buffer buf;

  grub_tpm2_buffer_init (&buf);
  grub_tpm2_mu_TPM2B_PUBLIC_Marshal (&buf, &sealed_key->public);
  grub_tpm2_mu_TPM2B_Marshal (&buf, sealed_key->private.size,
			      sealed_key->private.buffer);
  if (buf.error != 0)
    return GRUB_ERR_BAD_ARGUMENT;

  err = grub_protect_write_file (filepath, buf.data, buf.size);
  if (err != GRUB_ERR_NONE)
    fprintf (stderr, _("Could not write sealed key file (Error: %u).\n"),
	     errno);

  return err;
}

static grub_err_t
grub_protect_tpm2_add (struct grub_protect_args *args)
{
  grub_err_t err;
  grub_uint8_t *key;
  grub_size_t key_size;
  TPM_HANDLE srk;
  TPM2B_DIGEST policy_digest;
  TPM2_SEALED_KEY sealed_key;
  char *grub_drive = NULL;

  grub_protect_get_grub_drive_for_file (args->tpm2_outfile, &grub_drive);

  err = grub_protect_tpm2_open_device (args->tpm2_device);
  if (err != GRUB_ERR_NONE)
    return err;

  err = grub_protect_read_file (args->tpm2_keyfile, (void **)&key, &key_size);
  if (err != GRUB_ERR_NONE)
    goto exit1;

  if (key_size > TPM_MAX_SYM_DATA)
  {
    fprintf (stderr,
	     _("Input key is too long, maximum allowed size is %u bytes.\n"),
	     TPM_MAX_SYM_DATA);
    return GRUB_ERR_OUT_OF_RANGE;
  }

  err = grub_protect_tpm2_get_srk (args, &srk);
  if (err != GRUB_ERR_NONE)
    goto exit2;

  err = grub_protect_tpm2_get_policy_digest (args, &policy_digest);
  if (err != GRUB_ERR_NONE)
    goto exit3;

  err = grub_protect_tpm2_seal (&policy_digest, srk, key, key_size,
				&sealed_key);
  if (err != GRUB_ERR_NONE)
    goto exit3;

  if (args->tpm2_tpm2key)
    err = grub_protect_tpm2_export_tpm2key (args, &sealed_key);
  else
    err = grub_protect_tpm2_export_sealed_key (args->tpm2_outfile, &sealed_key);
  if (err != GRUB_ERR_NONE)
    goto exit3;

  if (grub_drive)
    {
      printf (_("GRUB drive for the sealed key file: %s\n"), grub_drive);
      grub_free (grub_drive);
    }
  else
    {
      fprintf (stderr,
	       _("Warning: Could not determine GRUB drive for sealed key "
		 "file.\n"));
      err = GRUB_ERR_NONE;
    }

exit3:
  TPM2_FlushContext (srk);

exit2:
  grub_free (key);

exit1:
  grub_protect_tpm2_close_device ();

  return err;
}

static grub_err_t
grub_protect_tpm2_remove (struct grub_protect_args *args)
{
  TPM_RC rc;
  TPM2B_PUBLIC public;
  TPMS_AUTH_COMMAND authCommand = { 0 };
  grub_err_t err;

  if (args->tpm2_evict == 0)
    {
      printf (_("--tpm2-evict not specified, nothing to do.\n"));
      return GRUB_ERR_NONE;
    }

  err = grub_protect_tpm2_open_device (args->tpm2_device);
  if (err != GRUB_ERR_NONE)
    return err;

  /* Find SRK */
  rc = TPM2_ReadPublic (args->tpm2_srk, NULL, &public);
  if (rc != TPM_RC_SUCCESS)
    {
      fprintf (stderr, _("SRK with handle 0x%x not found.\n"), args->tpm2_srk);
      err = GRUB_ERR_BAD_ARGUMENT;
      goto exit1;
    }

  /* Evict SRK */
  authCommand.sessionHandle = TPM_RS_PW;

  rc = TPM2_EvictControl (TPM_RH_OWNER, args->tpm2_srk, &authCommand,
			  args->tpm2_srk, NULL);
  if (rc != TPM_RC_SUCCESS)
    {
      fprintf (stderr,
	       _("Failed to evict SRK with handle 0x%x (TPM2_EvictControl: 0x%x).\n"),
	       args->tpm2_srk, rc);
      err = GRUB_ERR_BAD_DEVICE;
      goto exit2;
    }

  err = GRUB_ERR_NONE;

exit2:
  TPM2_FlushContext (args->tpm2_srk);

exit1:
  grub_protect_tpm2_close_device ();

  return GRUB_ERR_NONE;
}

static grub_err_t
grub_protect_tpm2_run (struct grub_protect_args *args)
{
  switch (args->action)
    {
    case GRUB_PROTECT_ACTION_ADD:
      return grub_protect_tpm2_add (args);

    case GRUB_PROTECT_ACTION_REMOVE:
      return grub_protect_tpm2_remove (args);

    default:
      return GRUB_ERR_BAD_ARGUMENT;
    }
}

static grub_err_t
grub_protect_tpm2_args_verify (struct grub_protect_args *args)
{
  switch (args->action)
    {
    case GRUB_PROTECT_ACTION_ADD:
      if (args->args & GRUB_PROTECT_ARG_TPM2_EVICT)
	{
	  fprintf (stderr,
		   _("--tpm2-evict is invalid when --action is 'add'.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->tpm2_keyfile == NULL)
	{
	  fprintf (stderr, _("--tpm2-keyfile must be specified.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->tpm2_outfile == NULL)
	{
	  fprintf (stderr, _("--tpm2-outfile must be specified.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->tpm2_device == NULL)
	args->tpm2_device = "/dev/tpm0";

      if (args->tpm2_pcr_count == 0)
	{
	  args->tpm2_pcrs[0] = 7;
	  args->tpm2_pcr_count = 1;
	}

      if (args->tpm2_asymmetric == TPM_ALG_ERROR)
	{
	  args->tpm2_asymmetric = TPM_ALG_RSA;
	  args->rsa_bits = 2048;
	}

      if (args->tpm2_bank == TPM_ALG_ERROR)
	args->tpm2_bank = TPM_ALG_SHA256;

      break;

    case GRUB_PROTECT_ACTION_REMOVE:
      if (args->args & GRUB_PROTECT_ARG_TPM2_ASYMMETRIC)
	{
	  fprintf (stderr,
		   _("--tpm2-asymmetric is invalid when --action is 'remove'.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->args & GRUB_PROTECT_ARG_TPM2_BANK)
	{
	  fprintf (stderr,
		   _("--tpm2-bank is invalid when --action is 'remove'.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->args & GRUB_PROTECT_ARG_TPM2_KEYFILE)
	{
	  fprintf (stderr,
		   _("--tpm2-keyfile is invalid when --action is 'remove'.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->args & GRUB_PROTECT_ARG_TPM2_OUTFILE)
	{
	  fprintf (stderr,
		   _("--tpm2-outfile is invalid when --action is 'remove'.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->args & GRUB_PROTECT_ARG_TPM2_PCRS)
	{
	  fprintf (stderr,
		   _("--tpm2-pcrs is invalid when --action is 'remove'.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->tpm2_srk == 0)
	{
	  fprintf (stderr,
		   _("--tpm2-srk is not specified when --action is 'remove'.\n"));
	  return GRUB_ERR_BAD_ARGUMENT;
	}

      if (args->tpm2_device == NULL)
	args->tpm2_device = "/dev/tpm0";

      break;

    default:
      fprintf (stderr,
	       _("The TPM2 key protector only supports the following actions: "
		 "add, remove.\n"));
      return GRUB_ERR_BAD_ARGUMENT;
    }

  return GRUB_ERR_NONE;
}

static error_t
grub_protect_argp_parser (int key, char *arg, struct argp_state *state)
{
  grub_err_t err;
  struct grub_protect_args *args = state->input;

  switch (key)
    {
    case GRUB_PROTECT_OPT_ACTION:
      if (args->args & GRUB_PROTECT_ARG_ACTION)
	{
	  fprintf (stderr, _("--action|-a can only be specified once.\n"));
	  return EINVAL;
	}

      if (grub_strcmp (arg, "add") == 0)
	args->action = GRUB_PROTECT_ACTION_ADD;
      else if (grub_strcmp (arg, "remove") == 0)
	args->action = GRUB_PROTECT_ACTION_REMOVE;
      else
	{
	  fprintf (stderr, _("'%s' is not a valid action.\n"), arg);
	  return EINVAL;
	}

      args->args |= GRUB_PROTECT_ARG_ACTION;
      break;

    case GRUB_PROTECT_OPT_PROTECTOR:
      if (args->args & GRUB_PROTECT_ARG_PROTECTOR)
	{
	  fprintf (stderr, _("--protector|-p can only be specified once.\n"));
	  return EINVAL;
	}

      if (grub_strcmp (arg, "tpm2") == 0)
	args->protector = GRUB_PROTECT_TYPE_TPM2;
      else
	{
	  fprintf (stderr, _("'%s' is not a valid protector.\n"), arg);
	  return EINVAL;
	}

      args->args |= GRUB_PROTECT_ARG_PROTECTOR;
      break;

    case GRUB_PROTECT_OPT_TPM2_DEVICE:
      if (args->args & GRUB_PROTECT_ARG_TPM2_DEVICE)
	{
	  fprintf (stderr, _("--tpm2-device can only be specified once.\n"));
	  return EINVAL;
	}

      args->tpm2_device = xstrdup(arg);
      args->args |= GRUB_PROTECT_ARG_TPM2_DEVICE;
      break;

    case GRUB_PROTECT_OPT_TPM2_PCRS:
      if (args->args & GRUB_PROTECT_ARG_TPM2_PCRS)
	{
	  fprintf (stderr, _("--tpm2-pcrs can only be specified once.\n"));
	  return EINVAL;
	}

      err = grub_tpm2_protector_parse_pcrs (arg, args->tpm2_pcrs,
					    &args->tpm2_pcr_count);
      if (err != GRUB_ERR_NONE)
	{
	  if (grub_errno != GRUB_ERR_NONE)
	    grub_print_error ();
	  return EINVAL;
	}

      args->args |= GRUB_PROTECT_ARG_TPM2_PCRS;
      break;

    case GRUB_PROTECT_OPT_TPM2_SRK:
      if (args->args & GRUB_PROTECT_ARG_TPM2_SRK)
	{
	  fprintf (stderr, _("--tpm2-srk can only be specified once.\n"));
	  return EINVAL;
	}

      err = grub_tpm2_protector_parse_tpm_handle (arg, &args->tpm2_srk);
      if (err != GRUB_ERR_NONE)
	{
	  if (grub_errno != GRUB_ERR_NONE)
	    grub_print_error ();
	  return EINVAL;
	}

      args->args |= GRUB_PROTECT_ARG_TPM2_SRK;
      break;

    case GRUB_PROTECT_OPT_TPM2_ASYMMETRIC:
      if (args->args & GRUB_PROTECT_ARG_TPM2_ASYMMETRIC)
	{
	  fprintf (stderr, _("--tpm2-asymmetric can only be specified once.\n"));
	  return EINVAL;
	}

      err = grub_tpm2_protector_parse_asymmetric (arg, &args->tpm2_asymmetric,
						  &args->rsa_bits, &args->ecc_curve);
      if (err != GRUB_ERR_NONE)
	{
	  if (grub_errno != GRUB_ERR_NONE)
	    grub_print_error ();
	  return EINVAL;
	}

      args->args |= GRUB_PROTECT_ARG_TPM2_ASYMMETRIC;
      break;

    case GRUB_PROTECT_OPT_TPM2_BANK:
      if (args->args & GRUB_PROTECT_ARG_TPM2_BANK)
	{
	  fprintf (stderr, _("--tpm2-bank can only be specified once.\n"));
	  return EINVAL;
	}

      err = grub_tpm2_protector_parse_bank (arg, &args->tpm2_bank);
      if (err != GRUB_ERR_NONE)
	{
	  if (grub_errno != GRUB_ERR_NONE)
	    grub_print_error ();
	  return EINVAL;
	}

      args->args |= GRUB_PROTECT_ARG_TPM2_BANK;
      break;

    case GRUB_PROTECT_OPT_TPM2_KEYFILE:
      if (args->args & GRUB_PROTECT_ARG_TPM2_KEYFILE)
	{
	  fprintf (stderr, _("--tpm2-keyfile can only be specified once.\n"));
	  return EINVAL;
	}

      args->tpm2_keyfile = xstrdup(arg);
      args->args |= GRUB_PROTECT_ARG_TPM2_KEYFILE;
      break;

    case GRUB_PROTECT_OPT_TPM2_OUTFILE:
      if (args->args & GRUB_PROTECT_ARG_TPM2_OUTFILE)
	{
	  fprintf (stderr, _("--tpm2-outfile can only be specified once.\n"));
	  return EINVAL;
	}

      args->tpm2_outfile = xstrdup(arg);
      args->args |= GRUB_PROTECT_ARG_TPM2_OUTFILE;
      break;

    case GRUB_PROTECT_OPT_TPM2_EVICT:
      if (args->args & GRUB_PROTECT_ARG_TPM2_EVICT)
	{
	  fprintf (stderr, _("--tpm2-evict can only be specified once.\n"));
	  return EINVAL;
	}

      args->tpm2_evict = 1;
      args->args |= GRUB_PROTECT_ARG_TPM2_EVICT;
      break;

    case GRUB_PROTECT_OPT_TPM2_TPM2KEY:
      if (args->args & GRUB_PROTECT_ARG_TPM2_TPM2KEY)
	{
	  fprintf (stderr, _("--tpm2-tpm2key can only be specified once.\n"));
	  return EINVAL;
	}

      args->tpm2_tpm2key = 1;
      args->args |= GRUB_PROTECT_ARG_TPM2_TPM2KEY;
      break;

    default:
      return ARGP_ERR_UNKNOWN;
    }

  return 0;
}

static grub_err_t
grub_protect_args_verify (struct grub_protect_args *args)
{
  if (args->action == GRUB_PROTECT_ACTION_ERROR)
    {
      fprintf (stderr, "--action is mandatory.\n");
      return GRUB_ERR_BAD_ARGUMENT;
    }

  /* At the moment, the only configurable key protector is the TPM2 one, so it
   * is the only key protector supported by this tool. */
  if (args->protector != GRUB_PROTECT_TYPE_TPM2)
    {
      fprintf (stderr,
	       _("--protector is mandatory and only 'tpm2' is currently "
		 "supported.\n"));
      return GRUB_ERR_BAD_ARGUMENT;
    }

  switch (args->protector)
    {
    case GRUB_PROTECT_TYPE_TPM2:
      return grub_protect_tpm2_args_verify (args);
    default:
      return GRUB_ERR_BAD_ARGUMENT;
    }

  return GRUB_ERR_NONE;
}

static grub_err_t
grub_protect_dispatch (struct grub_protect_args *args)
{
  switch (args->protector)
    {
    case GRUB_PROTECT_TYPE_TPM2:
      return grub_protect_tpm2_run (args);
    default:
      return GRUB_ERR_BAD_ARGUMENT;
    }
}

static void
grub_protect_init (int *argc, char **argv[])
{
  grub_util_host_init (argc, argv);

  grub_util_biosdisk_init (NULL);

  grub_init_all ();
  grub_gcry_init_all ();

  grub_lvm_fini ();
  grub_mdraid09_fini ();
  grub_mdraid1x_fini ();
  grub_diskfilter_fini ();
  grub_diskfilter_init ();
  grub_mdraid09_init ();
  grub_mdraid1x_init ();
  grub_lvm_init ();
}

static void
grub_protect_fini (void)
{
  grub_gcry_fini_all ();
  grub_fini_all ();
  grub_util_biosdisk_fini ();
}

static struct argp grub_protect_argp =
{
  .options     = grub_protect_options,
  .parser      = grub_protect_argp_parser,
  .args_doc    = NULL,
  .doc         =
    N_("Protect a cleartext key using a GRUB key protector that can retrieve "
       "the key during boot to unlock fully-encrypted disks automatically."),
  .children    = NULL,
  .help_filter = NULL,
  .argp_domain = NULL
};

int
main (int argc, char *argv[])
{
  grub_err_t err;
  struct grub_protect_args args = { 0 };

  if (argp_parse (&grub_protect_argp, argc, argv, 0, 0, &args) != 0)
    {
      fprintf (stderr, _("Could not parse arguments.\n"));
      return GRUB_ERR_BAD_ARGUMENT;
    }

  grub_protect_init (&argc, &argv);

  err = grub_protect_args_verify (&args);
  if (err != GRUB_ERR_NONE)
    goto exit;

  err = grub_protect_dispatch (&args);
  if (err != GRUB_ERR_NONE)
    goto exit;

exit:
  grub_protect_fini ();

  return err;
}
