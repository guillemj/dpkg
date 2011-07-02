/*
 * libdpkg - Debian packaging suite library routines
 * pkg-show.c - primitives for pkg information display
 *
 * Copyright © 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008-2010 Guillem Jover <guillem@debian.org>
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

const char *
pkg_summary(const struct pkginfo *pkg, int *len_ret)
{
	const char *pdesc;
	size_t len;

	pdesc = pkg->installed.description;
	if (!pdesc)
		pdesc = _("(no description available)");

	len = strcspn(pdesc, "\n");
	if (len == 0)
		len = strlen(pdesc);

	*len_ret = len;

	return pdesc;
}
