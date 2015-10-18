/*
 * libdpkg - Debian packaging suite library routines
 * dbdir.c - on-disk database directory functions
 *
 * Copyright © 2011 Guillem Jover <guillem@debian.org>
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

#include <stdlib.h>

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

static const char *db_dir = ADMINDIR;

/**
 * Set current on-disk database directory.
 *
 * The directory is initially set to ADMINDIR, this function can be used to
 * set the directory to a new value, or to set it to a default value if dir
 * is NULL. For the latter the order is, value from environment variable
 * DPKG_ADMINDIR, and then the built-in default ADMINDIR,
 *
 * @param dir The new databse directory, or NULL to set to default.
 *
 * @return The new database directory.
 */
const char *
dpkg_db_set_dir(const char *dir)
{
	if (dir == NULL) {
		const char *env;

		env = getenv("DPKG_ADMINDIR");
		if (env)
			db_dir = env;
		else
			db_dir = ADMINDIR;
	} else {
		db_dir = dir;
	}

	return db_dir;
}

/**
 * Get current on-disk database directory.
 *
 * @return The current database directory.
 */
const char *
dpkg_db_get_dir(void)
{
	return db_dir;
}

/**
 * Get a pathname to the current on-disk database directory.
 *
 * This function returns an allocated string, which should be freed with
 * free(2).
 *
 * @param pathpart The pathpart to append to the new pathnme.
 *
 * @return The newly allocated pathname.
 */
char *
dpkg_db_get_path(const char *pathpart)
{
	return str_fmt("%s/%s", db_dir, pathpart);
}
