/*
 * libcompat - system compatibility library
 * compat.h - system compatibility declarations
 *
 * Copyright © 1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
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

#ifndef TEST_LIBCOMPAT
#define TEST_LIBCOMPAT 0
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_STRNLEN) || !defined(HAVE_STRNDUP) || \
    !defined(HAVE_C99_SNPRINTF)
#include <stddef.h>
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_ASPRINTF) || !defined(HAVE_C99_SNPRINTF)
#include <stdarg.h>
#endif

#if  TEST_LIBCOMPAT || !defined(HAVE_VA_COPY)
#include <string.h>
#endif

/* Language definitions. */

#ifdef __GNUC__
#define LIBCOMPAT_GCC_VERSION (__GNUC__ << 8 | __GNUC_MINOR__)
#else
#define LIBCOMPAT_GCC_VERSION 0
#endif

#if LIBCOMPAT_GCC_VERSION >= 0x0300
#define LIBCOMPAT_ATTR_PRINTF(n)	__attribute__((format(printf, n, n + 1)))
#define LIBCOMPAT_ATTR_VPRINTF(n)	__attribute__((format(printf, n, 0)))
#else
#define LIBCOMPAT_ATTR_PRINTF(n)
#define LIBCOMPAT_ATTR_VPRINTF(n)
#endif

/* For C++, define a __func__ fallback in case it's not natively supported. */
#if defined(__cplusplus) && __cplusplus < 201103L
# if LIBCOMPAT_GCC_VERSION >= 0x0200
#  define __func__ __PRETTY_FUNCTION__
# else
#  define __func__ __FUNCTION__
# endif
#endif

#if defined(__cplusplus) && __cplusplus < 201103L
#define nullptr 0
#endif

#ifdef __cplusplus
extern "C" {
#endif

#ifndef HAVE_OFFSETOF
#define offsetof(st, m) ((size_t)&((st *)NULL)->m)
#endif

#ifndef HAVE_MAKEDEV
#define makedev(maj, min) ((((maj) & 0xff) << 8) | ((min) & 0xff))
#endif

#ifndef HAVE_O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

#ifndef HAVE_P_TMPDIR
#define P_tmpdir "/tmp"
#endif

/*
 * Define WCOREDUMP if we don't have it already, coredumps won't be
 * detected, though.
 */
#ifndef HAVE_WCOREDUMP
#define WCOREDUMP(x) 0
#endif

#ifndef HAVE_VA_COPY
#define va_copy(dest, src) memcpy(&(dest), &(src), sizeof(va_list))
#endif

#if TEST_LIBCOMPAT
#undef snprintf
#define snprintf test_snprintf
#undef vsnprintf
#define vsnprintf test_vsnprintf
#undef asprintf
#define asprintf test_asprintf
#undef vasprintf
#define vasprintf test_vasprintf
#undef strndup
#define strndup test_strndup
#undef strnlen
#define strnlen test_strnlen
#undef strerror
#define strerror test_strerror
#undef strsignal
#define strsignal test_strsignal
#undef scandir
#define scandir test_scandir
#undef alphasort
#define alphasort test_alphasort
#undef unsetenv
#define unsetenv test_unsetenv
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_C99_SNPRINTF)
int snprintf(char *str, size_t n, char const *fmt, ...)
	LIBCOMPAT_ATTR_PRINTF(3);
int vsnprintf(char *buf, size_t maxsize, const char *fmt, va_list args)
	LIBCOMPAT_ATTR_VPRINTF(3);
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_ASPRINTF)
int asprintf(char **str, char const *fmt, ...)
	LIBCOMPAT_ATTR_PRINTF(2);
int vasprintf(char **str, const char *fmt, va_list args)
	LIBCOMPAT_ATTR_VPRINTF(2);
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_STRNLEN)
size_t strnlen(const char *s, size_t n);
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_STRNDUP)
char *strndup(const char *s, size_t n);
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_STRERROR)
const char *strerror(int);
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_STRSIGNAL)
const char *strsignal(int);
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_SCANDIR)
struct dirent;
int scandir(const char *dir, struct dirent ***namelist,
            int (*filter)(const struct dirent *),
            int (*cmp)(const void *, const void *));
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_ALPHASORT)
int alphasort(const void *a, const void *b);
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_UNSETENV)
int unsetenv(const char *x);
#endif

#if TEST_LIBCOMPAT || !defined(HAVE_SETEXECFILECON)
int setexecfilecon(const char *filename, const char *fallback_type);
#endif

#ifdef __cplusplus
}
#endif

#endif /* COMPAT_H */
