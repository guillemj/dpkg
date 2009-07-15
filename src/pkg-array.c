/*
 * dpkg - main program for package management
 * pkg-array.c - primitives for pkg array handling
 *
 * Copyright © 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2009 Guillem Jover <guillem@debian.org>
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
 * You should have received a copy of the GNU General Public
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>
#include <compat.h>

#include <assert.h>
#include <string.h>
#include <stdlib.h>

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

#include "pkg-array.h"

int
pkglistqsortcmp(const void *a, const void *b)
{
	const struct pkginfo *pa = *(const struct pkginfo **)a;
	const struct pkginfo *pb = *(const struct pkginfo **)b;

	return strcmp(pa->name, pb->name);
}

void
pkg_array_init_from_db(struct pkg_array *a)
{
	struct pkgiterator *it;
	struct pkginfo *pkg;
	int i;

	a->n_pkgs = countpackages();
	a->pkgs = m_malloc(sizeof(a->pkgs[0]) * a->n_pkgs);

	it = iterpkgstart();
	for (i = 0; (pkg = iterpkgnext(it)); i++)
		a->pkgs[i] = pkg;
	iterpkgend(it);

	assert(i == a->n_pkgs);
}

void
pkg_array_sort(struct pkg_array *a, pkg_sorter_func *pkg_sort)
{
	qsort(a->pkgs, a->n_pkgs, sizeof(a->pkgs[0]), pkg_sort);
}

void
pkg_array_free(struct pkg_array *a)
{
	a->n_pkgs = 0;
	free(a->pkgs);
	a->pkgs = NULL;
}

