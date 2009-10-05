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

#include <stdio.h>
#include <string.h>

#include <dpkg/path.h>

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

/*
 * snprintf(3) doesn't work if format contains %.<nnn>s and an argument has
 * invalid char for locale, then it returns -1.
 * ohshite() is ok, but fd_fd_copy(), which is used in tarobject() in this
 * file, is not ok, because
 * - fd_fd_copy() == buffer_copy_setup() [include/dpkg.h]
 * - buffer_copy_setup() uses varbufvprintf(&v, desc, al); [lib/mlib.c]
 * - varbufvprintf() fails and memory exausted, because it call
 *    fmt = "backend dpkg-deb during `%.255s'
 *    arg may contain some invalid char, for example,
 *    /usr/share/doc/console-tools/examples/unicode/\342\231\252\342\231\254
 *   in console-tools.
 *   In this case, if user uses some locale which doesn't support \342\231...,
 *   vsnprintf() always returns -1 and varbufextend() get called again
 *   and again until memory is exausted and it aborts.
 *
 * So, we need to escape invalid char, probably as in
 * tar-1.13.19/lib/quotearg.c: quotearg_buffer_restyled()
 * but here I escape all 8bit chars, in order to be simple.
 * - ukai@debian.or.jp
 */
char *
path_quote_filename(char *buf, size_t size, const char *s)
{
	char *r = buf;

	while (size > 0) {
		switch (*s) {
		case '\0':
			*buf = '\0';
			return r;
		case '\\':
			*buf++ = '\\';
			*buf++ = '\\';
			size -= 2;
			break;
		default:
			if (((*s) & 0x80) == '\0') {
				*buf++ = *s++;
				--size;
			} else {
				if (size > 4) {
					sprintf(buf, "\\%03o",
					        *(unsigned char *)s);
					size -= 4;
					buf += 4;
					s++;
				} else {
					/* Buffer full. */
					*buf = '\0'; /* XXX */
					return r;
				}
			}
		}
	}
	*buf = '\0'; /* XXX */

	return r;
}

