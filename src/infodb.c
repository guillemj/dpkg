/*
 * dpkg - main program for package management
 * infodb.c - package control information database
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2011 Guillem Jover <guillem@debian.org>
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

#include <sys/types.h>
#include <sys/stat.h>

#include <errno.h>
#include <unistd.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

#include "infodb.h"

bool
pkg_infodb_has_file(struct pkginfo *pkg, const char *name)
{
	const char *filename;
	struct stat stab;

	filename = pkgadminfile(pkg, name);
	if (lstat(filename, &stab) == 0)
		return true;
	else if (errno == ENOENT)
		return false;
	else
		ohshite(_("unable to check existence of `%.250s'"), filename);
}
