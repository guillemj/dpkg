/*
 * libcompat - system compatibility library
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <sys/types.h>

#include <string.h>
#include <dirent.h>
#include <stdlib.h>

#ifndef HAVE_SCANDIR
int
scandir(const char *dir, struct dirent ***namelist,
        int (*filter)(const struct dirent *),
        int (*cmp)(const void *, const void *))
{
	DIR *d;
	int used, avail;
	struct dirent *e, *m;

	d = opendir(dir);
	if (!d)
		return -1;

	used = 0;
	avail = 20;

	*namelist = malloc(avail * sizeof(struct dirent *));
	if (!*namelist)
		return -1;

	while ((e = readdir(d)) != NULL) {
		if (filter != NULL && !filter(e))
			continue;

		m = malloc(sizeof(struct dirent) + strlen(e->d_name));
		if (!m)
			return -1;
		*m = *e;
		strcpy(m->d_name, e->d_name);

		if (used >= avail - 1) {
			avail += avail;
			*namelist = realloc(*namelist, avail * sizeof(struct dirent *));
			if (!*namelist)
				return -1;
		}

		(*namelist)[used] = m;
		used++;
	}
	(*namelist)[used] = NULL;

	if (cmp != NULL)
		qsort(*namelist, used, sizeof(struct dirent *), cmp);

	return used;
}
#endif

