/*
 * libdpkg - Debian packaging suite library routines
 * t-string.c - test string handling
 *
 * Copyright © 2009 Guillem Jover <guillem@debian.org>
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

#include <dpkg-test.h>
#include <dpkg-priv.h>

#include <string.h>

static void
test_str_escape_fmt(void)
{
	char buf[1024], *q;

	memset(buf, sizeof(buf), 'a');
	q = str_escape_fmt(buf, "");
	strcpy(q, " end");
	test_str(buf, ==, " end");

	memset(buf, sizeof(buf), 'a');
	q = str_escape_fmt(buf, "%");
	strcpy(q, " end");
	test_str(buf, ==, "%% end");

	memset(buf, sizeof(buf), 'a');
	q = str_escape_fmt(buf, "%%%");
	strcpy(q, " end");
	test_str(buf, ==, "%%%%%% end");

	memset(buf, sizeof(buf), 'a');
	q = str_escape_fmt(buf, "%b%b%c%c%%");
	strcpy(q, " end");
	test_str(buf, ==, "%%b%%b%%c%%c%%%% end");
}

static void
test(void)
{
	test_str_escape_fmt();
}

