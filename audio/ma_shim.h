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

/* Glue for miniaudio: Salam has no sizeof and cannot allocate an opaque
 * ma_device/ma_context/ma_decoder, so the structs live here as singletons:
 * one context, one device, one decoder. */

#ifndef MIZRAB_MA_SHIM_H
#define MIZRAB_MA_SHIM_H

typedef void (*mizrab_fill_proc)(void* device, void* output, const void* input, unsigned int frame_count);

void* mizrab_ma_create(mizrab_fill_proc fill, unsigned int sample_rate, unsigned int channels, int null_backend);
int mizrab_ma_start(void* device);
int mizrab_ma_stop(void* device);
void mizrab_ma_destroy(void* device);
const char* mizrab_ma_last_error(void);
const char* mizrab_ma_backend_name(void* device);

/* Device master volume, 0.0-1.0 (atomic, callback-safe). Control thread only.
 * set returns 0 or a ma_result code; get returns -1.0 on failure. */
int mizrab_ma_set_volume(void* device, float volume);
float mizrab_ma_get_volume(void* device);

/* The decoder. Only the thread that owns it may call these, one at a time.
 * Output is always f32 interleaved at the requested rate and channel count;
 * miniaudio converts. All return 0 on success or a ma_result code (-1 for a
 * shim-level error); mizrab_ma_last_error() describes the last failure. */
int mizrab_ma_decoder_create(const char* path, unsigned int sample_rate, unsigned int channels);
/* Reads up to frames; *frames_read < frames means end of stream (MA_AT_END
 * is reported as 0). */
int mizrab_ma_decoder_read(void* output, unsigned long long frames, unsigned long long* frames_read);
int mizrab_ma_decoder_seek(unsigned long long frame);
/* Output-rate frame count; 0 when unknown. Ogg Vorbis is reported as
 * unknown (see ma_shim.c); the MP3 count may scan the file, so it is cached. */
unsigned long long mizrab_ma_decoder_length_frames(void);
/* 1 when length_frames is a real duration. */
int mizrab_ma_decoder_length_known(void);
unsigned long long mizrab_ma_decoder_cursor(void);
void mizrab_ma_decoder_destroy(void);

/* Salam has no sizeof, so it cannot fill a timespec; hand it a scalar instead. */
long long mizrab_now_ns(void);

#endif
