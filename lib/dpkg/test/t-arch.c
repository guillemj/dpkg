/*
 * libdpkg - Debian packaging suite library routines
 * t-arch.c - test dpkg_arch implementation
 *
 * Copyright © 2011 Linaro Limited
 * Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
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
#include <dpkg/arch.h>

static void
test_dpkg_arch_name_is_illegal(void)
{
	/* Test invalid architecture names. */
	test_fail(dpkg_arch_name_is_illegal("") == NULL);
	test_fail(dpkg_arch_name_is_illegal("-i386") == NULL);
	test_fail(dpkg_arch_name_is_illegal(" i386") == NULL);
	test_fail(dpkg_arch_name_is_illegal(":any") == NULL);
	test_fail(dpkg_arch_name_is_illegal("amd64_test") == NULL);
	test_fail(dpkg_arch_name_is_illegal("i386:test") == NULL);
	test_fail(dpkg_arch_name_is_illegal("i386 amd64") == NULL);
	test_fail(dpkg_arch_name_is_illegal("i386,amd64") == NULL);
	test_fail(dpkg_arch_name_is_illegal("i386|amd64") == NULL);

	/* Test valid architecture names. */
	test_pass(dpkg_arch_name_is_illegal("i386") == NULL);
	test_pass(dpkg_arch_name_is_illegal("amd64") == NULL);
	test_pass(dpkg_arch_name_is_illegal("hurd-i386") == NULL);
	test_pass(dpkg_arch_name_is_illegal("kfreebsd-i386") == NULL);
	test_pass(dpkg_arch_name_is_illegal("kfreebsd-amd64") == NULL);
	test_pass(dpkg_arch_name_is_illegal("ia64") == NULL);
	test_pass(dpkg_arch_name_is_illegal("alpha") == NULL);
	test_pass(dpkg_arch_name_is_illegal("armel") == NULL);
	test_pass(dpkg_arch_name_is_illegal("hppa") == NULL);
	test_pass(dpkg_arch_name_is_illegal("mips") == NULL);
	test_pass(dpkg_arch_name_is_illegal("mipsel") == NULL);
	test_pass(dpkg_arch_name_is_illegal("powerpc") == NULL);
	test_pass(dpkg_arch_name_is_illegal("s390") == NULL);
	test_pass(dpkg_arch_name_is_illegal("sparc") == NULL);
}

static void
test_dpkg_arch_get_native(void)
{
	struct dpkg_arch *arch;

	arch = dpkg_arch_get_native();
	test_str(arch->name, ==, ARCHITECTURE);
	test_pass(arch->type == arch_native);
}

static void
test_dpkg_arch_get_list(void)
{
	struct dpkg_arch *arch;
	int count = 1;

	/* Must never return NULL. */
	arch = dpkg_arch_get_list();
	test_pass(arch != NULL);

	while ((arch = arch->next))
		count++;

	/* The default list should contain 3 architectures. */
	test_pass(count == 3);
}

static void
test_dpkg_arch_find(void)
{
	struct dpkg_arch *arch;

	/* Test existence and initial values of default architectures. */
	arch = dpkg_arch_find("all");
	test_pass(arch->type == arch_all);
	arch = dpkg_arch_find(ARCHITECTURE);
	test_pass(arch->type == arch_native);
	arch = dpkg_arch_find("any");
	test_pass(arch->type == arch_wildcard);

	/* Empty architectures are marked none. */
	arch = dpkg_arch_find(NULL);
	test_pass(arch->type == arch_none);
	test_str(arch->name, ==, "");
	arch = dpkg_arch_find("");
	test_pass(arch->type == arch_none);
	test_str(arch->name, ==, "");

	/* New valid architectures are marked unknown. */
	arch = dpkg_arch_find("foobar");
	test_pass(arch->type == arch_unknown);
	test_str(arch->name, ==, "foobar");

	/* New illegal architectures are marked illegal. */
	arch = dpkg_arch_find("a:b");
	test_pass(arch->type == arch_illegal);
	test_str(arch->name, ==, "a:b");
}

static void
test_dpkg_arch_reset_list(void)
{
	dpkg_arch_reset_list();

	test_dpkg_arch_get_list();
}

void
test(void)
{
	test_dpkg_arch_name_is_illegal();
	test_dpkg_arch_get_native();
	test_dpkg_arch_get_list();
	test_dpkg_arch_find();
	test_dpkg_arch_reset_list();
}
