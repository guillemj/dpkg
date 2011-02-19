/*
 * libdpkg - Debian packaging suite library routines
 * t-verbuf.c - test varbuf implementation
 *
 * Copyright © 2009-2011 Guillem Jover <guillem@debian.org>
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
#include <dpkg/varbuf.h>

#include <string.h>
#include <stdlib.h>

static void
test_varbuf_init(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 0);
	test_pass(vb.used == 0);
	test_pass(vb.size == 0);
	test_pass(vb.buf == NULL);

	varbuf_destroy(&vb);
	test_pass(vb.used == 0);
	test_pass(vb.size == 0);
	test_pass(vb.buf == NULL);
}

static void
test_varbuf_prealloc(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 10);
	test_pass(vb.used == 0);
	test_pass(vb.size >= 10);
	test_pass(vb.buf != NULL);

	varbuf_destroy(&vb);
	test_pass(vb.used == 0);
	test_pass(vb.size == 0);
	test_pass(vb.buf == NULL);
}

static void
test_varbuf_grow(void)
{
	struct varbuf vb;
	size_t old_size;
	int i;

	varbuf_init(&vb, 10);

	/* Test that we grow when needed. */
	varbuf_grow(&vb, 100);
	test_pass(vb.used == 0);
	test_pass(vb.size >= 100);

	old_size = vb.size;

	/* Test that we are not leaking. */
	for (i = 0; i < 10; i++) {
		varbuf_grow(&vb, 100);
		test_pass(vb.used == 0);
		test_pass(vb.size >= 100);
		test_pass(vb.size == old_size);
	}

	/* Test that we grow when needed, with used space. */
	vb.used = 10;
	varbuf_grow(&vb, 100);
	test_pass(vb.used == 10);
	test_pass(vb.size >= 110);

	varbuf_destroy(&vb);
}

static void
test_varbuf_trunc(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 50);

	/* Test that we truncate (grow). */
	varbuf_trunc(&vb, 20);
	test_pass(vb.used == 20);
	test_pass(vb.size >= 50);

	/* Test that we truncate (shrink). */
	varbuf_trunc(&vb, 10);
	test_pass(vb.used == 10);
	test_pass(vb.size >= 50);

	varbuf_destroy(&vb);
}

static void
test_varbuf_addbuf(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 5);

	varbuf_add_buf(&vb, "1234567890", 10);
	test_pass(vb.used == 10);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "1234567890", 10);

	varbuf_add_buf(&vb, "abcde", 5);
	test_pass(vb.used == 15);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "1234567890abcde", 15);

	varbuf_destroy(&vb);
}

static void
test_varbuf_addc(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 1);

	varbuf_add_char(&vb, 'a');
	test_pass(vb.used == 1);
	test_pass(vb.size >= vb.used);
	test_pass(vb.buf[0] == 'a');

	varbuf_add_char(&vb, 'b');
	test_pass(vb.used == 2);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "ab", 2);

	varbuf_add_char(&vb, 'c');
	test_pass(vb.used == 3);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "abc", 3);

	varbuf_add_char(&vb, 'd');
	test_pass(vb.used == 4);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "abcd", 4);

	varbuf_destroy(&vb);
}

static void
test_varbuf_dup_char(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 5);

	varbuf_dup_char(&vb, 'z', 10);
	test_pass(vb.used == 10);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "zzzzzzzzzz", 10);

	varbuf_dup_char(&vb, 'y', 5);
	test_pass(vb.used == 15);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "zzzzzzzzzzyyyyy", 15);

	varbuf_destroy(&vb);
}

static void
test_varbuf_map_char(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 5);

	varbuf_add_buf(&vb, "1234a5678a9012a", 15);

	varbuf_map_char(&vb, 'a', 'z');
	test_pass(vb.used == 15);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "1234z5678z9012z", 15);

	varbuf_destroy(&vb);
}

static void
test_varbuf_printf(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 5);

	/* Test normal format printing. */
	varbuf_printf(&vb, "format %s number %d", "string", 10);
	test_pass(vb.used == strlen("format string number 10"));
	test_pass(vb.size >= vb.used);
	test_str(vb.buf, ==, "format string number 10");

	varbuf_reset(&vb);

	/* Test concatenated format printing. */
	varbuf_printf(&vb, "format %s number %d", "string", 10);
	varbuf_printf(&vb, " extra %s", "string");
	test_pass(vb.used == strlen("format string number 10 extra string"));
	test_pass(vb.size >= vb.used);
	test_str(vb.buf, ==, "format string number 10 extra string");

	varbuf_destroy(&vb);
}

static void
test_varbuf_reset(void)
{
	struct varbuf vb;

	varbuf_init(&vb, 10);

	varbuf_add_buf(&vb, "1234567890", 10);

	varbuf_reset(&vb);
	test_pass(vb.used == 0);
	test_pass(vb.size >= vb.used);

	varbuf_add_buf(&vb, "abcdefghijklmno", 15);
	test_pass(vb.used == 15);
	test_pass(vb.size >= vb.used);
	test_mem(vb.buf, ==, "abcdefghijklmno", 15);

	varbuf_destroy(&vb);
}

static void
test_varbuf_detach(void)
{
	struct varbuf vb;
	char *str;

	varbuf_init(&vb, 0);

	varbuf_add_buf(&vb, "1234567890", 10);

	str = varbuf_detach(&vb);

	test_mem(str, ==, "1234567890", 10);
	test_pass(vb.used == 0);
	test_pass(vb.size == 0);
	test_pass(vb.buf == NULL);

	free(str);
}

static void
test(void)
{
	test_varbuf_init();
	test_varbuf_prealloc();
	test_varbuf_grow();
	test_varbuf_trunc();
	test_varbuf_addbuf();
	test_varbuf_addc();
	test_varbuf_dup_char();
	test_varbuf_map_char();
	test_varbuf_printf();
	test_varbuf_reset();
	test_varbuf_detach();

	/* FIXME: Complete. */
}
