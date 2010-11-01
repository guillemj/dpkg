/*
 * libdpkg - Debian packaging suite library routines
 * path.c - path handling functions
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008-2010 Guillem Jover <guillem@debian.org>
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

#include <config.h>
#include <compat.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <dpkg/varbuf.h>
#include <dpkg/path.h>

/**
 * Trim ‘/’ and ‘/.’ from the end of a pathname.
 *
 * The given string will get NUL-terminatd.
 *
 * @param path The pathname to trim.
 *
 * @return The size of the trimmed pathname.
 */
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

/**
 * Skip ‘/’ and ‘./’ from the beginning of a pathname.
 *
 * @param path The pathname to skip.
 *
 * @return The new beginning of the pathname.
 */
const char *
path_skip_slash_dotslash(const char *path)
{
	while (path[0] == '/' || (path[0] == '.' && path[1] == '/'))
		path++;

	return path;
}

/**
 * Create a template for a temporary pathname.
 *
 * @param suffix The suffix to use for the template string.
 *
 * @return An allocated string with the created template.
 */
char *
path_make_temp_template(const char *suffix)
{
	const char *tmpdir;
	struct varbuf template = VARBUF_INIT;

	tmpdir = getenv("TMPDIR");
#ifdef P_tmpdir
	if (!tmpdir)
		tmpdir = P_tmpdir;
#endif
	if (!tmpdir)
		tmpdir = "/tmp";

	varbufprintf(&template, "%s/%s.XXXXXX", tmpdir, suffix);

	return varbuf_detach(&template);
}

/**
 * Escape characters in a pathname for safe locale printing.
 *
 * We need to quote paths so that they do not cause problems when printing
 * them, for example with snprintf(3) which does not work if the format
 * string contains %s and an argument has invalid characters for the
 * current locale, it will then return -1.
 *
 * To simplify things, we just escape all 8 bit characters, instead of
 * just invalid characters.
 *
 * @param dst The escaped destination string.
 * @param src The source string to escape.
 * @param n The size of the destination buffer.
 *
 * @return The destination string.
 */
char *
path_quote_filename(char *dst, const char *src, size_t n)
{
	char *r = dst;
	ssize_t size = (ssize_t)n;

	if (size == 0)
		return r;

	while (*src) {
		if (*src == '\\') {
			size -= 2;
			if (size <= 0)
				break;

			*dst++ = '\\';
			*dst++ = '\\';
			src++;
		} else if (((*src) & 0x80) == '\0') {
			size--;
			if (size <= 0)
				break;

			*dst++ = *src++;
		} else {
			size -= 4;
			if (size <= 0)
				break;

			sprintf(dst, "\\%03o",
			        *(const unsigned char *)src);
			dst += 4;
			src++;
		}
	}

	*dst = '\0';

	return r;
}

