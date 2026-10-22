/*
 * mizrab - a terminal music player built on basalam (2026)
 *
 *   +---------------+
 *   |  M I Z R A B  |
 *   +---------------+
 *
 * Built on the Salam standard library and basalam
 * Salam: https://github.com/SalamLang/Salam
 *
 * Repository: https://github.com/curedbylethe/mizrab
 * License: GPL-3.0-or-later
 *
 */

/* Spike-only glue: Salam has no sizeof and cannot allocate an opaque
 * ma_device/ma_context, so the two structs live here. */

#ifndef MIZRAB_MA_SHIM_H
#define MIZRAB_MA_SHIM_H

typedef void (*mizrab_fill_proc)(void* device, void* output, const void* input, unsigned int frame_count);

void* mizrab_ma_create(mizrab_fill_proc fill, unsigned int sample_rate, unsigned int channels, int null_backend);
int mizrab_ma_start(void* device);
int mizrab_ma_stop(void* device);
void mizrab_ma_destroy(void* device);
const char* mizrab_ma_last_error(void);
const char* mizrab_ma_backend_name(void* device);

#endif
