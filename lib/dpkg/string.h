/*
 * libdpkg - Debian packaging suite library routines
 * string.h - string handling routines
 *
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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef LIBDPKG_STRING_H
#define LIBDPKG_STRING_H

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

char *str_escape_fmt(char *dest, const char *src, size_t n);
char *str_strip_quotes(char *str);

DPKG_END_DECLS

#endif /* LIBDPKG_STRING_H */

