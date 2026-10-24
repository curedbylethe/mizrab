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

/* Two filesystem primitives the Salam standard library lacks: an lstat that
 * reports size, mtime and kind in one call, and a binary-safe read of a bounded
 * slice of a file into a caller-owned buffer. */

#ifndef MIZRAB_LIBRARY_SHIM_H
#define MIZRAB_LIBRARY_SHIM_H

/* lstat (a symlink is reported, never followed). Fills out[0] = size in bytes,
 * out[1] = mtime in nanoseconds since the epoch, out[2] = flags: 1 directory,
 * 2 regular file, 4 symlink. Returns 0, or -1 when lstat fails. */
int mizrab_library_stat(const char* path, long long* out);

/* Reads up to n bytes starting at offset into dst. Returns the number of bytes
 * read (short at end of file, never padded), or -1 on an open, seek or read
 * error. */
int mizrab_library_read(const char* path, long long offset, int n, void* dst);

#endif
