/*
 * libdpkg - Debian packaging suite library routines
 * t-buffer.c - test buffer handling
 *
 * Copyright © 2009-2010 Guillem Jover <guillem@debian.org>
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

#include <dpkg/test.h>
#include <dpkg/buffer.h>
#include <dpkg/dpkg.h>

#include <stdio.h>

static void
test_buffer_hash(void)
{
	const char str_test[] = "this is a test string\n";
	const char str_empty[] = "";
	char hash[MD5HASHLEN + 1];

	buffer_md5(str_empty, hash, strlen(str_empty));
	test_str(hash, ==, "d41d8cd98f00b204e9800998ecf8427e");

	buffer_md5(str_test, hash, strlen(str_test));
	test_str(hash, ==, "475aae3b885d70a9130eec23ab33f2b9");
}

static void
test(void)
{
	test_buffer_hash();
}
