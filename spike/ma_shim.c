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

#include "miniaudio.h"
#include "ma_shim.h"

#include <time.h>

/* One device and one context: the spike plays one stream at a time. */
static ma_context g_context;
static ma_device g_device;
static int g_context_ready = 0;
static const char* g_last_error = "";

static int mizrab_ma_fail(ma_result result)
{
    g_last_error = ma_result_description(result);
    return (int)result;
}

const char* mizrab_ma_last_error(void)
{
    return g_last_error;
}

/* Read back which backend actually opened: CI has to tell ALSA from the null
 * timer, and "default" in a log does not answer that. */
const char* mizrab_ma_backend_name(void* device)
{
    if (device == NULL) {
        return "none";
    }

    return ma_get_backend_name(((ma_device*)device)->pContext->backend);
}

void* mizrab_ma_create(mizrab_fill_proc fill, unsigned int sample_rate, unsigned int channels, int null_backend)
{
    ma_result result;
    const ma_backend* backends = NULL;
    ma_uint32 backend_count = 0;
    ma_device_config config;

    /* The null backend is chosen through the context so CI never touches a
     * real device; otherwise NULL backends means "try every compiled backend". */
    if (null_backend) {
        static const ma_backend null_only[] = { ma_backend_null };
        backends = null_only;
        backend_count = 1;
    }

    result = ma_context_init(backends, backend_count, NULL, &g_context);
    if (result != MA_SUCCESS) {
        mizrab_ma_fail(result);
        return NULL;
    }
    g_context_ready = 1;

    config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = channels;
    config.sampleRate = sample_rate;
    config.dataCallback = (ma_device_data_proc)fill;
    config.pUserData = NULL;
    config.noPreSilencedOutputBuffer = MA_TRUE;

    result = ma_device_init(&g_context, &config, &g_device);
    if (result != MA_SUCCESS) {
        mizrab_ma_fail(result);
        ma_context_uninit(&g_context);
        g_context_ready = 0;
        return NULL;
    }

    return &g_device;
}

int mizrab_ma_start(void* device)
{
    ma_result result;

    if (device == NULL) {
        g_last_error = "no device";
        return -1;
    }

    result = ma_device_start((ma_device*)device);
    if (result != MA_SUCCESS) {
        return mizrab_ma_fail(result);
    }

    return 0;
}

int mizrab_ma_stop(void* device)
{
    ma_result result;

    if (device == NULL) {
        g_last_error = "no device";
        return -1;
    }

    result = ma_device_stop((ma_device*)device);
    if (result != MA_SUCCESS) {
        return mizrab_ma_fail(result);
    }

    return 0;
}

/* Monotonic nanoseconds for the in-callback timestamps. CLOCK_MONOTONIC is 6 on
 * macOS and 1 on Linux; the id stays here so Salam never sees it. */
long long mizrab_now_ns(void)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }

    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

/* ma_device_uninit joins the audio thread, so this is called from main only. */
void mizrab_ma_destroy(void* device)
{
    if (device != NULL) {
        ma_device_uninit((ma_device*)device);
    }

    if (g_context_ready) {
        ma_context_uninit(&g_context);
        g_context_ready = 0;
    }
}
