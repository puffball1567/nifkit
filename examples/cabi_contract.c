#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "nifkit.h"

#ifdef NIFKIT_DYNAMIC_LOAD
#include <windows.h>

typedef int (*nifkit_nif_to_bif_fn)(const void *, size_t, void **, size_t *);
typedef int (*nifkit_bif_to_nif_fn)(const void *, size_t, void **, size_t *);
typedef int (*nifkit_validate_bif_fn)(const void *, size_t);
typedef void (*nifkit_free_fn)(void *);
typedef const char *(*nifkit_last_error_fn)(void);

static nifkit_nif_to_bif_fn p_nifkit_nif_to_bif;
static nifkit_bif_to_nif_fn p_nifkit_bif_to_nif;
static nifkit_validate_bif_fn p_nifkit_validate_bif;
static nifkit_free_fn p_nifkit_free;
static nifkit_last_error_fn p_nifkit_last_error;

#define nifkit_nif_to_bif p_nifkit_nif_to_bif
#define nifkit_bif_to_nif p_nifkit_bif_to_nif
#define nifkit_validate_bif p_nifkit_validate_bif
#define nifkit_free p_nifkit_free
#define nifkit_last_error p_nifkit_last_error

static void load_nifkit(void) {
  HMODULE lib = LoadLibraryA("nifkit.dll");
  assert(lib != NULL);
  p_nifkit_nif_to_bif =
      (nifkit_nif_to_bif_fn)GetProcAddress(lib, "nifkit_nif_to_bif");
  p_nifkit_bif_to_nif =
      (nifkit_bif_to_nif_fn)GetProcAddress(lib, "nifkit_bif_to_nif");
  p_nifkit_validate_bif =
      (nifkit_validate_bif_fn)GetProcAddress(lib, "nifkit_validate_bif");
  p_nifkit_free = (nifkit_free_fn)GetProcAddress(lib, "nifkit_free");
  p_nifkit_last_error =
      (nifkit_last_error_fn)GetProcAddress(lib, "nifkit_last_error");
  assert(p_nifkit_nif_to_bif != NULL);
  assert(p_nifkit_bif_to_nif != NULL);
  assert(p_nifkit_validate_bif != NULL);
  assert(p_nifkit_free != NULL);
  assert(p_nifkit_last_error != NULL);
}
#else
static void load_nifkit(void) {}
#endif

int main(void) {
  load_nifkit();

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
