/*
 * dpkg - main program for package management
 * pkg-show.c - primitives for pkg information display
 *
 * Copyright © 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2,
 * or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>
#include <compat.h>

#include <string.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

void
limiteddescription(struct pkginfo *pkg,
                   int maxl, const char **pdesc_r, int *l_r)
{
	const char *pdesc, *p;

	pdesc = pkg->installed.valid ? pkg->installed.description : NULL;
	if (!pdesc)
		pdesc = _("(no description available)");
	p = strchr(pdesc, '\n');
	if (!p)
		p = pdesc + strlen(pdesc);

	*l_r = min(p - pdesc, maxl);
	*pdesc_r = pdesc;
}

