#ifndef NIFKIT_H
#define NIFKIT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

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
void nifkit_free(void *buffer);
const char *nifkit_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
