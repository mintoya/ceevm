#ifndef CEEVM_BITINT_H
#define CEEVM_BITINT_H
#include "u8slice.h"

#include <stdint.h>
#include <stdbool.h>
typedef union {
  uint64_t as64;
  uint32_t as32;
  uint8_t as8;
} BitBuf;

int32_t eval_bitint_first_set(int32_t bits, BitBuf *op);
bool eval_bitint_overflow(int32_t bits, BitBuf *src, int32_t chk_bits,
                          bool is_unsigned);
bool eval_bitint_to_bool(int32_t bits, BitBuf *op);
int eval_bitint_cmp(int32_t bits, BitBuf *lh, BitBuf *rh, bool is_unsigned);
void eval_bitint_sign_ext(int32_t bits, BitBuf *op, int32_t bits2,
                          bool is_unsigned);
void eval_bitint_neg(int32_t bits, BitBuf *op);
void eval_bitint_bitnot(int32_t bits, BitBuf *op);
void eval_bitint_bitand(int32_t bits, BitBuf *lh, BitBuf *rh);
void eval_bitint_bitor(int32_t bits, BitBuf *lh, BitBuf *rh);
void eval_bitint_bitxor(int32_t bits, BitBuf *lh, BitBuf *rh);
void eval_bitint_shl(int32_t bits, BitBuf *src, BitBuf *dst, int32_t amount);
void eval_bitint_shr(int32_t bits, BitBuf *src, BitBuf *dst, int32_t amount,
                     bool is_unsigned);
void *eval_bitint_bitfield_load(int32_t bits, BitBuf *src, BitBuf *dst,
                                int32_t width, int32_t ofs, bool is_unsigned);
void eval_bitint_bitfield_save(int32_t bits, BitBuf *src, BitBuf *dst,
                               int32_t width, int32_t ofs);
void eval_bitint_add(int32_t bits, const BitBuf *lh, BitBuf *rh);
void eval_bitint_sub(int32_t bits, const BitBuf *lh, BitBuf *rh);
void eval_bitint_mul(int32_t bits, const BitBuf *lh, BitBuf *rh);
void eval_bitint_div(int32_t bits, BitBuf *lh, BitBuf *rh, bool is_unsigned,
                     bool is_div);

#endif
