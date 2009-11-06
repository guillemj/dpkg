/*
 * libdpkg - Debian packaging suite library routines
 * macros.h - C language support macros
 *
 * Copyright © 2008, 2009 Guillem Jover <guillem@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2,
 * or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#ifndef LIBDPKG_MACROS_H
#define LIBDPKG_MACROS_H

/* Language definitions. */

#if HAVE_C_ATTRIBUTE
#define DPKG_ATTR_UNUSED	__attribute__((unused))
#define DPKG_ATTR_CONST		__attribute__((const))
#define DPKG_ATTR_NORET		__attribute__((noreturn))
#define DPKG_ATTR_PRINTF(n)	__attribute__((format(printf, n, n + 1)))
#else
#define DPKG_ATTR_UNUSED
#define DPKG_ATTR_CONST
#define DPKG_ATTR_NORET
#define DPKG_ATTR_PRINTF(n)
#endif

#ifdef __cplusplus
#define DPKG_BEGIN_DECLS	extern "C" {
#define DPKG_END_DECLS		}
#else
#define DPKG_BEGIN_DECLS
#define DPKG_END_DECLS
#endif

#ifndef sizeof_array
#define sizeof_array(a) (sizeof(a) / sizeof((a)[0]))
#endif

#ifndef min
#define min(a, b) ((a) < (b) ? (a) : (b))
#endif

#ifndef max
#define max(a, b) ((a) > (b) ? (a) : (b))
#endif

#endif /* LIBDPKG_MACROS_H */

