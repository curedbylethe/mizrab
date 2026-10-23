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

#include <stdio.h>
#include <string.h>

/* One device and one context: the engine plays one stream at a time. */
static ma_context g_context;
static ma_device g_device;
static int g_context_ready = 0;
static ma_decoder g_decoder;
static int g_decoder_ready = 0;
static int g_length_cached = 0;
static int g_is_vorbis = 0;
static ma_uint64 g_length = 0;
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

int mizrab_ma_set_volume(void* device, float volume)
{
    ma_result result;

    if (device == NULL) {
        g_last_error = "no device";
        return -1;
    }

    result = ma_device_set_master_volume((ma_device*)device, volume);
    return result == MA_SUCCESS ? 0 : mizrab_ma_fail(result);
}

float mizrab_ma_get_volume(void* device)
{
    float volume;

    if (device == NULL || ma_device_get_master_volume((ma_device*)device, &volume) != MA_SUCCESS) {
        return -1.0f;
    }

    return volume;
}

/* Vorbis length is reported as unknown on purpose. For a file, miniaudio's
 * stb_vorbis backend does return a length, but it is stb_vorbis's granule
 * estimate and drifts from the frames actually decoded (about 0.5% on the
 * fixture), and miniaudio keeps its backend vtables file-static, so the
 * detected format cannot be read from the decoder. The only Vorbis the build
 * decodes is Ogg, so the container magic stands in for "detected as Vorbis".
 * shortcut: magic sniff is Ogg-only, replace it if another Ogg codec is added. */
static int mizrab_ma_is_ogg(const char* path)
{
    char magic[4] = { 0 };
    FILE* file = fopen(path, "rb");

    if (file == NULL) {
        return 0;
    }

    if (fread(magic, 1, sizeof magic, file) != sizeof magic) {
        memset(magic, 0, sizeof magic);
    }
    fclose(file);

    return memcmp(magic, "OggS", sizeof magic) == 0;
}

int mizrab_ma_decoder_create(const char* path, unsigned int sample_rate, unsigned int channels)
{
    ma_decoder_config config;
    ma_result result;

    if (g_decoder_ready) {
        g_last_error = "decoder already open";
        return -1;
    }

    /* No encodingFormat: miniaudio picks the decoder from the extension, then
     * by trial, so the shim has no format logic. */
    config = ma_decoder_config_init(ma_format_f32, channels, sample_rate);
    result = ma_decoder_init_file(path, &config, &g_decoder);
    if (result != MA_SUCCESS) {
        return mizrab_ma_fail(result);
    }

    g_decoder_ready = 1;
    g_length_cached = 0;
    g_is_vorbis = mizrab_ma_is_ogg(path);
    return 0;
}

int mizrab_ma_decoder_read(void* output, unsigned long long frames, unsigned long long* frames_read)
{
    ma_uint64 count = 0;
    ma_result result;

    if (!g_decoder_ready) {
        g_last_error = "no decoder";
        return -1;
    }

    result = ma_decoder_read_pcm_frames(&g_decoder, output, frames, &count);
    *frames_read = count;
    if (result != MA_SUCCESS && result != MA_AT_END) {
        return mizrab_ma_fail(result);
    }

    return 0;
}

int mizrab_ma_decoder_seek(unsigned long long frame)
{
    ma_result result;

    if (!g_decoder_ready) {
        g_last_error = "no decoder";
        return -1;
    }

    result = ma_decoder_seek_to_pcm_frame(&g_decoder, frame);
    return result == MA_SUCCESS ? 0 : mizrab_ma_fail(result);
}

static void mizrab_ma_decoder_measure(void)
{
    ma_uint64 length = 0;

    if (!g_decoder_ready || g_length_cached) {
        return;
    }

    if (!g_is_vorbis && ma_decoder_get_length_in_pcm_frames(&g_decoder, &length) != MA_SUCCESS) {
        length = 0;
    }

    g_length = length;
    g_length_cached = 1;
}

unsigned long long mizrab_ma_decoder_length_frames(void)
{
    mizrab_ma_decoder_measure();
    return g_length;
}

int mizrab_ma_decoder_length_known(void)
{
    mizrab_ma_decoder_measure();
    return g_length > 0;
}

void mizrab_ma_decoder_destroy(void)
{
    if (g_decoder_ready) {
        ma_decoder_uninit(&g_decoder);
        g_decoder_ready = 0;
    }

    g_length = 0;
    g_length_cached = 0;
}
