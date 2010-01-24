/*
 * libdpkg - Debian packaging suite library routines
 * ar.c - primitives for ar handling
 *
 * Copyright © 2010 Guillem Jover <guillem@debian.org>
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

#include <dpkg/ar.h>

void
dpkg_ar_normalize_name(struct ar_hdr *arh)
{
	char *name = arh->ar_name;
	int i;

	/* Remove trailing spaces from the member name. */
	for (i = sizeof(arh->ar_name) - 1; i >= 0 && name[i] == ' '; i--)
		name[i] = '\0';

	/* Remove optional slash terminator (on GNU-style archives). */
	if (name[i] == '/')
		name[i] = '\0';
}
