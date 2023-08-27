/*
 * libdpkg - Debian packaging suite library routines
 * sysuser.c - system user and group handling
 *
 * Copyright © 2023 Guillem Jover <guillem@debian.org>
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

#include <dpkg/sysuser.h>

struct passwd *
dpkg_sysuser_from_name(const char *uname)
{
	struct passwd *pw;

	pw = getpwnam(uname);

	return pw;
}

struct passwd *
dpkg_sysuser_from_uid(uid_t uid)
{
	return getpwuid(uid);
}

struct group *
dpkg_sysgroup_from_name(const char *gname)
{
	struct group *gr;

	gr = getgrnam(gname);

	return gr;
}

struct group *
dpkg_sysgroup_from_gid(gid_t gid)
{
	return getgrgid(gid);
}
