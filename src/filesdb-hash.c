/*
 * dpkg - main program for package management
 * filesdb-hash.c - management of database of files installed on system
 *
 * Copyright © 2012 Guillem Jover <guillem@debian.org>
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

#include <string.h>
#include <stdio.h>

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/debug.h>
#include <dpkg/dir.h>

#include "filesdb.h"
#include "infodb.h"

/*
 * If mask is nonzero, will not write any file whose filenamenode
 * has any flag bits set in mask.
 */
void
write_filehash_except(struct pkginfo *pkg, struct pkgbin *pkgbin,
                      struct fileinlist *list, enum fnnflags mask)
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
