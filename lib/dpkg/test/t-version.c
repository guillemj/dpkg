/*
 * libdpkg - Debian packaging suite library routines
 * t-version.c - test version handling
 *
 * Copyright © 2009 Guillem Jover <guillem@debian.org>
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
#include <dpkg/dpkg-db.h>

#define version(epoch, version, revision) \
	(struct versionrevision) { (epoch), (version), (revision) }

static void
test_version_compare(void)
{
	struct versionrevision a, b;

	blankversion(&a);
	blankversion(&b);
	test_fail(epochsdiffer(&a, &b));

	a.epoch = 1;
	b.epoch = 2;
	test_pass(epochsdiffer(&a, &b));

	/* Test for version equality. */
	a = b = version(0, "0", "0");
	test_pass(versioncompare(&a, &b) == 0);

	a = version(0, "0", "00");
	b = version(0, "00", "0");
	test_pass(versioncompare(&a, &b) == 0);

	a = b = version(1, "2", "3");
	test_pass(versioncompare(&a, &b) == 0);

	/* Test for epoch difference. */
	a = version(0, "0", "0");
	b = version(1, "0", "0");
	test_pass(versioncompare(&a, &b) < 0);
	test_pass(versioncompare(&b, &a) > 0);

	/* FIXME: Complete. */
}

static void
test_version_parse(void)
{
	struct versionrevision a, b;

	/* Test 0 versions. */
	blankversion(&a);
	b = version(0, "0", "");

	test_pass(parseversion(&a, "0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	test_pass(parseversion(&a, "0:0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	test_pass(parseversion(&a, "0:0-") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	b = version(0, "0", "0");
	test_pass(parseversion(&a, "0:0-0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	b = version(0, "0.0", "0.0");
	test_pass(parseversion(&a, "0:0.0-0.0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	/* Test epoched versions. */
	b = version(1, "0", "");
	test_pass(parseversion(&a, "1:0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	b = version(5, "1", "");
	test_pass(parseversion(&a, "5:1") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	/* Test multiple dashes. */
	b = version(0, "0-0", "0");
	test_pass(parseversion(&a, "0:0-0-0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	b = version(0, "0-0-0", "0");
	test_pass(parseversion(&a, "0:0-0-0-0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	/* Test multiple colons. */
	b = version(0, "0:0", "0");
	test_pass(parseversion(&a, "0:0:0-0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	b = version(0, "0:0:0", "0");
	test_pass(parseversion(&a, "0:0:0:0-0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	/* Test multiple dashes and colons. */
	b = version(0, "0:0-0", "0");
	test_pass(parseversion(&a, "0:0:0-0-0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	b = version(0, "0-0:0", "0");
	test_pass(parseversion(&a, "0:0-0:0-0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	/* Test valid characters in upstream version. */
	b = version(0, "azAZ09.-+~:", "0");
	test_pass(parseversion(&a, "0:azAZ09.-+~:-0") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	/* Test valid characters in revision. */
	b = version(0, "0", "azAZ09.+~");
	test_pass(parseversion(&a, "0:0-azAZ09.+~") == NULL);
	test_pass(versioncompare(&a, &b) == 0);

	/* Test invalid characters in epoch. */
	test_fail(parseversion(&a, "a:0-0") == NULL);
	test_fail(parseversion(&a, "A:0-0") == NULL);

	/* Test invalid characters in upstream version. */
	test_fail(parseversion(&a, "0:!#@$%&/|\\<>()[]{};,=*^'-0") == NULL);

	/* Test invalid characters in revision. */
	test_fail(parseversion(&a, "0:0-0:0") == NULL);
	test_fail(parseversion(&a, "0:0-!#@$%&/|\\<>()[]{}:;,=*^'") == NULL);

	/* FIXME: Complete. */
}

static void
test(void)
{
	test_version_compare();
	test_version_parse();
}
