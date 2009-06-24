/*
 * libdpkg - Debian packaging suite library routines
 * path.c - path handling functions
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
#include <compat.h>

#include <string.h>
#include <dpkg-priv.h>

size_t
path_rtrim_slash_slashdot(char *path)
{
	char *end;

	if (!path || !*path)
		return 0;

	for (end = path + strlen(path) - 1; end - path >= 1; end--) {
		if (*end == '/' || (*(end - 1) == '/' && *end == '.'))
			*end = '\0';
		else
			break;
	}

	return end - path + 1;
}

const char *
path_skip_slash_dotslash(const char *path)
{
	while (path[0] == '/' || (path[0] == '.' && path[1] == '/'))
		path++;

	return path;
}

