/*
 * libdpkg - Debian packaging suite library routines
 * fsys-dir.c - filesystem root directory functions
 *
 * Copyright © 2011, 2018 Guillem Jover <guillem@debian.org>
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
#include <dpkg/string.h>
#include <dpkg/path.h>
#include <dpkg/fsys.h>

static const char *fsys_dir = "";
static char *fsys_dir_alloc;

/**
 * Set current on-disk filesystem root directory.
 *
 * The directory is initially set to "", this function can be used to
 * set the directory to a new value, or to set it to a default value if dir
 * is NULL. For the latter the order is, value from environment variable
 * DPKG_ROOT, and then the built-in default "",
 *
 * @param dir The new filesystem root directory, or NULL to set to default.
 *
 * @return The new filesystem root directory.
 */
const char *
dpkg_fsys_set_dir(const char *dir)
{
	char *fsys_dir_new;

	if (dir == NULL) {
		const char *env;

		env = getenv("DPKG_ROOT");
		if (env)
			dir = env;
	}

	if (dir == NULL) {
		fsys_dir = "";
		fsys_dir_new = NULL;
	} else {
		fsys_dir = fsys_dir_new = m_strdup(dir);
		path_trim_slash_slashdot(fsys_dir_new);
	}

	free(fsys_dir_alloc);
	fsys_dir_alloc = fsys_dir_new;

	return fsys_dir;
}

/**
 * Get current on-disk filesystem root directory.
 *
 * @return The current filesystem root directory.
 */
const char *
dpkg_fsys_get_dir(void)
{
	return fsys_dir;
}

/**
 * Get a pathname to the current on-disk filesystem root directory.
 *
 * This function returns an allocated string, which should be freed with
 * free(2).
 *
 * @param pathpart The pathpart to append to the new pathname.
 *
 * @return The newly allocated pathname.
 */
char *
dpkg_fsys_get_path(const char *pathpart)
{
	pathpart = path_skip_slash_dotslash(pathpart);

	return str_fmt("%s/%s", fsys_dir, pathpart);
}
