#ifndef GRUB_OFPATH_MACHINE_UTIL_HEADER
#define GRUB_OFPATH_MACHINE_UTIL_HEADER	1

char *grub_util_devname_to_ofpath (const char *devname);

struct ofpath_files_list_node {
  char* filename;
  struct ofpath_files_list_node* next;
};

struct ofpath_files_list_root {
  int items;
  struct ofpath_files_list_node* first;
};

struct ofpath_nvmeof_info {
  char* host_wwpn;
  char* target_wwpn;
  char* nqn;
  int cntlid;
  int nsid;
};

void of_path_get_nvmeof_adapter_info(char* sysfs_path,
                               struct ofpath_nvmeof_info* nvmeof_info);

unsigned int of_path_get_nvme_nsid(const char* devname);

void add_filename_to_pile(char *filename, struct ofpath_files_list_root* root);

void find_file(char* filename, char* directory, struct ofpath_files_list_root* root, int max_depth, int depth);

char* of_find_fc_host(char* host_wwpn);

char* nvme_get_syspath(const char *nvmedev);

char* block_device_get_sysfs_path_and_link(const char *devicenode);

char* xrealpath (const char *in);

unsigned int of_path_get_nvme_nsid(const char* devname);


#endif /* ! GRUB_OFPATH_MACHINE_UTIL_HEADER */
