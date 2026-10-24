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

#include "library_shim.h"

#include <stdio.h>
#include <sys/stat.h>

int mizrab_library_stat(const char* path, long long* out)
{
    struct stat st;
    if (lstat(path, &st) != 0) {
        return -1;
    }
    out[0] = (long long)st.st_size;
    /* The nanosecond field is st_mtimespec on Darwin and st_mtim elsewhere; this
     * is the only platform conditional in the library. */
#ifdef __APPLE__
    out[1] = (long long)st.st_mtimespec.tv_sec * 1000000000LL + st.st_mtimespec.tv_nsec;
#else
    out[1] = (long long)st.st_mtim.tv_sec * 1000000000LL + st.st_mtim.tv_nsec;
#endif
    out[2] = (S_ISDIR(st.st_mode) ? 1 : 0) | (S_ISREG(st.st_mode) ? 2 : 0) | (S_ISLNK(st.st_mode) ? 4 : 0);
    return 0;
}

int mizrab_library_read(const char* path, long long offset, int n, void* dst)
{
    FILE* f = fopen(path, "rb");
    if (f == NULL) {
        return -1;
    }
    if (offset != 0 && fseek(f, (long)offset, SEEK_SET) != 0) {
        fclose(f);
        return -1;
    }
    size_t got = n > 0 ? fread(dst, 1, (size_t)n, f) : 0;
    int failed = ferror(f);
    fclose(f);
    return failed ? -1 : (int)got;
}
