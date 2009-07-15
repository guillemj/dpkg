/*
 * libdpkg - Debian packaging suite library routines
 * t-path.c - test path handling code
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

#include <dpkg/test.h>
#include <dpkg-priv.h>

#include <stdlib.h>

/* Use the test_trim_eq_ref macro to avoid leaking the string and to get
 * meaningful line numbers from assert. */
#define test_trim_eq_ref(p, ref) \
do { \
	char *t = strdup((p)); \
	path_rtrim_slash_slashdot(t); \
	test_str(t, ==, (ref)); \
	free(t); \
} while (0)

static void
test_path_rtrim(void)
{
	test_trim_eq_ref("./././.", ".");
	test_trim_eq_ref("./././", ".");
	test_trim_eq_ref("./.", ".");
	test_trim_eq_ref("./", ".");
	test_trim_eq_ref("/./././.", "/");
	test_trim_eq_ref("/./", "/");
	test_trim_eq_ref("/.", "/");
	test_trim_eq_ref("/", "/");
	test_trim_eq_ref("", "");
	test_trim_eq_ref("/./../.", "/./..");
	test_trim_eq_ref("/foo/bar/./", "/foo/bar");
	test_trim_eq_ref("./foo/bar/./", "./foo/bar");
	test_trim_eq_ref("/./foo/bar/./", "/./foo/bar");
}

static void
test_path_skip(void)
{
	test_str(path_skip_slash_dotslash("./././."), ==, ".");
	test_str(path_skip_slash_dotslash("./././"), ==, "");
	test_str(path_skip_slash_dotslash("./."), ==, ".");
	test_str(path_skip_slash_dotslash("./"), ==, "");
	test_str(path_skip_slash_dotslash("/./././."), ==, ".");
	test_str(path_skip_slash_dotslash("/./"), ==, "");
	test_str(path_skip_slash_dotslash("/."), ==, ".");
	test_str(path_skip_slash_dotslash("/"), ==, "");
	test_str(path_skip_slash_dotslash("/./../."), ==, "../.");
	test_str(path_skip_slash_dotslash("/foo/bar/./"), ==, "foo/bar/./");
	test_str(path_skip_slash_dotslash("./foo/bar/./"), ==, "foo/bar/./");
	test_str(path_skip_slash_dotslash("/./foo/bar/./"), ==, "foo/bar/./");
}

static void
test(void)
{
	test_path_rtrim();
	test_path_skip();
}

