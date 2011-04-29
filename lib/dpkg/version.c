/*
 * libdpkg - Debian packaging suite library routines
 * version.c - Version handling functions
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <dpkg/version.h>

void
blankversion(struct versionrevision *version)
{
	version->epoch = 0;
	version->version = NULL;
	version->revision = NULL;
}

bool
informativeversion(const struct versionrevision *version)
{
	return (version->epoch ||
	        (version->version && *version->version) ||
	        (version->revision && *version->revision));
}
