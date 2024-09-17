/* ofdisk.c - Open Firmware disk access.  */
/*
 *  GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2004,2006,2007,2008,2009  Free Software Foundation, Inc.
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

#include <grub/misc.h>
#include <grub/disk.h>
#include <grub/mm.h>
#include <grub/ieee1275/ieee1275.h>
#include <grub/ieee1275/ofdisk.h>
#include <grub/i18n.h>
#include <grub/time.h>
#include <grub/env.h>
#include <grub/command.h>

#define RETRY_DEFAULT_TIMEOUT 15

static char *last_devpath;
static grub_ieee1275_ihandle_t last_ihandle;

#define IEEE1275_DISK_ALIAS "/disk@"
#define IEEE1275_NVMEOF_DISK_ALIAS "/nvme-of/controller@"

/* Used to check boot_type, print debug message if doesn't match, this can be
 * useful to measure boot delays */
static char *boot_type;
/* Used to restrict fcp to a physical boot path */
static char *boot_parent;
/* Knowing the nvmeof in advance to avoid blind open test during iteration to
 * validate a path */
static int is_boot_nvmeof;

struct ofdisk_hash_ent
{
  char *devpath;
  char *open_path;
  char *grub_devpath;
  int is_boot;
  int is_removable;
  int block_size_fails;
  /* Pointer to shortest available name on nodes representing canonical names,
     otherwise NULL.  */
  const char *shortest;
  const char *grub_shortest;
  struct ofdisk_hash_ent *next;
};

static grub_err_t
grub_ofdisk_get_block_size (grub_uint32_t *block_size,
			    struct ofdisk_hash_ent *op);

#define OFDISK_HASH_SZ	8
static struct ofdisk_hash_ent *ofdisk_hash[OFDISK_HASH_SZ];

static void early_log (const char *fmt, ...);
static void print_early_log (void);

static int
ofdisk_hash_fn (const char *devpath)
{
  int hash = 0;
  while (*devpath)
    hash ^= *devpath++;
  return (hash & (OFDISK_HASH_SZ - 1));
}

static struct ofdisk_hash_ent *
ofdisk_hash_find (const char *devpath)
{
  struct ofdisk_hash_ent *p = ofdisk_hash[ofdisk_hash_fn(devpath)];

  while (p)
    {
      if (!grub_strcmp (p->devpath, devpath))
	break;
      p = p->next;
    }
  return p;
}

static struct ofdisk_hash_ent *
ofdisk_hash_add_real (char *devpath)
{
  struct ofdisk_hash_ent *p;
  struct ofdisk_hash_ent **head = &ofdisk_hash[ofdisk_hash_fn(devpath)];
  const char *iptr;
  char *optr;

  p = grub_zalloc (sizeof (*p));
  if (!p)
    return NULL;

  p->devpath = devpath;

  p->grub_devpath = grub_malloc (sizeof ("ieee1275/")
				 + 2 * grub_strlen (p->devpath));

  if (!p->grub_devpath)
    {
      grub_free (p);
      return NULL;
    }

  if (! grub_ieee1275_test_flag (GRUB_IEEE1275_FLAG_NO_PARTITION_0))
    {
      p->open_path = grub_malloc (grub_strlen (p->devpath) + 3);
      if (!p->open_path)
	{
	  grub_free (p->grub_devpath);
	  grub_free (p);
	  return NULL;
	}
      optr = grub_stpcpy (p->open_path, p->devpath);
      *optr++ = ':';
      *optr++ = '0';
      *optr = '\0';
    }
  else
    p->open_path = p->devpath;

  optr = grub_stpcpy (p->grub_devpath, "ieee1275/");
  for (iptr = p->devpath; *iptr; )
    {
      if (*iptr == ',')
	*optr++ = '\\';
      *optr++ = *iptr++;
    }
  *optr = 0;

  p->next = *head;
  *head = p;
  return p;
}

static int
check_string_removable (const char *str)
{
  const char *ptr = grub_strrchr (str, '/');

  if (ptr)
    ptr++;
  else
    ptr = str;
  return (grub_strncmp (ptr, "cdrom", 5) == 0 || grub_strncmp (ptr, "fd", 2) == 0);
}

static struct ofdisk_hash_ent *
ofdisk_hash_add (char *devpath, char *curcan)
{
  struct ofdisk_hash_ent *p, *pcan;

  p = ofdisk_hash_add_real (devpath);

  grub_dprintf ("disk", "devpath = %s, canonical = %s\n", devpath, curcan);

  if (!curcan)
    {
      p->shortest = p->devpath;
      p->grub_shortest = p->grub_devpath;
      if (check_string_removable (devpath))
	p->is_removable = 1;
      return p;
    }

  pcan = ofdisk_hash_find (curcan);
  if (!pcan)
    pcan = ofdisk_hash_add_real (curcan);
  else
    grub_free (curcan);

  if (check_string_removable (devpath) || check_string_removable (curcan))
    pcan->is_removable = 1;

  if (!pcan)
    grub_errno = GRUB_ERR_NONE;
  else
    {
      if (!pcan->shortest
	  || grub_strlen (pcan->shortest) > grub_strlen (devpath))
	{
	  pcan->shortest = p->devpath;
	  pcan->grub_shortest = p->grub_devpath;
	}
    }

  return p;
}

static void
dev_iterate_real (const char *name, const char *path)
{
  struct ofdisk_hash_ent *op;

  grub_dprintf ("disk", "disk name = %s, path = %s\n", name,
		path);

  op = ofdisk_hash_find (path);
  if (!op)
    {
      char *name_dup = grub_strdup (name);
      char *can = grub_strdup (path);
      if (!name_dup || !can)
	{
	  grub_errno = GRUB_ERR_NONE;
	  grub_free (name_dup);
	  grub_free (can);
	  return;
	}
      op = ofdisk_hash_add (name_dup, can);
    }
  return;
}


static void
dev_iterate_fcp_disks(const struct grub_ieee1275_devalias *alias)
{
    /* If we are dealing with fcp devices, we need
     * to find the WWPNs and LUNs to iterate them */
    grub_ieee1275_ihandle_t ihandle;
    grub_uint64_t *ptr_targets, *ptr_luns, k, l;
    unsigned int i, j, pos;
    char *buf, *bufptr;

    struct set_fcp_targets_args
    {
      struct grub_ieee1275_common_hdr common;
      grub_ieee1275_cell_t method;
      grub_ieee1275_cell_t ihandle;
      grub_ieee1275_cell_t catch_result;
      grub_ieee1275_cell_t nentries;
      grub_ieee1275_cell_t table;
    } args_targets;

    struct set_fcp_luns_args
    {
      struct grub_ieee1275_common_hdr common;
      grub_ieee1275_cell_t method;
      grub_ieee1275_cell_t ihandle;
      grub_ieee1275_cell_t wwpn_h;
      grub_ieee1275_cell_t wwpn_l;
      grub_ieee1275_cell_t catch_result;
      grub_ieee1275_cell_t nentries;
      grub_ieee1275_cell_t table;
    } args_luns;

    struct args_ret
    {
      grub_uint64_t addr;
      grub_uint64_t len;
    };

    if(grub_ieee1275_open (alias->path, &ihandle))
    {
      grub_dprintf("disk", "failed to open the disk while iterating FCP disk path=%s\n", alias->path);
      return;
    }

    /* Setup the fcp-targets method to call via pfw*/
    INIT_IEEE1275_COMMON (&args_targets.common, "call-method", 2, 3);
    args_targets.method = (grub_ieee1275_cell_t) "fcp-targets";
    args_targets.ihandle = ihandle;

    /* Setup the fcp-luns method to call via pfw */
    INIT_IEEE1275_COMMON (&args_luns.common, "call-method", 4, 3);
    args_luns.method = (grub_ieee1275_cell_t) "fcp-luns";
    args_luns.ihandle = ihandle;

    if (IEEE1275_CALL_ENTRY_FN (&args_targets) == -1)
    {
      grub_dprintf("disk", "failed to get the targets while iterating FCP disk path=%s\n", alias->path);
      grub_ieee1275_close(ihandle);
      return;
    }

    buf = grub_malloc (grub_strlen (alias->path) + 32 + 32);

    if (!buf)
    {
      grub_ieee1275_close(ihandle);
      return;
    }

    bufptr = grub_stpcpy (buf, alias->path);

    /* Iterate over entries returned by pfw. Each entry contains a
     * pointer to wwpn table and his length. */
    struct args_ret *targets_table = (struct args_ret *)(args_targets.table);
    for (i=0; i< args_targets.nentries; i++)
    {
      ptr_targets = (grub_uint64_t*)(grub_uint32_t) targets_table[i].addr;
      /* Iterate over all wwpns in given table */
      for(k=0;k<targets_table[i].len;k++)
      {
        args_luns.wwpn_l = (grub_ieee1275_cell_t) (*ptr_targets);
        args_luns.wwpn_h = (grub_ieee1275_cell_t) (*ptr_targets >> 32);
        pos=grub_snprintf (bufptr, 32, "/disk@%" PRIxGRUB_UINT64_T,
                                                *ptr_targets++);
        /* Get the luns for given wwpn target */
        if (IEEE1275_CALL_ENTRY_FN (&args_luns) == -1)
        {
          grub_dprintf("disk", "failed to get the LUNS while iterating FCP disk path=%s\n", buf);
          grub_ieee1275_close (ihandle);
          grub_free (buf);
          return;
        }

        struct args_ret *luns_table = (struct args_ret *)(args_luns.table);

        /* Iterate over all LUNs */
        for(j=0;j<args_luns.nentries; j++)
        {
          ptr_luns = (grub_uint64_t*) (grub_uint32_t) luns_table[j].addr;
          for(l=0;l<luns_table[j].len;l++)
          {
            grub_snprintf (&bufptr[pos], 30, ",%" PRIxGRUB_UINT64_T,
                                                       *ptr_luns++);
            dev_iterate_real(buf,buf);
          }
        }

      }
    }

    grub_ieee1275_close (ihandle);
    grub_free (buf);
    return;

}

static void
dev_iterate_fcp_nvmeof (const struct grub_ieee1275_devalias *alias)
{
    
    
    char *bufptr;
    grub_ieee1275_ihandle_t ihandle;


    // Create the structs for the parameters passing to PFW
    struct nvme_args_
    {
      struct grub_ieee1275_common_hdr common;
      grub_ieee1275_cell_t method;
      grub_ieee1275_cell_t ihandle;
      grub_ieee1275_cell_t catch_result;
      grub_ieee1275_cell_t nentries;
      grub_ieee1275_cell_t table;
    } nvme_discovery_controllers_args, nvme_controllers_args, nvme_namespaces_args;


    // Create the structs for the results from PFW

    struct discovery_controllers_table_struct_
    {
      grub_uint64_t table[256];
      grub_uint32_t len;
    } discovery_controllers_table;

    /* struct nvme_controllers_table_entry
     * this the return of nvme-controllers method tables, containing:
     * - 2-byte controller ID
     * - 256-byte transport address string
     * - 256-byte field containing null-terminated NVM subsystem NQN string up to 223 characters
     */
    struct nvme_controllers_table_entry_
    {
      grub_uint16_t id;
      char wwpn[256];
      char nqn[256];
    };
    
    struct nvme_controllers_table_entry_* nvme_controllers_table = grub_malloc(sizeof(struct nvme_controllers_table_entry_)*256);
    
    grub_uint32_t nvme_controllers_table_entries;

    struct nvme_controllers_table_entry_real
    {
      grub_uint16_t id;
      char wwpn[256];
      char nqn[256];
    };

    /* Allocate memory for building the NVMeoF path */
    char *buf = grub_malloc (grub_strlen (alias->path) + 512);
    if (!buf)
    {
      grub_ieee1275_close(ihandle);
      return;
    }

    /* Copy the alias->path to buf so we can work with */
    bufptr = grub_stpcpy (buf, alias->path);
    grub_snprintf (bufptr, 32, "/nvme-of");

    /* 
     *  Open the nvme-of layer
     *  Ex.  /pci@bus/fibre-channel@@dev,func/nvme-of
     */
    if(grub_ieee1275_open (buf, &ihandle))
    {
      grub_dprintf("disk", "failed to open the disk while iterating FCP disk path=%s\n", buf);
      return;
    }

    /*
     * Call to nvme-discovery-controllers method from the nvme-of layer
     * to get a list of the NVMe discovery controllers per the binding
     */

    INIT_IEEE1275_COMMON (&nvme_discovery_controllers_args.common, "call-method", 2, 2);
    nvme_discovery_controllers_args.method = (grub_ieee1275_cell_t) "nvme-discovery-controllers";
    nvme_discovery_controllers_args.ihandle = ihandle;

    if (IEEE1275_CALL_ENTRY_FN (&nvme_discovery_controllers_args) == -1)
    {
      grub_dprintf("disk", "failed to get the targets while iterating FCP disk path=%s\n", buf);
      grub_ieee1275_close(ihandle);
      return;
    }

    /* After closing the device, the info is lost. So lets copy each buffer in the buffers table */

    discovery_controllers_table.len = (grub_uint32_t) nvme_discovery_controllers_args.nentries;

    unsigned int i=0;
    for(i = 0; i < discovery_controllers_table.len; i++){
	    discovery_controllers_table.table[i] = ((grub_uint64_t*)nvme_discovery_controllers_args.table)[i];
    }

    grub_ieee1275_close(ihandle); 
 
    grub_dprintf("ofdisk","NVMeoF: Found %d discovery controllers\n",discovery_controllers_table.len);

    /* For each nvme discovery controller */
    int current_buffer_index;
    for(current_buffer_index = 0; current_buffer_index < (int) discovery_controllers_table.len; current_buffer_index++){

    
        grub_snprintf (bufptr, 64, "/nvme-of/controller@%" PRIxGRUB_UINT64_T ",ffff",
                                                discovery_controllers_table.table[current_buffer_index]);

        grub_dprintf("ofdisk","nvmeof controller=%s\n",buf);

        if(grub_ieee1275_open (buf, &ihandle))
        {
           grub_dprintf("ofdisk", "failed to open the disk while getting nvme-controllers  path=%s\n", buf);
           continue;
         }

        
	INIT_IEEE1275_COMMON (&nvme_controllers_args.common, "call-method", 2, 2);
        nvme_controllers_args.method = (grub_ieee1275_cell_t) "nvme-controllers";
        nvme_controllers_args.ihandle = ihandle;
        nvme_controllers_args.catch_result = 0;


	if (IEEE1275_CALL_ENTRY_FN (&nvme_controllers_args) == -1)
         {
          grub_dprintf("ofdisk", "failed to get the nvme-controllers while iterating FCP disk path\n");
          grub_ieee1275_close(ihandle);
          continue;
         }


	/* Copy the buffer list to nvme_controllers_table */
	nvme_controllers_table_entries = ((grub_uint32_t) nvme_controllers_args.nentries);
	struct nvme_controllers_table_entry_* nvme_controllers_table_ = (struct nvme_controllers_table_entry_*) nvme_controllers_args.table;

	for(i = 0; i < nvme_controllers_table_entries; i++){
		nvme_controllers_table[i].id = (grub_uint16_t) nvme_controllers_table_[i].id;
		grub_strcpy(nvme_controllers_table[i].wwpn, nvme_controllers_table_[i].wwpn);
		grub_strcpy(nvme_controllers_table[i].nqn, nvme_controllers_table_[i].nqn);
	}

	grub_ieee1275_close(ihandle);

	int nvme_controller_index;
        int bufptr_pos2;
        grub_dprintf("ofdisk","NVMeoF: found %d nvme controllers\n",(int) nvme_controllers_args.nentries);

	/* For each nvme controller */
        for(nvme_controller_index = 0; nvme_controller_index < (int) nvme_controllers_args.nentries; nvme_controller_index++){
           /* Open the nvme controller
            *       /pci@bus/fibre-channel@dev,func/nvme-of/controller@transport-addr,ctlr-id:nqn=tgt-subsystem-nqn
            */

           bufptr_pos2 = grub_snprintf (bufptr, 512, "/nvme-of/controller@%s,ffff:nqn=%s",
                                                nvme_controllers_table[nvme_controller_index].wwpn, nvme_controllers_table[nvme_controller_index].nqn);

	   grub_dprintf("ofdisk","NVMeoF: nvmeof controller=%s\n",buf);

           if(grub_ieee1275_open (buf, &ihandle)){
              grub_dprintf("ofdisk","failed to open the path=%s\n",buf);
	      continue;
	   }

           INIT_IEEE1275_COMMON (&nvme_namespaces_args.common, "call-method", 2, 2);
           nvme_namespaces_args.method = (grub_ieee1275_cell_t) "get-namespace-list";
           nvme_namespaces_args.ihandle = ihandle;
           nvme_namespaces_args.catch_result = 0;

  	   if (IEEE1275_CALL_ENTRY_FN (&nvme_namespaces_args) == -1)
           {
            grub_dprintf("ofdisk", "failed to get the nvme-namespace-list while iterating FCP disk path\n");
            grub_ieee1275_close(ihandle);
            continue;
           }

           grub_uint32_t *namespaces = (grub_uint32_t*) nvme_namespaces_args.table;
	   grub_dprintf("ofdisk","NVMeoF: found %d namespaces\n",(int)nvme_namespaces_args.nentries);
	   
	   grub_ieee1275_close(ihandle);

	   grub_uint32_t namespace_index = 0;
	   for(namespace_index=0; namespace_index < nvme_namespaces_args.nentries; namespace_index++){
		 grub_snprintf (bufptr+bufptr_pos2, 512, "/namespace@%"PRIxGRUB_UINT32_T,namespaces[namespace_index]);
		 grub_dprintf("ofdisk","NVMeoF: namespace=%s\n",buf);
		 dev_iterate_real(buf,buf);
           }

	   dev_iterate_real(buf,buf); 
	}
    }
    grub_free(buf);
    return;
}

static void
dev_iterate (const struct grub_ieee1275_devalias *alias)
{
  if (grub_strcmp (alias->type, "fcp") == 0)
  {
    if (boot_parent &&
	grub_strcmp (boot_parent, alias->path) != 0)
      {
	grub_dprintf ("ofdisk", "Skipped device: %s, doesn't match boot_parent %s\n",
	    alias->path, boot_parent);
	goto iter_children;
      }

    /* Allow set boot_parent and boot_type to NULL to force iteration */
    if (!boot_parent)
      {
	grub_dprintf ("ofdisk", "iterate %s\n", alias->path);
	dev_iterate_fcp_nvmeof(alias);
	dev_iterate_fcp_disks(alias);
      }
    else if (is_boot_nvmeof)
      {
	grub_dprintf ("ofdisk", "iterate nvmeof: %s\n", alias->path);
	dev_iterate_fcp_nvmeof(alias);
      }
    else
      {
	grub_dprintf ("ofdisk", "iterate fcp: %s\n", alias->path);
	dev_iterate_fcp_disks(alias);
      }
  }
  else if (grub_strcmp (alias->type, "vscsi") == 0)
    {
      static grub_ieee1275_ihandle_t ihandle;
      struct set_color_args
      {
	struct grub_ieee1275_common_hdr common;
	grub_ieee1275_cell_t method;
	grub_ieee1275_cell_t ihandle;
	grub_ieee1275_cell_t catch_result;
	grub_ieee1275_cell_t nentries;
	grub_ieee1275_cell_t table;
      }
      args;
      char *buf, *bufptr;
      unsigned i;

      if (boot_type &&
	  grub_strcmp (boot_type, alias->type) != 0)
	{
	  grub_dprintf ("ofdisk", "WARN: device: %s, type %s not match boot_type %s\n",
	      alias->path, alias->type, boot_type);
	}

      if (grub_ieee1275_open (alias->path, &ihandle))
	return;

      /* This method doesn't need memory allocation for the table. Open
         firmware takes care of all memory management and the result table
         stays in memory and is never freed. */
      INIT_IEEE1275_COMMON (&args.common, "call-method", 2, 3);
      args.method = (grub_ieee1275_cell_t) "vscsi-report-luns";
      args.ihandle = ihandle;
      args.table = 0;
      args.nentries = 0;

      if (IEEE1275_CALL_ENTRY_FN (&args) == -1 || args.catch_result)
	{
	  grub_ieee1275_close (ihandle);
	  return;
	}

      buf = grub_malloc (grub_strlen (alias->path) + 32);
      if (!buf)
	return;
      bufptr = grub_stpcpy (buf, alias->path);

      for (i = 0; i < args.nentries; i++)
	{
	  grub_uint64_t *ptr;

	  ptr = *(grub_uint64_t **) (args.table + 4 + 8 * i);
	  while (*ptr)
	    {
	      grub_snprintf (bufptr, 32, "/disk@%" PRIxGRUB_UINT64_T, *ptr++);
	      dev_iterate_real (buf, buf);
	    }
	}
      grub_ieee1275_close (ihandle);
      grub_free (buf);
      return;
    }
  else if (grub_strcmp (alias->type, "sas_ioa") == 0)
    {
      /* The method returns the number of disks and a table where
       * each ID is 64-bit long. Example of sas paths:
       *  /pci@80000002000001f/pci1014,034A@0/sas/disk@c05db70800
       *  /pci@80000002000001f/pci1014,034A@0/sas/disk@a05db70800
       *  /pci@80000002000001f/pci1014,034A@0/sas/disk@805db70800 */

      struct sas_children
        {
          struct grub_ieee1275_common_hdr common;
          grub_ieee1275_cell_t method;
          grub_ieee1275_cell_t ihandle;
          grub_ieee1275_cell_t max;
          grub_ieee1275_cell_t table;
          grub_ieee1275_cell_t catch_result;
          grub_ieee1275_cell_t nentries;
        }
      args;
      char *buf, *bufptr;
      unsigned i;
      grub_uint64_t *table;
      grub_uint16_t table_size;
      grub_ieee1275_ihandle_t ihandle;

      if (boot_type &&
	  grub_strcmp (boot_type, alias->type) != 0)
	{
	  grub_dprintf ("ofdisk", "WARN: device: %s, type %s not match boot_type %s\n",
	      alias->path, alias->type, boot_type);
	}

      buf = grub_malloc (grub_strlen (alias->path) +
                         sizeof ("/disk@7766554433221100"));
      if (!buf)
        return;
      bufptr = grub_stpcpy (buf, alias->path);

      /* Power machines documentation specify 672 as maximum SAS disks in
         one system. Using a slightly larger value to be safe. */
      table_size = 768;
      table = grub_calloc (table_size, sizeof (grub_uint64_t));

      if (!table)
        {
          grub_free (buf);
          return;
        }

      if (grub_ieee1275_open (alias->path, &ihandle))
        {
          grub_free (buf);
          grub_free (table);
          return;
        }

      INIT_IEEE1275_COMMON (&args.common, "call-method", 4, 2);
      args.method = (grub_ieee1275_cell_t) "get-sas-children";
      args.ihandle = ihandle;
      args.max = table_size;
      args.table = (grub_ieee1275_cell_t) table;
      args.catch_result = 0;
      args.nentries = 0;

      if (IEEE1275_CALL_ENTRY_FN (&args) == -1)
        {
          grub_ieee1275_close (ihandle);
          grub_free (table);
          grub_free (buf);
          return;
        }

      for (i = 0; i < args.nentries; i++)
        {
          grub_snprintf (bufptr, sizeof ("/disk@7766554433221100"),
                        "/disk@%" PRIxGRUB_UINT64_T, table[i]);
          dev_iterate_real (buf, buf);
        }

      grub_ieee1275_close (ihandle);
      grub_free (table);
      grub_free (buf);
    }

  if (!grub_ieee1275_test_flag (GRUB_IEEE1275_FLAG_NO_TREE_SCANNING_FOR_DISKS)
      && grub_strcmp (alias->type, "block") == 0)
    {
      dev_iterate_real (alias->path, alias->path);
      return;
    }

 iter_children:
  {
    struct grub_ieee1275_devalias child;

    FOR_IEEE1275_DEVCHILDREN(alias->path, child)
      dev_iterate (&child);
  }
}

static void
scan (void)
{
  struct grub_ieee1275_devalias alias;
  FOR_IEEE1275_DEVALIASES(alias)
    {
      if (grub_strcmp (alias.type, "block") != 0)
	continue;
      dev_iterate_real (alias.name, alias.path);
    }

  FOR_IEEE1275_DEVCHILDREN("/", alias)
    dev_iterate (&alias);
}

static int
grub_ofdisk_iterate (grub_disk_dev_iterate_hook_t hook, void *hook_data,
		     grub_disk_pull_t pull)
{
  unsigned i;

  if (pull > GRUB_DISK_PULL_REMOVABLE)
    return 0;

  if (pull == GRUB_DISK_PULL_REMOVABLE)
    scan ();

  for (i = 0; i < ARRAY_SIZE (ofdisk_hash); i++)
    {
      static struct ofdisk_hash_ent *ent;
      for (ent = ofdisk_hash[i]; ent; ent = ent->next)
	{
	  if (!ent->shortest)
	    continue;
	  if (grub_ieee1275_test_flag (GRUB_IEEE1275_FLAG_OFDISK_SDCARD_ONLY))
	    {
	      grub_ieee1275_phandle_t dev;
	      char tmp[8];

	      if (grub_ieee1275_finddevice (ent->devpath, &dev))
		{
		  grub_dprintf ("disk", "finddevice (%s) failed\n",
				ent->devpath);
		  continue;
		}

	      if (grub_ieee1275_get_property (dev, "iconname", tmp,
					      sizeof tmp, 0))
		{
		  grub_dprintf ("disk", "get iconname failed\n");
		  continue;
		}

	      if (grub_strcmp (tmp, "sdmmc") != 0)
		{
		  grub_dprintf ("disk", "device is not an SD card\n");
		  continue;
		}
	    }

	  if (!ent->is_boot && ent->is_removable)
	    continue;

	  if (pull == GRUB_DISK_PULL_NONE && !ent->is_boot)
	    continue;

	  if (pull == GRUB_DISK_PULL_REMOVABLE && ent->is_boot)
	    continue;

	  if (hook (ent->grub_shortest, hook_data))
	    return 1;
	}
    }
  return 0;
}

static char *
compute_dev_path (const char *name)
{
  char *devpath = grub_malloc (grub_strlen (name) + 3);
  char *p, c;

  if (!devpath)
    return NULL;

  /* Un-escape commas. */
  p = devpath;
  while ((c = *name++) != '\0')
    {
      if (c == '\\' && *name == ',')
	{
	  *p++ = ',';
	  name++;
	}
      else
	*p++ = c;
    }

  *p++ = '\0';

  return devpath;
}

static grub_err_t
grub_ofdisk_open_real (const char *name, grub_disk_t disk)
{
  grub_ieee1275_phandle_t dev;
  char *devpath;
  /* XXX: This should be large enough for any possible case.  */
  char prop[64];
  grub_ssize_t actual;
  grub_uint32_t block_size = 0;
  grub_err_t err;
  struct ofdisk_hash_ent *op;

  if (grub_strncmp (name, "ieee1275/", sizeof ("ieee1275/") - 1) != 0)
      return grub_error (GRUB_ERR_UNKNOWN_DEVICE,
			 "not IEEE1275 device");
  devpath = compute_dev_path (name + sizeof ("ieee1275/") - 1);
  if (! devpath)
    return grub_errno;

  grub_dprintf ("disk", "Opening `%s'.\n", devpath);

  op = ofdisk_hash_find (devpath);
  if (!op)
    op = ofdisk_hash_add (devpath, NULL);
  if (!op)
    {
      grub_free (devpath);
      return grub_errno;
    }

  /* Check if the call to open is the same to the last disk already opened */
  if (last_devpath && !grub_strcmp(op->open_path,last_devpath))
  {
      goto finish;
  }

 /* If not, we need to close the previous disk and open the new one */
  else {
    if (last_ihandle){
        grub_ieee1275_close (last_ihandle);
    }
    last_ihandle = 0;
    last_devpath = NULL;

    grub_ieee1275_open (op->open_path, &last_ihandle);
    if (! last_ihandle)
      return grub_error (GRUB_ERR_UNKNOWN_DEVICE, "can't open device");
    last_devpath = op->open_path;
  }

  if (grub_ieee1275_finddevice (devpath, &dev))
    {
      grub_free (devpath);
      return grub_error (GRUB_ERR_UNKNOWN_DEVICE,
			 "can't read device properties");
    }

  if (grub_ieee1275_get_property (dev, "device_type", prop, sizeof (prop),
				  &actual))
    {
      grub_free (devpath);
      return grub_error (GRUB_ERR_UNKNOWN_DEVICE, "can't read the device type");
    }

  if (grub_strcmp (prop, "block"))
    {
      grub_free (devpath);
      return grub_error (GRUB_ERR_UNKNOWN_DEVICE, "not a block device");
    }


  finish:
  /* XXX: There is no property to read the number of blocks.  There
     should be a property `#blocks', but it is not there.  Perhaps it
     is possible to use seek for this.  */
  disk->total_sectors = GRUB_DISK_SIZE_UNKNOWN;

  {
    disk->id = (unsigned long) op;
    disk->data = op->open_path;

    err = grub_ofdisk_get_block_size (&block_size, op);
    if (err)
      {
        grub_free (devpath);
        return err;
      }
    if (block_size != 0)
      disk->log_sector_size = grub_log2ull (block_size);
    else
      disk->log_sector_size = 9;
  }

  grub_free (devpath);
  return 0;
}

static grub_uint64_t
grub_ofdisk_disk_timeout (grub_disk_t disk)
{
  grub_uint64_t retry;
  const char *timeout = grub_env_get ("ofdisk_retry_timeout");

  if (!(grub_strstr (disk->name, "fibre-channel@") ||
      grub_strstr (disk->name, "vfc-client")) ||
      grub_strstr(disk->name, "nvme-of"))
    {
      /* Do not retry in case of non network drives */
      return 0;
    }

  if (timeout != NULL)
    {
       retry = grub_strtoul (timeout, 0, 10);
       if (grub_errno != GRUB_ERR_NONE)
         {
           grub_errno = GRUB_ERR_NONE;
           return RETRY_DEFAULT_TIMEOUT;
         }
       if (retry)
         return retry;
    }
  return RETRY_DEFAULT_TIMEOUT;
}

static grub_err_t
grub_ofdisk_open (const char *name, grub_disk_t disk)
{
  grub_err_t err;
  grub_uint64_t timeout = grub_get_time_ms () + (grub_ofdisk_disk_timeout (disk) * 1000);
  _Bool cont;
  do
    {
      err = grub_ofdisk_open_real (name, disk);
      cont = grub_get_time_ms () < timeout;
      if (err == GRUB_ERR_UNKNOWN_DEVICE && cont)
        {
          grub_dprintf ("ofdisk","Failed to open disk %s. Retrying...\n", name);
          grub_errno = GRUB_ERR_NONE;
        }
      else
          break;
      grub_millisleep (1000);
    } while (cont);
  return err;
}

static void
grub_ofdisk_close (grub_disk_t disk)
{
  disk->data = 0;
}

static grub_err_t
grub_ofdisk_prepare (grub_disk_t disk, grub_disk_addr_t sector)
{
  grub_ssize_t status;
  unsigned long long pos;

  if (disk->data != last_devpath)
    {
      if (last_ihandle)
	grub_ieee1275_close (last_ihandle);
      last_ihandle = 0;
      last_devpath = NULL;

      grub_ieee1275_open (disk->data, &last_ihandle);
      if (! last_ihandle)
	return grub_error (GRUB_ERR_UNKNOWN_DEVICE, "can't open device");
      last_devpath = disk->data;
    }

  pos = sector << disk->log_sector_size;

  grub_ieee1275_seek (last_ihandle, pos, &status);
  if (status < 0)
    return grub_error (GRUB_ERR_READ_ERROR,
		       "seek error, can't seek block %llu",
		       (long long) sector);
  return 0;
}

static grub_err_t
grub_ofdisk_read_real (grub_disk_t disk, grub_disk_addr_t sector,
		  grub_size_t size, char *buf)
{
  grub_err_t err;
  grub_ssize_t actual;
  err = grub_ofdisk_prepare (disk, sector);
  if (err)
    return err;
  grub_ieee1275_read (last_ihandle, buf, size  << disk->log_sector_size,
		      &actual);
  if (actual != (grub_ssize_t) (size  << disk->log_sector_size))
    return grub_error (GRUB_ERR_READ_ERROR, N_("failure reading sector 0x%llx "
					       "from `%s'"),
		       (unsigned long long) sector,
		       disk->name);

  return 0;
}

static grub_err_t
grub_ofdisk_read (grub_disk_t disk, grub_disk_addr_t sector,
		  grub_size_t size, char *buf)
{
  grub_err_t err;
  grub_uint64_t timeout = grub_get_time_ms () + (grub_ofdisk_disk_timeout (disk) * 1000);
  _Bool cont;
  do
    {
      err = grub_ofdisk_read_real (disk, sector, size, buf);
      cont = grub_get_time_ms () < timeout;
      if (err == GRUB_ERR_UNKNOWN_DEVICE && cont)
        {
          grub_dprintf ("ofdisk","Failed to read disk %s. Retrying...\n", (char*)disk->data);
          grub_errno = GRUB_ERR_NONE;
        }
      else
          break;
      grub_millisleep (1000);
     } while (cont);
  return err;
}

static grub_err_t
grub_ofdisk_write (grub_disk_t disk, grub_disk_addr_t sector,
		   grub_size_t size, const char *buf)
{
  grub_err_t err;
  grub_ssize_t actual;
  err = grub_ofdisk_prepare (disk, sector);
  if (err)
    return err;
  grub_ieee1275_write (last_ihandle, buf, size  << disk->log_sector_size,
		       &actual);
  if (actual != (grub_ssize_t) (size << disk->log_sector_size))
    return grub_error (GRUB_ERR_WRITE_ERROR, N_("failure writing sector 0x%llx "
						"to `%s'"),
		       (unsigned long long) sector,
		       disk->name);

  return 0;
}

static struct grub_disk_dev grub_ofdisk_dev =
  {
    .name = "ofdisk",
    .id = GRUB_DISK_DEVICE_OFDISK_ID,
    .disk_iterate = grub_ofdisk_iterate,
    .disk_open = grub_ofdisk_open,
    .disk_close = grub_ofdisk_close,
    .disk_read = grub_ofdisk_read,
    .disk_write = grub_ofdisk_write,
    .next = 0
  };

static char *
get_parent_devname (const char *devname, int *is_nvmeof)
{
  char *parent, *pptr;

  if (is_nvmeof)
    *is_nvmeof = 0;

  parent = grub_strdup (devname);

  if (parent == NULL)
    {
      grub_print_error ();
      return NULL;
    }

  pptr = grub_strstr (parent, IEEE1275_DISK_ALIAS);

  if (pptr != NULL)
    {
      *pptr = '\0';
      return parent;
    }

  pptr = grub_strstr (parent, IEEE1275_NVMEOF_DISK_ALIAS);

  if (pptr != NULL)
    {
      *pptr = '\0';
      if (is_nvmeof)
	*is_nvmeof = 1;
      return parent;
    }

  return parent;
}


static int
is_canonical (const char *path)
{
  if (grub_strstr (path, IEEE1275_DISK_ALIAS) ||
      grub_strstr (path, IEEE1275_NVMEOF_DISK_ALIAS))
    return 1;
  else
    return 0;
}

static char *
get_boot_device_parent (const char *bootpath, int *is_nvmeof)
{
  char *canon, *parent;

  if (is_canonical (bootpath))
    {
      early_log ("Use %s as canonical\n", bootpath);
      canon = grub_strdup (bootpath);
    }
  else
    {
      char *dev;

      dev = grub_ieee1275_get_aliasdevname (bootpath);
      canon = grub_ieee1275_canonicalise_devname (dev);
      early_log ("bootpath: %s \n", bootpath);
      early_log ("alias: %s\n", dev);
      early_log ("canonical: %s\n", canon);
    }

  if (!canon)
    {
      /* This should not happen. */
      grub_error (GRUB_ERR_BAD_DEVICE, "canonicalise devname failed");
      grub_print_error ();
      return NULL;
    }

  parent = get_parent_devname (canon, is_nvmeof);
  early_log ("%s is parent of %s\n", parent, canon);

  grub_free (canon);
  return parent;
}

static void
insert_bootpath (void)
{
  char *bootpath;
  grub_ssize_t bootpath_size;
  char *type;

  if (grub_ieee1275_get_property_length (grub_ieee1275_chosen, "bootpath",
					 &bootpath_size)
      || bootpath_size <= 0)
    {
      /* Should never happen.  */
      grub_printf ("/chosen/bootpath property missing!\n");
      return;
    }

  bootpath = (char *) grub_malloc ((grub_size_t) bootpath_size + 64);
  if (! bootpath)
    {
      grub_print_error ();
      return;
    }
  grub_ieee1275_get_property (grub_ieee1275_chosen, "bootpath", bootpath,
                              (grub_size_t) bootpath_size + 1, 0);
  bootpath[bootpath_size] = '\0';

  /* Transform an OF device path to a GRUB path.  */

  type = grub_ieee1275_get_device_type (bootpath);
  if (!(type && grub_strcmp (type, "network") == 0))
    {
      struct ofdisk_hash_ent *op;
      char *device = grub_ieee1275_get_devname (bootpath);
      op = ofdisk_hash_add (device, NULL);
      op->is_boot = 1;
      boot_parent = get_boot_device_parent (bootpath, &is_boot_nvmeof);
      boot_type =  grub_ieee1275_get_device_type (boot_parent);
      if (boot_type)
	early_log ("the boot device type: %s\n", boot_type);
      else
	early_log ("the boot device type is unknown\n");
    }
  grub_free (type);
  grub_free (bootpath);
}

void
grub_ofdisk_fini (void)
{
  if (last_ihandle)
    grub_ieee1275_close (last_ihandle);
  last_ihandle = 0;
  last_devpath = NULL;

  grub_disk_dev_unregister (&grub_ofdisk_dev);
}

static const char *
grub_env_get_boot_type (struct grub_env_var *var __attribute__ ((unused)),
			const char *val __attribute__ ((unused)))
{
  static char *ret;

  if (!ret)
    ret = grub_xasprintf("boot: %s type: %s is_nvmeof? %d",
	      boot_parent,
	      boot_type ? : "unknown",
	      is_boot_nvmeof);

  return ret;
}

static char *
grub_env_set_boot_type (struct grub_env_var *var __attribute__ ((unused)),
			const char *val __attribute__ ((unused)))
{
  /* READ ONLY */
  return NULL;
}

static grub_err_t
grub_cmd_early_msg (struct grub_command *cmd __attribute__ ((unused)),
		   int argc __attribute__ ((unused)),
		   char *argv[] __attribute__ ((unused)))
{
  print_early_log ();
  return 0;
}

static grub_command_t cmd_early_msg;

void
grub_ofdisk_init (void)
{
  grub_disk_firmware_fini = grub_ofdisk_fini;

  insert_bootpath ();
  grub_register_variable_hook ("ofdisk_boot_type", grub_env_get_boot_type,
                               grub_env_set_boot_type );

  cmd_early_msg =
    grub_register_command ("ofdisk_early_msg", grub_cmd_early_msg,
			   0, N_("Show early boot message in ofdisk."));
  grub_disk_dev_register (&grub_ofdisk_dev);
}

static grub_err_t
grub_ofdisk_get_block_size (grub_uint32_t *block_size,
			    struct ofdisk_hash_ent *op)
{
  struct size_args_ieee1275
    {
      struct grub_ieee1275_common_hdr common;
      grub_ieee1275_cell_t method;
      grub_ieee1275_cell_t ihandle;
      grub_ieee1275_cell_t result;
      grub_ieee1275_cell_t size1;
      grub_ieee1275_cell_t size2;
    } args_ieee1275;

  *block_size = 0;

  if (op->block_size_fails >= 2)
    return GRUB_ERR_NONE;

  INIT_IEEE1275_COMMON (&args_ieee1275.common, "call-method", 2, 2);
  args_ieee1275.method = (grub_ieee1275_cell_t) "block-size";
  args_ieee1275.ihandle = last_ihandle;
  args_ieee1275.result = 1;

  if (IEEE1275_CALL_ENTRY_FN (&args_ieee1275) == -1)
    {
      grub_dprintf ("disk", "can't get block size: failed call-method\n");
      op->block_size_fails++;
    }
  else if (args_ieee1275.result)
    {
      grub_dprintf ("disk", "can't get block size: %lld\n",
		    (long long) args_ieee1275.result);
      op->block_size_fails++;
    }
  else if (args_ieee1275.size1
	   && !(args_ieee1275.size1 & (args_ieee1275.size1 - 1))
	   && args_ieee1275.size1 >= 512 && args_ieee1275.size1 <= 16384)
    {
      op->block_size_fails = 0;
      *block_size = args_ieee1275.size1;
    }

  return 0;
}

struct ofdisk_early_msg
{
  struct ofdisk_early_msg *next;
  char *msg;
};

static struct ofdisk_early_msg *early_msg_head;
static struct ofdisk_early_msg **early_msg_last = &early_msg_head;

static void
early_log (const char *fmt, ...)
{
  struct ofdisk_early_msg *n;
  va_list args;

  grub_error_push ();
  n = grub_malloc (sizeof (*n));
  if (!n)
    {
      grub_errno = 0;
      grub_error_pop ();
      return;
    }
  n->next = 0;

  va_start (args, fmt);
  n->msg = grub_xvasprintf (fmt, args);
  va_end (args);

  *early_msg_last = n;
  early_msg_last = &n->next;

  grub_errno = 0;
  grub_error_pop ();
}

static void
print_early_log (void)
{
  struct ofdisk_early_msg *cur;

  if (!early_msg_head)
    grub_printf ("no early log is available\n");
  for (cur = early_msg_head; cur; cur = cur->next)
    grub_printf ("%s\n", cur->msg);
}
