/*
 * libdpkg - Debian packaging suite library routines
 * fsys-iter.c - filesystem nodes iterators
 *
 * Copyright © 1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2000, 2001 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2008-2014 Guillem Jover <guillem@debian.org>
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

#include <stdlib.h>

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-list.h>

#include "fsys.h"

/*
 * Reverse fileinlist iterator.
 */

/*
 * Initializes an iterator that appears to go through the file list ‘files’
 * in reverse order, returning the namenode from each. What actually happens
 * is that we walk the list here, building up a reverse list, and then peel
 * it apart one entry at a time.
 */
void
reversefilelist_init(struct reversefilelistiter *iter,
                     struct fileinlist *files)
{
	struct fileinlist *newent;

	iter->todo = NULL;
	while (files) {
		newent = m_malloc(sizeof(struct fileinlist));
		newent->namenode = files->namenode;
		newent->next = iter->todo;
		iter->todo = newent;
		files = files->next;
	}
}

struct filenamenode *
reversefilelist_next(struct reversefilelistiter *iter)
{
	struct filenamenode *ret;
	struct fileinlist *todo;

	todo = iter->todo;
	if (!todo)
		return NULL;
	ret = todo->namenode;
	iter->todo = todo->next;
	free(todo);

	return ret;
}

/*
 * Clients must call this function to clean up the reversefilelistiter
 * if they wish to break out of the iteration before it is all done.
 * Calling this function is not necessary if reversefilelist_next() has
 * been called until it returned 0.
 */
void
reversefilelist_abort(struct reversefilelistiter *iter)
{
	while (reversefilelist_next(iter))
		;
}

/*
 * Iterator for packages owning a file.
 */

struct filepackages_iterator {
	struct pkg_list *pkg_node;
};

struct filepackages_iterator *
filepackages_iter_new(struct filenamenode *fnn)
{
	struct filepackages_iterator *iter;

	iter = m_malloc(sizeof(*iter));
	iter->pkg_node = fnn->packages;

	return iter;
}

struct pkginfo *
filepackages_iter_next(struct filepackages_iterator *iter)
{
	struct pkg_list *pkg_node;

	if (iter->pkg_node == NULL)
		return NULL;

	pkg_node = iter->pkg_node;
	iter->pkg_node = pkg_node->next;

	return pkg_node->pkg;
}

void
filepackages_iter_free(struct filepackages_iterator *iter)
{
	free(iter);
}
