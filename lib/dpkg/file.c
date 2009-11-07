/*
 * libdpkg - Debian packaging suite library routines
 * file.c - file handling functions
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008 Guillem Jover <guillem@debian.org>
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
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <errno.h>
#include <unistd.h>

#include <dpkg/dpkg.h>
#include <dpkg/i18n.h>
#include <dpkg/file.h>

void
file_copy_perms(const char *src, const char *dst)
{
	struct stat stab;

	if (stat(src, &stab) == -1) {
		if (errno == ENOENT)
			return;
		ohshite(_("unable to stat source file '%.250s'"), src);
	}

	if (chown(dst, stab.st_uid, stab.st_gid) == -1)
		ohshite(_("unable to change ownership of target file '%.250s'"),
		        dst);

	if (chmod(dst, (stab.st_mode & 07777)) == -1)
		ohshite(_("unable to set mode of target file '%.250s'"), dst);
}

