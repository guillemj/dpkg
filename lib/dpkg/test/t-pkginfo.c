/*
 * libdpkg - Debian packaging suite library routines
 * t-pkginfo.c - test pkginfo handling
 *
 * Copyright © 2009-2010,2012 Guillem Jover <guillem@debian.org>
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

#include <config.h>
#include <compat.h>

#include <dpkg/test.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg.h>

static void
test_pkginfo_informative(void)
{
	struct pkginfo pkg;

	pkg_blank(&pkg);
	test_fail(pkg_is_informative(&pkg, &pkg.installed));

	pkg_set_want(&pkg, want_purge);
	test_pass(pkg_is_informative(&pkg, &pkg.installed));

	pkg_blank(&pkg);
	pkg.installed.description = "test description";
	test_pass(pkg_is_informative(&pkg, &pkg.installed));

	/* FIXME: Complete. */
}

static void
test_pkginfo_eflags(void)
{
	struct pkginfo pkg;

	pkg_blank(&pkg);
	test_pass(pkg.eflag == eflag_ok);

	pkg_set_eflags(&pkg, eflag_reinstreq);
	test_pass(pkg.eflag == eflag_reinstreq);

	pkg_clear_eflags(&pkg, eflag_reinstreq);
	test_pass(pkg.eflag == eflag_ok);

	pkg_set_eflags(&pkg, 0x11);
	test_pass(pkg.eflag == 0x11);
	pkg_reset_eflags(&pkg);
	test_pass(pkg.eflag == eflag_ok);
}

static void
test_pkginfo_instance_tracking(void)
{
	struct pkgset set;
	struct pkginfo pkg2, pkg3, pkg4;

	pkgset_blank(&set);
	pkg_blank(&pkg2);
	pkg_blank(&pkg3);
	pkg_blank(&pkg4);

	test_pass(pkgset_installed_instances(&set) == 0);

	/* Link the other instances into the pkgset. */
	pkgset_link_pkg(&set, &pkg4);
	pkgset_link_pkg(&set, &pkg3);
	pkgset_link_pkg(&set, &pkg2);

	/* Test installation state transitions. */
	pkg_set_status(&pkg4, stat_installed);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_installed);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_triggerspending);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_triggersawaited);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_halfconfigured);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_unpacked);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_halfinstalled);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_configfiles);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_notinstalled);
	test_pass(pkgset_installed_instances(&set) == 0);

	pkg_set_status(&pkg4, stat_notinstalled);
	test_pass(pkgset_installed_instances(&set) == 0);

	/* Toggle installation states on various packages. */
	pkg_set_status(&pkg4, stat_installed);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg2, stat_halfinstalled);
	test_pass(pkgset_installed_instances(&set) == 2);

	pkg_set_status(&set.pkg, stat_configfiles);
	test_pass(pkgset_installed_instances(&set) == 3);

	pkg_set_status(&pkg3, stat_notinstalled);
	test_pass(pkgset_installed_instances(&set) == 3);

	pkg_set_status(&pkg3, stat_unpacked);
	test_pass(pkgset_installed_instances(&set) == 4);

	pkg_set_status(&set.pkg, stat_notinstalled);
	test_pass(pkgset_installed_instances(&set) == 3);

	pkg_set_status(&pkg2, stat_notinstalled);
	test_pass(pkgset_installed_instances(&set) == 2);

	pkg_set_status(&pkg3, stat_notinstalled);
	test_pass(pkgset_installed_instances(&set) == 1);

	pkg_set_status(&pkg4, stat_notinstalled);
	test_pass(pkgset_installed_instances(&set) == 0);
}

static void
test(void)
{
	test_plan(28);

	test_pkginfo_informative();
	test_pkginfo_eflags();
	test_pkginfo_instance_tracking();

	/* FIXME: Complete. */
}
