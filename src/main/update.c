/*
 * dpkg - main program for package management
 * update.c - options which update the ‘available’ database
 *
 * Copyright © 1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
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

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/options.h>

#include "main.h"

static void
db_available_check_access(void)
{
	const char *dbdir = dpkg_db_get_dir();

	if (access(dbdir, W_OK) == 0)
		return;

	if (errno != EACCES)
		ohshite(_("cannot access dpkg database directory '%s' "
		          "for bulk available update"),
		        dbdir);
	else
		ohshit(_("required write access to dpkg database directory '%s' "
		         "for bulk available update"),
		       dbdir);
}

int
available_update(const char *const *argv)
{
	const char *sourcefile = argv[0];
	const char *sourcename = sourcefile;
	char *availfile;
	int count = 0;

	if (sourcefile == NULL)
		sourcefile = "-";
	else if (argv[1])
		badusage(_("--%s takes at most one Packages-file argument"),
		         cipaction->olong);
	if (strcmp(sourcefile, "-") == 0)
		sourcename = _("<standard input>");

	modstatdb_init();

	if (f_act) {
		db_available_check_access();
		modstatdb_lock();
	}

	switch (cipaction->arg_int) {
	case act_avreplace:
		printf(_("Replacing available packages information from %s.\n"),
		       sourcename);
		break;
	case act_avmerge:
		printf(_("Updating available packages information from %s.\n"),
		       sourcename);
		break;
	default:
		internerr("unknown action '%d'", cipaction->arg_int);
	}

	availfile = dpkg_db_get_path(DPKG_DB_AVAIL_FILE);

	if (cipaction->arg_int == act_avmerge)
		parsedb(availfile, pdb_parse_available, NULL);

	count += parsedb(sourcefile,
	                 pdb_parse_available | pdb_ignoreolder | pdb_dash_is_stdin,
	                 NULL);

	if (f_act) {
		writedb(availfile, wdb_dump_available);
		modstatdb_unlock();
	}

	free(availfile);

	printf(P_("Information about %d package was updated.\n",
	          "Information about %d packages was updated.\n",
	          count),
	       count);

	modstatdb_done();

	return 0;
}

int
available_clear(const char *const *argv)
{
	const char *sourcefile = argv[0];

	if (sourcefile)
		badusage(_("--%s takes no arguments"), cipaction->olong);

	modstatdb_init();

	if (f_act) {
		char *availfile;

		db_available_check_access();
		modstatdb_lock();

		availfile = dpkg_db_get_path(DPKG_DB_AVAIL_FILE);

		writedb(availfile, wdb_dump_available);
		modstatdb_unlock();

		free(availfile);
	}

	modstatdb_done();

	return 0;
}

int
forgetold(const char *const *argv)
{
	if (*argv)
		badusage(_("--%s takes no arguments"), cipaction->olong);

	warning(_("obsolete '--%s' option; unavailable packages are automatically cleaned up"),
	        cipaction->olong);

	return 0;
}
