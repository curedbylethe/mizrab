/*
 * One implementation unit for the vendored audio sources.
 *
 * stb_vorbis.c is the upstream single file (no separate header exists). It is
 * included in full, before miniaudio.h: that defines
 * STB_VORBIS_INCLUDE_STB_VORBIS_H, which is the only switch that compiles
 * miniaudio's Vorbis decoder in. Do not include it from any other unit, or
 * its implementation would be compiled twice.
 */
#include "stb_vorbis.c"

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
