/*
 * libdpkg - Debian packaging suite library routines
 * pkg-show.c - primitives for pkg information display
 *
 * Copyright © 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008-2012 Guillem Jover <guillem@debian.org>
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

#include <string.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-show.h>

static bool
pkgbin_name_needs_arch(const struct pkgbin *pkgbin,
                       enum pkg_name_arch_when pnaw)
{
	switch (pnaw) {
	case pnaw_never:
		break;
	case pnaw_foreign:
		if (pkgbin->arch->type == arch_native ||
		    pkgbin->arch->type == arch_all ||
		    pkgbin->arch->type == arch_none)
			break;
		return true;
	case pnaw_nonambig:
		if (pkgbin->multiarch != multiarch_same)
			break;
	/* Fall through. */
	case pnaw_always:
		return true;
	}

	return false;
}

/**
 * Add a string representation of the package name to a varbuf.
 *
 * Works exactly like pkgbin_name() but acts on the varbuf instead of
 * returning a string. It NUL terminates the varbuf.
 *
 * @param vb      The varbuf struct to modify.
 * @param pkg     The package to consider.
 * @param pkgbin  The binary package instance to consider.
 * @param pnaw    When to display the architecture qualifier.
 */
void
varbuf_add_pkgbin_name(struct varbuf *vb,
                       const struct pkginfo *pkg, const struct pkgbin *pkgbin,
                       enum pkg_name_arch_when pnaw)
{
	varbuf_add_str(vb, pkg->set->name);
	if (pkgbin_name_needs_arch(pkgbin, pnaw))
		varbuf_add_archqual(vb, pkgbin->arch);
	varbuf_end_str(vb);
}

/**
 * Return a string representation of the package name.
 *
 * The returned string must not be freed, and it's permanently allocated so
 * can be used as long as the non-freeing memory pool has not been freed.
 *
 * The pnaw parameter should be one of pnaw_never (never print arch),
 * pnaw_foreign (print arch for foreign packages only), pnaw_nonambig (print
 * arch for non ambiguous cases) or pnaw_always (always print arch),
 *
 * @param pkg     The package to consider.
 * @param pkgbin  The binary package instance to consider.
 * @param pnaw    When to display the architecture qualifier.
 *
 * @return The string representation.
 */
const char *
pkgbin_name(struct pkginfo *pkg, struct pkgbin *pkgbin,
            enum pkg_name_arch_when pnaw)
{
	if (!pkgbin_name_needs_arch(pkgbin, pnaw))
		return pkg->set->name;

	/* Cache the package name representation, for later reuse. */
	if (pkgbin->pkgname_archqual == NULL) {
		struct varbuf vb = VARBUF_INIT;

		varbuf_add_str(&vb, pkg->set->name);
		varbuf_add_archqual(&vb, pkgbin->arch);
		varbuf_end_str(&vb);

		pkgbin->pkgname_archqual = nfstrsave(vb.buf);

		varbuf_destroy(&vb);
	}

	return pkgbin->pkgname_archqual;
}

/**
 * Return a string representation of the package name.
 *
 * This is equivalent to pkgbin_name() but just for its installed pkgbin.
 *
 * @param pkg   The package to consider.
 * @param pnaw  When to display the architecture qualifier.
 *
 * @return The string representation.
 */
const char *
pkg_name(struct pkginfo *pkg, enum pkg_name_arch_when pnaw)
{
	return pkgbin_name(pkg, &pkg->installed, pnaw);
}

const char *
pkg_summary(const struct pkginfo *pkg, const struct pkgbin *pkgbin, int *len_ret)
{
	const char *pdesc;
	size_t len;

	pdesc = pkgbin->description;
	if (!pdesc)
		pdesc = _("(no description available)");

	len = strcspn(pdesc, "\n");
	if (len == 0)
		len = strlen(pdesc);

	*len_ret = len;

	return pdesc;
}

int
pkg_abbrev_want(const struct pkginfo *pkg)
{
	return "uihrp"[pkg->want];
}

int
pkg_abbrev_status(const struct pkginfo *pkg)
{
	return "ncHUFWti"[pkg->status];
}

int
pkg_abbrev_eflag(const struct pkginfo *pkg)
{
	return " R"[pkg->eflag];
}

/**
 * Compare a package to be sorted by non-ambiguous name and architecture.
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
pkg_sorter_by_nonambig_name_arch(const void *a, const void *b)
{
	const struct pkginfo *pa = *(const struct pkginfo **)a;
	const struct pkginfo *pb = *(const struct pkginfo **)b;
	const struct pkgbin *pbina = &pa->installed;
	const struct pkgbin *pbinb = &pb->installed;
	int res;

	res = strcmp(pa->set->name, pb->set->name);
	if (res)
		return res;

	if (pbina->arch == pbinb->arch)
		return 0;

	if (pkgbin_name_needs_arch(pbina, pnaw_nonambig)) {
		if (pkgbin_name_needs_arch(pbinb, pnaw_nonambig))
			return strcmp(pbina->arch->name, pbinb->arch->name);
		else
			return 1;
	} else {
		return -1;
	}
}
