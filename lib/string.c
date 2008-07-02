/*
 * libdpkg - Debian packaging suite library routines
 * string.c - string handling routines
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008 Guillem Jover <guillem@debian.org>
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

#include <config.h>
#include <dpkg-priv.h>

char *
str_escape_fmt(char *dst, const char *src)
{
	char *d = dst;
	const char *s = src;

	while (*s) {
		if (*s == '%')
			*d++ = '%';
		*d++ = *s++;
	}

	*d = '\0';

	return d;
}

