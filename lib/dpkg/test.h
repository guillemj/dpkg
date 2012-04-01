/*
 * libdpkg - Debian packaging suite library routines
 * test.h - test suite support
 *
 * Copyright © 2009-2012 Guillem Jover <guillem@debian.org>
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

#ifndef LIBDPKG_TEST_H
#define LIBDPKG_TEST_H

#include <assert.h>
#include <string.h>

#ifndef TEST_MAIN_PROVIDED
#include <dpkg/ehandle.h>
#endif

/* Make sure NDEBUG is never defined, as we rely on the assert() macro. */
#undef NDEBUG

/**
 * @defgroup dpkg_test Test suite support
 * @ingroup dpkg-internal
 * @{
 */

#define test_pass(a)			assert((a))
#define test_fail(a)			assert(!(a))
#define test_str(a, op, b)		assert(strcmp((a), (b)) op 0)
#define test_mem(a, op, b, size)	assert(memcmp((a), (b), (size)) op 0)

/** @} */

#ifndef TEST_MAIN_PROVIDED
static void test(void);

int
main(int argc, char **argv)
{
	push_error_context();

	test();

	pop_error_context(ehflag_normaltidy);

	return 0;
}
#endif

#endif
