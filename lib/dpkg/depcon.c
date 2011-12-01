/*
 * libdpkg - Debian packaging suite library routines
 * depcon.c - dependency and conflict checking
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2009 Canonical Ltd.
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

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/arch.h>

bool
versionsatisfied(struct pkgbin *it, struct deppossi *against)
{
	return versionsatisfied3(&it->version, &against->version,
	                         against->verrel);
}

/**
 * Check if the architecture qualifier in the dependency is satisfied.
 *
 * The rules are supposed to be:
 * - unqualified Depends/Pre-Depends/Recommends/Suggests are only
 *   satisfied by a package of a different architecture if the target
 *   package is Multi-Arch: foreign.
 * - Depends/Pre-Depends/Recommends/Suggests on pkg:any are satisfied by
 *   a package of a different architecture if the target package is
 *   Multi-Arch: allowed.
 * - all other Depends/Pre-Depends/Recommends/Suggests are only
 *   satisfied by packages of the same architecture.
 * - Architecture: all packages are treated the same as packages of the
 *   native architecture.
 * - Conflicts/Replaces/Breaks are assumed to apply to packages of any arch.
 */
bool
archsatisfied(struct pkgbin *it, struct deppossi *against)
{
	const struct dpkg_arch *dep_arch, *pkg_arch;

	if (it->multiarch == multiarch_foreign)
		return true;

	dep_arch = against->arch;
	if (dep_arch->type == arch_wildcard &&
	    (it->multiarch == multiarch_allowed ||
	     against->up->type == dep_conflicts ||
	     against->up->type == dep_replaces ||
	     against->up->type == dep_breaks))
		return true;

	pkg_arch = it->arch;
	if (dep_arch->type == arch_none || dep_arch->type == arch_all)
		dep_arch = dpkg_arch_get(arch_native);
	if (pkg_arch->type == arch_none || pkg_arch->type == arch_all)
		pkg_arch = dpkg_arch_get(arch_native);

	return (dep_arch == pkg_arch);
}
