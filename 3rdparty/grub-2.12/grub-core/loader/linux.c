#include <grub/types.h>
#include <grub/err.h>
#include <grub/linux.h>
#include <grub/misc.h>
#include <grub/file.h>
#include <grub/mm.h>
#include <grub/safemath.h>
#include <grub/list.h>
#include <grub/crypttab.h>

struct newc_head
{
  char magic[6];
  char ino[8];
  char mode[8];
  char uid[8];
  char gid[8];
  char nlink[8];
  char mtime[8];
  char filesize[8];
  char devmajor[8];
  char devminor[8];
  char rdevmajor[8];
  char rdevminor[8];
  char namesize[8];
  char check[8];
} GRUB_PACKED;

struct grub_linux_initrd_component
{
  grub_file_t file;
  char *buf;
  char *newc_name;
  grub_off_t size;
  grub_uint32_t mode;
};

struct dir
{
  char *name;
  struct dir *next;
  struct dir *child;
};

static char
hex (grub_uint8_t val)
{
  if (val < 10)
    return '0' + val;
  return 'a' + val - 10;
}

static void
set_field (char *var, grub_uint32_t val)
{
  int i;
  char *ptr = var;
  for (i = 28; i >= 0; i -= 4)
    *ptr++ = hex((val >> i) & 0xf);
}

static grub_uint8_t *
make_header (grub_uint8_t *ptr,
	     const char *name, grub_size_t len,
	     grub_uint32_t mode,
	     grub_off_t fsize)
{
  struct newc_head *head = (struct newc_head *) ptr;
  grub_uint8_t *optr;
  grub_size_t oh = 0;

  grub_dprintf ("linux", "newc: Creating path '%s', mode=%s%o, size=%" PRIuGRUB_OFFSET "\n", name, (mode == 0) ? "" : "0", mode, fsize);
  grub_memcpy (head->magic, "070701", 6);
  set_field (head->ino, 0);
  set_field (head->mode, mode);
  set_field (head->uid, 0);
  set_field (head->gid, 0);
  set_field (head->nlink, 1);
  set_field (head->mtime, 0);
  set_field (head->filesize, fsize);
  set_field (head->devmajor, 0);
  set_field (head->devminor, 0);
  set_field (head->rdevmajor, 0);
  set_field (head->rdevminor, 0);
  set_field (head->namesize, len);
  set_field (head->check, 0);
  optr = ptr;
  ptr += sizeof (struct newc_head);
  grub_memcpy (ptr, name, len);
  ptr += len;
  oh = ALIGN_UP_OVERHEAD (ptr - optr, 4);
  grub_memset (ptr, 0, oh);
  ptr += oh;
  return ptr;
}

static void
free_dir (struct dir *root)
{
  if (!root)
    return;
  free_dir (root->next);
  free_dir (root->child);
  grub_free (root->name);
  grub_free (root);
}

static grub_err_t
insert_dir (const char *name, struct dir **root,
	    grub_uint8_t *ptr, grub_size_t *size)
{
  struct dir *cur, **head = root;
  const char *cb, *ce = name;
  *size = 0;

  while (1)
    {
      for (cb = ce; *cb == '/'; cb++);
      for (ce = cb; *ce && *ce != '/'; ce++);
      if (!*ce)
	break;

      for (cur = *root; cur; cur = cur->next)
	if (grub_memcmp (cur->name, cb, ce - cb) == 0
	    && cur->name[ce - cb] == 0)
	  break;
      if (!cur)
	{
	  struct dir *n;
	  n = grub_zalloc (sizeof (*n));
	  if (!n)
	    return 0;
	  n->next = *head;
	  n->name = grub_strndup (cb, ce - cb);
	  if (ptr)
	    {
	      /*
	       * Create the substring with the trailing NUL byte
	       * to be included in the cpio header.
	       */
	      char *tmp_name = grub_strndup (name, ce - name);
	      if (!tmp_name) {
		grub_free (n->name);
		grub_free (n);
		return grub_errno;
	      }
	      ptr = make_header (ptr, tmp_name, ce - name + 1,
				 040777, 0);
	      grub_free (tmp_name);
	    }
	  if (grub_add (*size,
		        ALIGN_UP ((ce - (char *) name + 1)
				  + sizeof (struct newc_head), 4),
			size))
	    {
	      grub_error (GRUB_ERR_OUT_OF_RANGE, N_("overflow is detected"));
	      grub_free (n->name);
	      grub_free (n);
	      return grub_errno;
	    }
	  *head = n;
	  cur = n;
	}
      root = &cur->next;
    }
  return GRUB_ERR_NONE;
}

static grub_err_t
grub_initrd_component (const char *buf, int bufsz, const char *newc_name,
		  struct grub_linux_initrd_context *initrd_ctx)
{
  struct dir *root = 0;
  struct grub_linux_initrd_component *comp = initrd_ctx->components + initrd_ctx->nfiles;
  grub_size_t dir_size, name_len;

  while (*newc_name == '/')
    newc_name++;

  initrd_ctx->size = ALIGN_UP (initrd_ctx->size, 4);
  comp->newc_name = grub_strdup (newc_name);
  if (!comp->newc_name ||
      insert_dir (comp->newc_name, &root, 0, &dir_size))
    {
      /* FIXME: Check NULL file pointer before close */
      grub_initrd_close (initrd_ctx);
      return grub_errno;
    }
  /* Should name_len count terminating null ? */
  name_len = grub_strlen (comp->newc_name) + 1;
  if (grub_add (initrd_ctx->size,
		ALIGN_UP (sizeof (struct newc_head) + name_len, 4),
		&initrd_ctx->size) ||
      grub_add (initrd_ctx->size, dir_size, &initrd_ctx->size))
    goto overflow;

  comp->buf = grub_malloc (bufsz);
  if (!comp->buf)
    {
      free_dir (root);
      grub_initrd_close (initrd_ctx);
      return grub_errno;
    }
  grub_memcpy (comp->buf, buf, bufsz);
  initrd_ctx->nfiles++;
  comp->size = bufsz;
  comp->mode = 0100400;
  if (grub_add (initrd_ctx->size, comp->size,
		&initrd_ctx->size))
    goto overflow;

  free_dir (root);
  root = 0;
  return GRUB_ERR_NONE;

 overflow:
  free_dir (root);
  grub_initrd_close (initrd_ctx);
  return grub_error (GRUB_ERR_OUT_OF_RANGE, N_("overflow is detected"));
}

grub_err_t
grub_initrd_init (int argc, char *argv[],
		  struct grub_linux_initrd_context *initrd_ctx)
{
  int i;
  int newc = 0;
  struct dir *root = 0;
  grub_crypto_key_list_t *pk;
  int numkey = 0;

  initrd_ctx->nfiles = 0;
  initrd_ctx->components = 0;

  FOR_LIST_ELEMENTS (pk, cryptokey_lst)
    if (pk->key && pk->path)
      numkey++;

  initrd_ctx->components = grub_calloc (argc + numkey, sizeof (initrd_ctx->components[0]));
  if (!initrd_ctx->components)
    return grub_errno;

  initrd_ctx->size = 0;

  for (i = 0; i < argc; i++)
    {
      const char *fname = argv[i];

      initrd_ctx->size = ALIGN_UP (initrd_ctx->size, 4);

      if (grub_memcmp (argv[i], "newc:", 5) == 0)
	{
	  const char *ptr, *eptr;
	  ptr = argv[i] + 5;
	  while (*ptr == '/')
	    ptr++;
	  eptr = grub_strchr (ptr, ':');
	  if (eptr)
	    {
	      grub_size_t dir_size, name_len;

	      initrd_ctx->components[i].newc_name = grub_strndup (ptr, eptr - ptr);
	      if (!initrd_ctx->components[i].newc_name ||
		  insert_dir (initrd_ctx->components[i].newc_name, &root, 0,
			      &dir_size))
		{
		  grub_initrd_close (initrd_ctx);
		  return grub_errno;
		}
	      initrd_ctx->components[i].mode = 0100777;
	      name_len = grub_strlen (initrd_ctx->components[i].newc_name) + 1;
	      if (grub_add (initrd_ctx->size,
			    ALIGN_UP (sizeof (struct newc_head) + name_len, 4),
			    &initrd_ctx->size) ||
		  grub_add (initrd_ctx->size, dir_size, &initrd_ctx->size))
		goto overflow;
	      newc = 1;
	      fname = eptr + 1;
	    }
	}
      else if (newc)
	{
	  if (grub_add (initrd_ctx->size,
			ALIGN_UP (sizeof (struct newc_head)
				  + sizeof ("TRAILER!!!"), 4),
			&initrd_ctx->size))
	    goto overflow;
	  free_dir (root);
	  root = 0;
	  newc = 0;
	}
      initrd_ctx->components[i].file = grub_file_open (fname,
						       GRUB_FILE_TYPE_LINUX_INITRD
						       | GRUB_FILE_TYPE_NO_DECOMPRESS);
      if (!initrd_ctx->components[i].file)
	{
	  grub_initrd_close (initrd_ctx);
	  return grub_errno;
	}
      initrd_ctx->nfiles++;
      initrd_ctx->components[i].size
	= grub_file_size (initrd_ctx->components[i].file);
      if (grub_add (initrd_ctx->size, initrd_ctx->components[i].size,
		    &initrd_ctx->size))
	goto overflow;
    }

  FOR_LIST_ELEMENTS (pk, cryptokey_lst)
    if (pk->key && pk->path)
      {
	grub_initrd_component (pk->key, pk->key_len, pk->path, initrd_ctx);
	newc = 1;
      }

  if (newc)
    {
      initrd_ctx->size = ALIGN_UP (initrd_ctx->size, 4);
      if (grub_add (initrd_ctx->size,
		    ALIGN_UP (sizeof (struct newc_head)
			      + sizeof ("TRAILER!!!"), 4),
		    &initrd_ctx->size))
	goto overflow;
      free_dir (root);
      root = 0;
    }

  return GRUB_ERR_NONE;

 overflow:
  free_dir (root);
  grub_initrd_close (initrd_ctx);
  return grub_error (GRUB_ERR_OUT_OF_RANGE, N_("overflow is detected"));
}

grub_size_t
grub_get_initrd_size (struct grub_linux_initrd_context *initrd_ctx)
{
  return initrd_ctx->size;
}

void
grub_initrd_close (struct grub_linux_initrd_context *initrd_ctx)
{
  int i;
  if (!initrd_ctx->components)
    return;
  for (i = 0; i < initrd_ctx->nfiles; i++)
    {
      grub_free (initrd_ctx->components[i].newc_name);
      if (initrd_ctx->components[i].file)
	grub_file_close (initrd_ctx->components[i].file);
      grub_free (initrd_ctx->components[i].buf);
    }
  grub_free (initrd_ctx->components);
  initrd_ctx->components = 0;
}

grub_err_t
grub_initrd_load (struct grub_linux_initrd_context *initrd_ctx,
		  void *target)
{
  grub_uint8_t *ptr = target;
  int i;
  int newc = 0;
  struct dir *root = 0;
  grub_ssize_t cursize = 0;

  for (i = 0; i < initrd_ctx->nfiles; i++)
    {
      grub_memset (ptr, 0, ALIGN_UP_OVERHEAD (cursize, 4));
      ptr += ALIGN_UP_OVERHEAD (cursize, 4);

      if (initrd_ctx->components[i].newc_name)
	{
	  grub_size_t dir_size;
	  grub_uint32_t mode = initrd_ctx->components[i].mode; 

	  if (insert_dir (initrd_ctx->components[i].newc_name, &root, ptr,
			  &dir_size))
	    {
	      free_dir (root);
	      grub_initrd_close (initrd_ctx);
	      return grub_errno;
	    }
	  ptr += dir_size;
	  ptr = make_header (ptr, initrd_ctx->components[i].newc_name,
			     grub_strlen (initrd_ctx->components[i].newc_name) + 1,
			     mode,
			     initrd_ctx->components[i].size);
	  newc = 1;
	}
      else if (newc)
	{
	  ptr = make_header (ptr, "TRAILER!!!", sizeof ("TRAILER!!!"),
			     0, 0);
	  free_dir (root);
	  root = 0;
	  newc = 0;
	}

      cursize = initrd_ctx->components[i].size;
      if (initrd_ctx->components[i].buf)
        grub_memcpy (ptr, initrd_ctx->components[i].buf, cursize);
      else if (grub_file_read (initrd_ctx->components[i].file, ptr, cursize)
	  != cursize)
	{
	  if (!grub_errno)
	    grub_error (GRUB_ERR_FILE_READ_ERROR, N_("premature end of file %s"),
			initrd_ctx->components[i].file->name);
	  grub_initrd_close (initrd_ctx);
	  return grub_errno;
	}
      ptr += cursize;
    }
  if (newc)
    {
      grub_memset (ptr, 0, ALIGN_UP_OVERHEAD (cursize, 4));
      ptr += ALIGN_UP_OVERHEAD (cursize, 4);
      ptr = make_header (ptr, "TRAILER!!!", sizeof ("TRAILER!!!"), 0, 0);
    }
  free_dir (root);
  root = 0;
  return GRUB_ERR_NONE;
}
