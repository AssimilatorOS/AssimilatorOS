#ifndef GRUB_CRYPTTAB_HEADER
#define GRUB_CRYPTTAB_HEADER 1

#include <grub/types.h>
#include <grub/err.h>

typedef struct grub_crypto_key_list
{
  struct grub_crypto_key_list *next;
  struct grub_crypto_key_list **prev;
  char *name; /* UUID */
  char *path;
  char *key;
  grub_size_t key_len;
  int is_tpmkey;
} grub_crypto_key_list_t;

extern grub_crypto_key_list_t *EXPORT_VAR (cryptokey_lst);

grub_err_t
grub_cryptokey_add_or_update (const char *uuid, const char *key, grub_size_t key_len, const char *path, int is_tpmkey);

void
grub_cryptokey_discard (void);

void
grub_cryptokey_tpmkey_discard (void);
#endif /* ! GRUB_CRYPTTAB_HEADER */
