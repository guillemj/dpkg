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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
static FILE *diversionsfile = NULL;

void
ensure_diversions(void)
{
	static struct varbuf vb;

	struct stat stab1, stab2;
	char linebuf[MAXDIVERTFILENAME];
	FILE *file;
	struct diversion *ov, *oicontest, *oialtname;

	varbufreset(&vb);
	varbufaddstr(&vb, admindir);
	varbufaddstr(&vb, "/" DIVERSIONSFILE);
	varbufaddc(&vb, 0);

	onerr_abort++;

	file = fopen(vb.buf,"r");
	if (!file) {
		if (errno != ENOENT)
			ohshite(_("failed to open diversions file"));
		if (!diversionsfile) {
			onerr_abort--;
			return;
		}
	} else if (diversionsfile) {
		if (fstat(fileno(diversionsfile), &stab1))
			ohshite(_("failed to fstat previous diversions file"));
		if (fstat(fileno(file), &stab2))
			ohshite(_("failed to fstat diversions file"));
		if (stab1.st_dev == stab2.st_dev &&
		    stab1.st_ino == stab2.st_ino) {
			fclose(file);
			onerr_abort--;
			return;
		}
	}
	if (diversionsfile)
		fclose(diversionsfile);
	diversionsfile = file;
	setcloexec(fileno(diversionsfile), vb.buf);

	for (ov = diversions; ov; ov = ov->next) {
		ov->useinstead->divert->camefrom->divert = NULL;
		ov->useinstead->divert = NULL;
	}
	diversions = NULL;
	if (!file) {
		onerr_abort--;
		return;
	}

	while (fgets_checked(linebuf, sizeof(linebuf), file, vb.buf) >= 0) {
		oicontest = nfmalloc(sizeof(struct diversion));
		oialtname = nfmalloc(sizeof(struct diversion));

		oialtname->camefrom = findnamenode(linebuf, 0);
		oialtname->useinstead = NULL;

		fgets_must(linebuf, sizeof(linebuf), file, vb.buf);
		oicontest->useinstead = findnamenode(linebuf, 0);
		oicontest->camefrom = NULL;

		fgets_must(linebuf, sizeof(linebuf), file, vb.buf);
		oicontest->pkg = oialtname->pkg = strcmp(linebuf, ":") ?
		                                  pkg_db_find(linebuf) : NULL;

		if (oialtname->camefrom->divert ||
		    oicontest->useinstead->divert)
			ohshit(_("conflicting diversions involving `%.250s' or `%.250s'"),
			       oialtname->camefrom->name, oicontest->useinstead->name);

		oialtname->camefrom->divert = oicontest;
		oicontest->useinstead->divert = oialtname;

		oicontest->next = diversions;
		diversions = oicontest;
	}

	onerr_abort--;
}

