
#include <grub/dl.h>
#include <grub/command.h>
#include <grub/misc.h>
#include <grub/i18n.h>
#include <grub/mm.h>
#include <grub/list.h>
#include <grub/crypttab.h>
#include <grub/file.h>

GRUB_MOD_LICENSE ("GPLv3+");

grub_crypto_key_list_t *cryptokey_lst;

static grub_file_t
grub_nocat_open (grub_file_t io, enum grub_file_type type)
{
  grub_disk_t disk;

  /* Network device */
  if (!io->device->disk)
    return io;

  disk = io->device->disk; 

  if (grub_disk_is_crypto (disk))
    {
      switch (type & GRUB_FILE_TYPE_MASK)
	{
	  case GRUB_FILE_TYPE_CAT:
	  case GRUB_FILE_TYPE_HEXCAT:
	    grub_error (GRUB_ERR_ACCESS_DENIED, N_("prohibited to view encrypted data"));
	    return NULL;
	  default:
	    break;
	}
    }

  return io;
}

grub_err_t
grub_cryptokey_add_or_update (const char *uuid, const char *key, grub_size_t key_len, const char *path, int is_tpmkey)
{
  grub_crypto_key_list_t *cur = NULL;

  FOR_LIST_ELEMENTS (cur, cryptokey_lst)
    if (grub_uuidcasecmp (cur->name, uuid, sizeof (cur->name)) == 0)
      break;

  if (!cur && !uuid)
    return GRUB_ERR_NONE;

  if (!cur)
    cur = grub_zalloc (sizeof (*cur));
  if (!cur)
    return grub_errno;

  if (key && key_len)
    {
      grub_free (cur->key);
      cur->key = grub_malloc (key_len);
      if (!cur->key)
	{
	  grub_free (cur);
	  return grub_errno;
	}
      grub_memcpy (cur->key, key, key_len);
      cur->key_len = key_len;
    }

  if (path)
    {
      grub_free (cur->path);
      cur->path = grub_strdup (path);
    }

  if (is_tpmkey >= 0)
    {
      cur->is_tpmkey = is_tpmkey;
      if (is_tpmkey)
	grub_file_filter_register (GRUB_FILE_FILTER_NOCAT, grub_nocat_open);
    }

  if (!cur->name)
    {
      cur->name = grub_strdup (uuid);
      grub_list_push (GRUB_AS_LIST_P (&cryptokey_lst), GRUB_AS_LIST (cur));
    }

  return GRUB_ERR_NONE;
}

void
grub_cryptokey_discard (void)
{
  grub_crypto_key_list_t *cur, *nxt;

  FOR_LIST_ELEMENTS_SAFE (cur, nxt, cryptokey_lst)
	{
	  grub_list_remove (GRUB_AS_LIST (cur));
	  grub_memset (cur->key, 0, cur->key_len);
	  grub_free (cur->name);
	  grub_free (cur->path);
	  grub_free (cur->key);
	  grub_free (cur);
	}
}

void
grub_cryptokey_tpmkey_discard (void)
{
  grub_crypto_key_list_t *cur = NULL;

  FOR_LIST_ELEMENTS (cur, cryptokey_lst)
    if (cur->is_tpmkey)
      break;

  /* Discard all keys if any of them is tpm */
  if (cur)
    grub_cryptokey_discard();
}

static grub_file_t
grub_distrust_open (grub_file_t io,
		enum grub_file_type type __attribute__ ((unused)))
{
  grub_disk_t disk = io->device->disk;

  if (io->device->disk &&
      (io->device->disk->dev->id == GRUB_DISK_DEVICE_MEMDISK_ID
       || io->device->disk->dev->id == GRUB_DISK_DEVICE_PROCFS_ID))
    return io;

  /* Ensure second stage files is in a protected location or grub won't hand
   * over the key and discards it */
  switch (type & GRUB_FILE_TYPE_MASK)
    {
      case GRUB_FILE_TYPE_ACPI_TABLE:
      case GRUB_FILE_TYPE_CONFIG:
      case GRUB_FILE_TYPE_DEVICE_TREE_IMAGE:
      case GRUB_FILE_TYPE_FONT:
      case GRUB_FILE_TYPE_GRUB_MODULE:
      case GRUB_FILE_TYPE_GRUB_MODULE_LIST:
      case GRUB_FILE_TYPE_LINUX_KERNEL:
      case GRUB_FILE_TYPE_LINUX_INITRD:
      case GRUB_FILE_TYPE_LOADENV:
      case GRUB_FILE_TYPE_THEME:
	if (!disk || !grub_disk_is_crypto (disk))
	  grub_cryptokey_discard ();
	break;
      default:
	break;
    }

  return io;
}

static grub_err_t
grub_cmd_crypttab_entry (grub_command_t cmd __attribute__ ((unused)),
	       int argc, char **argv)
{
  char buf[256];
  const char *path = NULL;

  if (argc == 2)
    path = NULL;
  else if (argc == 3)
    path = argv[2];
  else
    return grub_error (GRUB_ERR_BAD_ARGUMENT, N_("two or three arguments expected"));

  if (!path
      || grub_strcmp (path, "none") == 0
      || grub_strcmp (path, "-") == 0)
    {
      grub_snprintf (buf, sizeof (buf), "/etc/cryptsetup-keys.d/%s.key", argv[0]);
      path = buf;
    }

  /*FIXME: Validate UUID string*/
  return grub_cryptokey_add_or_update (argv[1], NULL, 0, path, -1);
}

static grub_command_t cmd;

GRUB_MOD_INIT(crypttab)
{
  cmd = grub_register_command ("crypttab_entry", grub_cmd_crypttab_entry,
			       N_("VOLUME-NAME ENCRYPTED-DEVICE KEY-FILE") , N_("No description"));
  grub_file_filter_register (GRUB_FILE_FILTER_DISTRUST, grub_distrust_open);
  grub_dl_set_persistent (mod);
}

GRUB_MOD_FINI(crypttab)
{
  grub_unregister_command (cmd);
}
