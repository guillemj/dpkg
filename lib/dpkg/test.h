/*
 * libdpkg - Debian packaging suite library routines
 * test.h - test suite support
 *
 * Copyright © 2009-2014 Guillem Jover <guillem@debian.org>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef LIBDPKG_TEST_H
#define LIBDPKG_TEST_H

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#ifndef TEST_MAIN_PROVIDED
#include <dpkg/ehandle.h>
#endif

/**
 * @defgroup dpkg_test Test suite support
 * @ingroup dpkg-internal
 * @{
 */

#define test_bail(reason) \
	do { \
		printf("Bail out! %s\n", (reason)); \
		exit(255); \
	} while (0)

#define test_xstringify(str) \
	#str
#define test_stringify(str) \
	test_xstringify(str)

static inline void *
test_alloc(void *ptr, const char *reason)
{
	if (ptr == NULL)
		test_bail(reason);
	return ptr;
}

#define test_alloc(ptr) \
	test_alloc((ptr), "cannot allocate memory for " #ptr " in " __FILE__ ":" test_stringify(__LINE__))

static int test_id = 1;
static int test_skip_code;
static const char *test_skip_prefix;
static const char *test_skip_reason;

#define test_plan(n) \
	printf("1..%d\n", n);

#define test_skip_all(reason) \
	do { \
		printf("1..0 # SKIP %s\n", (reason)); \
		exit(0); \
	} while (0)
#define test_skip(reason) \
	printf("ok %d # SKIP %s\n", test_id++, (reason))
#define test_skip_block(cond) \
	for (test_skip_prefix = " # SKIP ", \
	     test_skip_reason = cond ? #cond : NULL, \
	     test_skip_code = 1; \
	     test_skip_prefix; \
	     test_skip_prefix = test_skip_reason = NULL, test_skip_code = 0)

#define test_todo(a, reason, desc) \
	do { \
		test_skip_prefix = " # TODO "; \
		test_skip_reason = reason; \
		test_case(a, "%s", desc); \
		test_skip_prefix = test_skip_reason = NULL; \
	} while(0)
#define test_todo_block(reason) \
	for (test_skip_prefix = " # TODO ", test_skip_reason = reason; \
	     test_skip_prefix; \
	     test_skip_prefix = test_skip_reason = NULL)

#define test_case(a, fmt, ...) \
	printf("%sok %d - " fmt "%s%s\n", \
	       test_skip_code || (a) ? "" : "not ", \
	       test_id++, __VA_ARGS__, \
	       test_skip_reason ? test_skip_prefix : "", \
	       test_skip_reason ? test_skip_reason : "")

#define test_pass(a) \
	test_case((a), "pass %s", #a)
#define test_fail(a) \
	test_case(!(a), "fail %s", #a)
#define test_str(a, op, b) \
	test_case(strcmp((a), (b)) op 0, "strcmp '%s' %s '%s'", a, #op, b)
#define test_mem(a, op, b, size) \
	test_case(memcmp((a), (b), (size)) op 0, "memcmp %p %s %p", a, #op, b)

/** @} */

#ifndef TEST_MAIN_PROVIDED
static void test(void);

int
main(int argc, char **argv)
{
	setvbuf(stdout, NULL, _IOLBF, 0);

	push_error_context();

	test();

	pop_error_context(ehflag_normaltidy);

	return 0;
}
#endif

#endif
