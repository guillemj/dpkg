/*
 * dpkg - main program for package management
 * statdb.c - management of database of ownership and mode of files
 *
 * Copyright © 1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2000, 2001 Wichert Akkerman <wakkerma@debian.org>
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
#include <dpkg/fdio.h>

#include "filesdb.h"
#include "main.h"

static char *statoverridename;

uid_t
statdb_parse_uid(const char *str)
{
	char *endptr;
	uid_t uid;

	if (str[0] == '#') {
		long int value;

		errno = 0;
		value = strtol(str + 1, &endptr, 10);
		if (str + 1 == endptr || *endptr || value < 0 || errno != 0)
			ohshit(_("invalid statoverride uid %s"), str);
		uid = (uid_t)value;
	} else {
		struct passwd *pw = getpwnam(str);

		if (pw == NULL)
			uid = (uid_t)-1;
		else
			uid = pw->pw_uid;
	}

	return uid;
}

gid_t
statdb_parse_gid(const char *str)
{
	char *endptr;
	gid_t gid;

	if (str[0] == '#') {
		long int value;

		errno = 0;
		value = strtol(str + 1, &endptr, 10);
		if (str + 1 == endptr || *endptr || value < 0 || errno != 0)
			ohshit(_("invalid statoverride gid %s"), str);
		gid = (gid_t)value;
	} else {
		struct group *gr = getgrnam(str);

		if (gr == NULL)
			gid = (gid_t)-1;
		else
			gid = gr->gr_gid;
	}

	return gid;
}

mode_t
statdb_parse_mode(const char *str)
{
	char *endptr;
	long int mode;

	mode = strtol(str, &endptr, 8);
	if (str == endptr || *endptr || mode < 0 || mode > 07777)
		ohshit(_("invalid statoverride mode %s"), str);

	return (mode_t)mode;
}

void
ensure_statoverrides(enum statdb_parse_flags flags)
{
	static struct stat sb_prev;
	struct stat sb_next;
	static FILE *file_prev;
	FILE *file;
	char *loaded_list, *loaded_list_end, *thisline, *nextline, *ptr;
	struct file_stat *fso;
	struct filenamenode *fnn;
	struct fileiterator *iter;

	if (statoverridename == NULL)
		statoverridename = dpkg_db_get_path(STATOVERRIDEFILE);

	onerr_abort++;

	file = fopen(statoverridename, "r");
	if (!file) {
		if (errno != ENOENT)
			ohshite(_("failed to open statoverride file"));
	} else {
		setcloexec(fileno(file), statoverridename);

		if (fstat(fileno(file), &sb_next))
			ohshite(_("failed to fstat statoverride file"));

		/*
		 * We need to keep the database file open so that the
		 * filesystem cannot reuse the inode number (f.ex. during
		 * multiple dpkg-statoverride invocations in a maintainer
		 * script), otherwise the following check might turn true,
		 * and we would skip reloading a modified database.
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

	/* Reset statoverride information. */
	iter = files_db_iter_new();
	while ((fnn = files_db_iter_next(iter)))
		fnn->statoverride = NULL;
	files_db_iter_free(iter);

	if (!file) {
		onerr_abort--;
		debug(dbg_general, "%s: none, resetting", __func__);
		return;
	}
	debug(dbg_general, "%s: new, (re)loading", __func__);

	/* If the statoverride list is empty we don't need to bother
	 * reading it. */
	if (!sb_next.st_size) {
		onerr_abort--;
		return;
	}

	loaded_list = nfmalloc(sb_next.st_size);
	loaded_list_end = loaded_list + sb_next.st_size;

	if (fd_read(fileno(file), loaded_list, sb_next.st_size) < 0)
		ohshite(_("reading statoverride file '%.250s'"), statoverridename);

	thisline = loaded_list;
	while (thisline < loaded_list_end) {
		fso = nfmalloc(sizeof(struct file_stat));

		ptr = memchr(thisline, '\n', loaded_list_end - thisline);
		if (ptr == NULL)
			ohshit(_("statoverride file is missing final newline"));
		/* Where to start next time around. */
		nextline = ptr + 1;
		if (ptr == thisline)
			ohshit(_("statoverride file contains empty line"));
		*ptr = '\0';

		/* Extract the uid. */
		ptr = memchr(thisline, ' ', nextline - thisline);
		if (ptr == NULL)
			ohshit(_("syntax error in statoverride file"));
		*ptr = '\0';

		fso->uid = statdb_parse_uid(thisline);
		if (fso->uid == (uid_t)-1)
			fso->uname = nfstrsave(thisline);
		else
			fso->uname = NULL;

		if (fso->uid == (uid_t)-1 && !(flags & STATDB_PARSE_LAX))
			ohshit(_("unknown user '%s' in statoverride file"),
			       thisline);

		/* Move to the next bit */
		thisline = ptr + 1;
		if (thisline >= loaded_list_end)
			ohshit(_("unexpected end of line in statoverride file"));

		/* Extract the gid */
		ptr = memchr(thisline, ' ', nextline - thisline);
		if (ptr == NULL)
			ohshit(_("syntax error in statoverride file"));
		*ptr = '\0';

		fso->gid = statdb_parse_gid(thisline);
		if (fso->gid == (gid_t)-1)
			fso->gname = nfstrsave(thisline);
		else
			fso->gname = NULL;

		if (fso->gid == (gid_t)-1 && !(flags & STATDB_PARSE_LAX))
			ohshit(_("unknown group '%s' in statoverride file"),
			       thisline);

		/* Move to the next bit */
		thisline = ptr + 1;
		if (thisline >= loaded_list_end)
			ohshit(_("unexpected end of line in statoverride file"));

		/* Extract the mode */
		ptr = memchr(thisline, ' ', nextline - thisline);
		if (ptr == NULL)
			ohshit(_("syntax error in statoverride file"));
		*ptr = '\0';

		fso->mode = statdb_parse_mode(thisline);

		/* Move to the next bit */
		thisline = ptr + 1;
		if (thisline >= loaded_list_end)
			ohshit(_("unexpected end of line in statoverride file"));

		fnn = findnamenode(thisline, 0);
		if (fnn->statoverride)
			ohshit(_("multiple statoverrides present for file '%.250s'"),
			       thisline);
		fnn->statoverride = fso;

		/* Moving on... */
		thisline = nextline;
	}

	onerr_abort--;
}
