/*
 * libdpkg - Debian packaging suite library routines
 * t-pkginfo.c - test pkginfo handling
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

static void
test_pkginfo_informative(void)
{
	struct pkginfo pkg;

	pkg_blank(&pkg);
	test_fail(pkg_is_informative(&pkg, &pkg.installed));

	pkg.want = want_purge;
	test_pass(pkg_is_informative(&pkg, &pkg.installed));

	pkg_blank(&pkg);
	pkg.installed.description = "test description";
	test_pass(pkg_is_informative(&pkg, &pkg.installed));

	/* FIXME: Complete. */
}

static void
test(void)
{
	test_pkginfo_informative();

	/* FIXME: Complete. */
}

