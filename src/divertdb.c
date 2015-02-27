/*
 * dpkg - main program for package management
 * divertdb.c - management of database of diverted files
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000, 2001 Wichert Akkerman <wakkerma@debian.org>
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

#include <sys/types.h>
#include <sys/stat.h>

#include <errno.h>
#include <string.h>
#include <pwd.h>
#include <grp.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

#include "filesdb.h"
#include "main.h"

static struct diversion *diversions = NULL;
static char *diversionsname;

void
ensure_diversions(void)
{
	static struct stat sb_prev;
	struct stat sb_next;
	char linebuf[MAXDIVERTFILENAME];
	static FILE *file_prev;
	FILE *file;
	struct diversion *ov, *oicontest, *oialtname;

	if (diversionsname == NULL)
		diversionsname = dpkg_db_get_path(DIVERSIONSFILE);

	onerr_abort++;

	file = fopen(diversionsname, "r");
	if (!file) {
		if (errno != ENOENT)
			ohshite(_("failed to open diversions file"));
	} else {
		setcloexec(fileno(file), diversionsname);

		if (fstat(fileno(file), &sb_next))
			ohshite(_("failed to fstat diversions file"));

		/*
		 * We need to keep the database file open so that the
		 * filesystem cannot reuse the inode number (f.ex. during
		 * multiple dpkg-divert invocations in a maintainer script),
		 * otherwise the following check might turn true, and we
		 * would skip reloading a modified database.
		 */
		if (file_prev &&
		    sb_prev.st_dev == sb_next.st_dev &&
		    sb_prev.st_ino == sb_next.st_ino) {
			fclose(file);
			onerr_abort--;
			debug(dbg_general, "%s: same, skipping", __func__);
			return;
		}
		sb_prev = sb_next;
	}
	if (file_prev)
		fclose(file_prev);
	file_prev = file;

	for (ov = diversions; ov; ov = ov->next) {
		ov->useinstead->divert->camefrom->divert = NULL;
		ov->useinstead->divert = NULL;
	}
	diversions = NULL;
	if (!file) {
		onerr_abort--;
		debug(dbg_general, "%s: none, reseting", __func__);
		return;
	}
	debug(dbg_general, "%s: new, (re)loading", __func__);

	while (fgets_checked(linebuf, sizeof(linebuf), file, diversionsname) >= 0) {
		oicontest = nfmalloc(sizeof(struct diversion));
		oialtname = nfmalloc(sizeof(struct diversion));

		oialtname->camefrom = findnamenode(linebuf, 0);
		oialtname->useinstead = NULL;

		fgets_must(linebuf, sizeof(linebuf), file, diversionsname);
		oicontest->useinstead = findnamenode(linebuf, 0);
		oicontest->camefrom = NULL;

		fgets_must(linebuf, sizeof(linebuf), file, diversionsname);
		oicontest->pkgset = strcmp(linebuf, ":") ?
		                    pkg_db_find_set(linebuf) : NULL;
		oialtname->pkgset = oicontest->pkgset;

		if (oialtname->camefrom->divert ||
		    oicontest->useinstead->divert)
			ohshit(_("conflicting diversions involving '%.250s' or '%.250s'"),
			       oialtname->camefrom->name, oicontest->useinstead->name);

		oialtname->camefrom->divert = oicontest;
		oicontest->useinstead->divert = oialtname;

		oicontest->next = diversions;
		diversions = oicontest;
	}

	onerr_abort--;
}
