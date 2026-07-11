#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "nifkit.h"

int main(void) {
  const char *nif = "(record@5,3,file.nim title@2,0#field# \"NIF\"@4,0)";
  void *bif = NULL;
  size_t bif_len = 0;
  assert(nifkit_nif_to_bif(nif, strlen(nif), &bif, &bif_len) == 0);
  assert(bif != NULL && bif_len > 0);

  void *decoded = NULL;
  size_t decoded_len = 0;
  assert(nifkit_validate_bif(bif, bif_len) == 0);
  assert(nifkit_bif_to_nif(bif, bif_len, &decoded, &decoded_len) == 0);
  assert(decoded_len == strlen(nif));
  assert(memcmp(decoded, nif, decoded_len) == 0);
  nifkit_free(decoded);

  void *bad_out = (void *)0x1;
  size_t bad_len = 999;
  assert(nifkit_bif_to_nif("not-bif", 7, &bad_out, &bad_len) != 0);
  assert(bad_out == NULL);
  assert(bad_len == 0);
  assert(strstr(nifkit_last_error(), "invalid BIF") != NULL);
  assert(nifkit_validate_bif("not-bif", 7) != 0);
  assert(strstr(nifkit_last_error(), "invalid BIF") != NULL);

  bad_out = (void *)0x1;
  bad_len = 999;
  assert(nifkit_nif_to_bif(NULL, 1, &bad_out, &bad_len) != 0);
  assert(bad_out == NULL);
  assert(bad_len == 0);
  assert(strstr(nifkit_last_error(), "input pointer is nil") != NULL);

  assert(nifkit_nif_to_bif(nif, strlen(nif), NULL, &bad_len) != 0);
  assert(strstr(nifkit_last_error(), "output pointers are required") != NULL);

  assert(nifkit_bif_to_nif(bif, bif_len, &decoded, NULL) != 0);
  assert(strstr(nifkit_last_error(), "output pointers are required") != NULL);

  assert(nifkit_bif_to_nif(bif, bif_len, &decoded, &decoded_len) == 0);
  assert(nifkit_last_error()[0] == '\0');
  nifkit_free(decoded);
  nifkit_free(bif);

  bif = NULL;
  bif_len = 0;
  assert(nifkit_nif_to_bif(NULL, 0, &bif, &bif_len) == 0);
  assert(bif != NULL && bif_len > 0);
  assert(nifkit_bif_to_nif(bif, bif_len, &decoded, &decoded_len) == 0);
  assert(decoded == NULL && decoded_len == 0);
  nifkit_free(decoded);
  nifkit_free(bif);

  const char nul_nif[] = "\"a\\00b\"";
  bif = NULL;
  bif_len = 0;
  assert(nifkit_nif_to_bif(nul_nif, sizeof(nul_nif) - 1, &bif, &bif_len) == 0);
  assert(nifkit_bif_to_nif(bif, bif_len, &decoded, &decoded_len) == 0);
  assert(decoded_len == sizeof(nul_nif) - 1);
  assert(memcmp(decoded, nul_nif, decoded_len) == 0);
  nifkit_free(decoded);
  nifkit_free(bif);

  puts("nifkit C ABI contract passed");
  return 0;
}
