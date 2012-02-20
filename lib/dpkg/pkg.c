/*
 * libdpkg - Debian packaging suite library routines
 * pkg.c - primitives for pkg handling
 *
 * Copyright © 1995, 1996 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <config.h>
#include <compat.h>

#include <assert.h>
#include <string.h>

#include <dpkg/dpkg-db.h>
#include <dpkg/pkg.h>

/**
 * Set the package installation status.
 */
void
pkg_set_status(struct pkginfo *pkg, enum pkgstatus status)
{
	if (pkg->status == status)
		return;
	else if (pkg->status == stat_notinstalled)
		pkg->set->installed_instances++;
	else if (status == stat_notinstalled)
		pkg->set->installed_instances--;

	assert(pkg->set->installed_instances >= 0);

	pkg->status = status;
}

/**
 * Set the specified flags to 1 in the package error flags.
 */
void
pkg_set_eflags(struct pkginfo *pkg, enum pkgeflag eflag)
{
	pkg->eflag |= eflag;
}

/**
 * Clear the specified flags to 0 in the package error flags.
 */
void
pkg_clear_eflags(struct pkginfo *pkg, enum pkgeflag eflag)
{
	pkg->eflag &= ~eflag;
}

/**
 * Reset the package error flags to 0.
 */
void
pkg_reset_eflags(struct pkginfo *pkg)
{
	pkg->eflag = eflag_ok;
}

/**
 * Copy the package error flags to another package.
 */
void
pkg_copy_eflags(struct pkginfo *pkg_dst, struct pkginfo *pkg_src)
{
	pkg_dst->eflag = pkg_src->eflag;
}

/**
 * Set the package selection status.
 */
void
pkg_set_want(struct pkginfo *pkg, enum pkgwant want)
{
	pkg->want = want;
}

void
pkgbin_blank(struct pkgbin *pkgbin)
{
	pkgbin->essential = false;
	pkgbin->multiarch = multiarch_no;
	pkgbin->depends = NULL;
	pkgbin->pkgname_archqual = NULL;
	pkgbin->description = NULL;
	pkgbin->maintainer = NULL;
	pkgbin->source = NULL;
	pkgbin->installedsize = NULL;
	pkgbin->bugs = NULL;
	pkgbin->origin = NULL;
	blankversion(&pkgbin->version);
	pkgbin->conffiles = NULL;
	pkgbin->arbs = NULL;
}

void
pkg_blank(struct pkginfo *pkg)
{
	pkg->status = stat_notinstalled;
	pkg->eflag = eflag_ok;
	pkg->want = want_unknown;
	pkg->priority = pri_unknown;
	pkg->otherpriority = NULL;
	pkg->section = NULL;
	blankversion(&pkg->configversion);
	pkg->files = NULL;
	pkg->clientdata = NULL;
	pkg->trigaw.head = NULL;
	pkg->trigaw.tail = NULL;
	pkg->othertrigaw_head = NULL;
	pkg->trigpend_head = NULL;
	pkgbin_blank(&pkg->installed);
	pkgbin_blank(&pkg->available);

	/* The architectures are reset here (instead of in pkgbin_blank),
	 * because they are part of the package specification, and needed
	 * for selections. */
	pkg->installed.arch = dpkg_arch_get(arch_none);
	pkg->available.arch = dpkg_arch_get(arch_none);
}

void
pkgset_blank(struct pkgset *set)
{
	set->name = NULL;
	set->depended.available = NULL;
	set->depended.installed = NULL;
	pkg_blank(&set->pkg);
	set->installed_instances = 0;
	set->pkg.set = set;
	set->pkg.arch_next = NULL;
}

/**
 * Link a pkginfo instance into a package set.
 *
 * @param set The package set to use.
 * @param pkg The package to link into the set.
 */
void
pkgset_link_pkg(struct pkgset *set, struct pkginfo *pkg)
{
	pkg->set = set;
	pkg->arch_next = set->pkg.arch_next;
	set->pkg.arch_next = pkg;
}

/**
 * Get the number of installed package instances in a package set.
 *
 * @param set The package set to use.
 *
 * @return The count of installed packages.
 */
int
pkgset_installed_instances(struct pkgset *set)
{
	return set->installed_instances;
}

/**
 * Get the singleton package instance of a package set.
 *
 * This means, either the first instance if none are installed, the single
 * installed instance, or NULL if more than one instance is installed.
 *
 * @param set The package set to use.
 *
 * @return The singleton package instance.
 */
struct pkginfo *
pkgset_get_singleton(struct pkgset *set)
{
	struct pkginfo *pkg;

	if (pkgset_installed_instances(set) > 1)
		return NULL;

	for (pkg = &set->pkg; pkg; pkg = pkg->arch_next) {
		if (pkg->status > stat_notinstalled)
			return pkg;
	}

	return &set->pkg;
}

static int
nes(const char *s)
{
	return s && *s;
}

/**
 * Check if a pkg is informative.
 *
 * Used by dselect and dpkg query options as an aid to decide whether to
 * display things, and by dump to decide whether to write them out.
 */
bool
pkg_is_informative(struct pkginfo *pkg, struct pkgbin *pkgbin)
{
	/* We ignore Section and Priority, as these tend to hang around. */
	if (pkgbin == &pkg->installed &&
	    (pkg->want != want_unknown ||
	     pkg->eflag != eflag_ok ||
	     pkg->status != stat_notinstalled ||
	     informativeversion(&pkg->configversion)))
		return true;

	if (pkgbin->depends ||
	    nes(pkgbin->description) ||
	    nes(pkgbin->maintainer) ||
	    nes(pkgbin->origin) ||
	    nes(pkgbin->bugs) ||
	    nes(pkgbin->installedsize) ||
	    nes(pkgbin->source) ||
	    informativeversion(&pkgbin->version) ||
	    pkgbin->conffiles ||
	    pkgbin->arbs)
		return true;

	return false;
}

/**
 * Compare a package to be sorted by name.
 *
 * @param a A pointer of a pointer to a struct pkginfo.
 * @param b A pointer of a pointer to a struct pkginfo.
 *
 * @return An integer with the result of the comparison.
 * @retval -1 a is earlier than b.
 * @retval 0 a is equal to b.
 * @retval 1 a is later than b.
 */
int
pkg_sorter_by_name(const void *a, const void *b)
{
	const struct pkginfo *pa = *(const struct pkginfo **)a;
	const struct pkginfo *pb = *(const struct pkginfo **)b;

	return strcmp(pa->set->name, pb->set->name);
}
