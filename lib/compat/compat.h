/*
 * libcompat - system compatibility library
 * compat.h - system compatibility declarations
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008, 2009 Guillem Jover <guillem@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef COMPAT_H
#define COMPAT_H

#ifdef __cplusplus
extern "C" {
#endif

#ifndef HAVE_OFFSETOF
#define offsetof(st, m) ((size_t)&((st *)NULL)->m)
#endif

#ifndef HAVE_O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

/*
 * Define WCOREDUMP if we don't have it already, coredumps won't be
 * detected, though.
 */
#ifndef HAVE_WCOREDUMP
#define WCOREDUMP(x) 0
#endif

#ifndef HAVE_VA_COPY
#include <string.h>
#define va_copy(dest, src) memcpy(&(dest), &(src), sizeof(va_list))
#endif

#include <strnlen.h>

#ifndef HAVE_C99_SNPRINTF
#include <stddef.h>
#include <stdarg.h>

int snprintf(char *str, size_t n, char const *fmt, ...);
int vsnprintf(char *buf, size_t maxsize, const char *fmt, va_list args);
#endif

#ifndef HAVE_ASPRINTF
#include <stdarg.h>

int asprintf(char **str, char const *fmt, ...);
int vasprintf(char **str, const char *fmt, va_list args);
#endif

#ifndef HAVE_STRNDUP
#include <stddef.h>

#undef strndup
char *strndup(const char *s, size_t n);
#endif

#ifndef HAVE_STRERROR
const char *strerror(int);
#endif

#ifndef HAVE_STRSIGNAL
const char *strsignal(int);
#endif

#ifndef HAVE_SCANDIR
struct dirent;
int scandir(const char *dir, struct dirent ***namelist,
            int (*filter)(const struct dirent *),
            int (*cmp)(const void *, const void *));
#endif

#ifndef HAVE_ALPHASORT
int alphasort(const void *a, const void *b);
#endif

#ifndef HAVE_UNSETENV
int unsetenv(const char *x);
#endif

#ifdef __cplusplus
}
#endif

#endif /* COMPAT_H */
