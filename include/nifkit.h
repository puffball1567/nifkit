#ifndef NIFKIT_H
#define NIFKIT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct nifkit_limits {
  size_t max_input_bytes;
  size_t max_output_bytes;
  size_t max_nesting_depth;
  size_t max_tokens;
  size_t max_pool_entries;
  size_t max_pool_bytes;
  size_t max_string_bytes;
  size_t max_index_entries;
} nifkit_limits;

/*
 * Stable NIFKit C ABI.
 *
 * All payloads are byte slices: NUL termination is not required and returned
 * buffers may contain NUL bytes. Returns 0 on success. Output buffers are
 * released with nifkit_free.
 */
int nifkit_nif_to_bif(const void *nif_data, size_t nif_len,
                      void **out_bif, size_t *out_len);
int nifkit_bif_to_nif(const void *bif_data, size_t bif_len,
                      void **out_nif, size_t *out_len);
int nifkit_validate_bif(const void *bif_data, size_t bif_len);
int nifkit_nif_to_bif_with_limits(const void *nif_data, size_t nif_len,
                                  void **out_bif, size_t *out_len,
                                  const nifkit_limits *limits);
int nifkit_bif_to_nif_with_limits(const void *bif_data, size_t bif_len,
                                  void **out_nif, size_t *out_len,
                                  const nifkit_limits *limits);
int nifkit_validate_bif_with_limits(const void *bif_data, size_t bif_len,
                                    const nifkit_limits *limits);
void nifkit_free(void *buffer);
const char *nifkit_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
