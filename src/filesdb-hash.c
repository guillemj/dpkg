/*
 * dpkg - main program for package management
 * filesdb-hash.c - management of database of files installed on system
 *
 * Copyright © 2012-2014 Guillem Jover <guillem@debian.org>
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

#include <sys/stat.h>

#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/debug.h>
#include <dpkg/fdio.h>
#include <dpkg/dir.h>

#include "filesdb.h"
#include "infodb.h"

/*
 * If mask is nonzero, will not write any file whose filenamenode
 * has any flag bits set in mask.
 */
void
write_filehash_except(struct pkginfo *pkg, struct pkgbin *pkgbin,
                      struct fileinlist *list, enum filenamenode_flags mask)
{
	struct atomic_file *file;
	const char *hashfile;

	debug(dbg_general, "generating infodb hashfile");

	if (pkg_infodb_has_file(pkg, &pkg->available, HASHFILE))
		return;

	hashfile = pkg_infodb_get_file(pkg, pkgbin, HASHFILE);

	file = atomic_file_new(hashfile, 0);
	atomic_file_open(file);

	for (; list; list = list->next) {
		 struct filenamenode *namenode = list->namenode;

		if (mask && (namenode->flags & mask))
			continue;
		if (strcmp(namenode->newhash, EMPTYHASHFLAG) == 0)
			continue;

		fprintf(file->fp, "%s  %s\n",
		        namenode->newhash, namenode->name + 1);
	}

	atomic_file_sync(file);
	atomic_file_close(file);
	atomic_file_commit(file);
	atomic_file_free(file);

	dir_sync_path(pkg_infodb_get_dir());
}

static void
parse_filehash_buffer(char *buf, char *buf_end,
                      struct pkginfo *pkg, struct pkgbin *pkgbin)
{
	char *thisline, *nextline;
	const char *pkgname = pkg_name(pkg, pnaw_nonambig);

	for (thisline = buf; thisline < buf_end; thisline = nextline) {
		struct filenamenode *namenode;
		char *endline, *hash_end, *filename;

		endline = memchr(thisline, '\n', buf_end - thisline);
		if (endline == NULL)
			ohshit(_("control file '%s' for package '%s' is "
			         "missing final newline"), HASHFILE, pkgname);

		/* The md5sum hash has a constant length. */
		hash_end = thisline + MD5HASHLEN;

		filename = hash_end + 2;
		if (filename + 1 > endline)
			ohshit(_("control file '%s' for package '%s' is "
			         "missing value"), HASHFILE, pkgname);

		if (hash_end[0] != ' ' || hash_end[1] != ' ')
			ohshit(_("control file '%s' for package '%s' is "
			         "missing value separator"), HASHFILE, pkgname);
		hash_end[0] = '\0';

		/* Where to start next time around. */
		nextline = endline + 1;

		/* Strip trailing ‘/’. */
		if (endline > thisline && endline[-1] == '/')
			endline--;
		*endline = '\0';

		if (endline == thisline)
			ohshit(_("control file '%s' for package '%s' "
			         "contains empty filename"), HASHFILE, pkgname);

		debug(dbg_eachfiledetail, "load hash '%s' for filename '%s'",
		      thisline, filename);

		/* Add the file to the list. */
		namenode = findnamenode(filename, fnn_nocopy);
		namenode->newhash = thisline;
	}
}

void
parse_filehash(struct pkginfo *pkg, struct pkgbin *pkgbin)
{
	static int fd;
	const char *hashfile;
	struct stat st;

	hashfile = pkg_infodb_get_file(pkg, pkgbin, HASHFILE);

	fd = open(hashfile, O_RDONLY);
	if (fd < 0) {
		if (errno == ENOENT)
			return;

		ohshite(_("cannot open control file '%s' for package '%s'"),
		        HASHFILE, pkg_name(pkg, pnaw_nonambig));
	}

	if (fstat(fd, &st) < 0)
		ohshite(_("cannot stat control file '%s' for package '%s'"),
		        HASHFILE, pkg_name(pkg, pnaw_nonambig));

	if (!S_ISREG(st.st_mode))
		ohshit(_("control file '%s' for package '%s' is not a regular file"),
		       HASHFILE, pkg_name(pkg, pnaw_nonambig));

	if (st.st_size > 0) {
		char *buf, *buf_end;

		buf = nfmalloc(st.st_size);
		buf_end = buf + st.st_size;

		if (fd_read(fd, buf, st.st_size) < 0)
			ohshite(_("cannot read control file '%s' for package '%s'"),
			        HASHFILE, pkg_name(pkg, pnaw_nonambig));

		parse_filehash_buffer(buf, buf_end, pkg, pkgbin);
	}

	if (close(fd))
		ohshite(_("cannot close control file '%s' for package '%s'"),
		        HASHFILE, pkg_name(pkg, pnaw_nonambig));
}
