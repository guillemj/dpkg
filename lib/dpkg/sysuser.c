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

#include <string.h>

#include <dpkg/sysuser.h>

/* Cache UID 0 called "root" in most systems.
 * Cache GID 0 called "root" in most systems,
 *   or "wheel" on macOS,
 *   or "system" on AIX,
 *   although we do not cache the non-"root" ones.
 */

static struct passwd *root_pw;
static struct group *root_gr;

/*
 * Copy a sysuser struct.
 *
 * Note: We only copy the portable subset that we care about, the rest will
 * be zeroed out.
 */
static struct passwd *
dpkg_sysuser_copy(struct passwd *pw_old)
{
	struct passwd *pw_new;

	pw_new = m_calloc(1, sizeof(*pw_new));
	pw_new->pw_name = m_strdup(pw_old->pw_name);
	pw_new->pw_uid = pw_old->pw_uid;
	pw_new->pw_gid = pw_old->pw_gid;
	pw_new->pw_gecos = m_strdup(pw_old->pw_gecos);
	pw_new->pw_dir = m_strdup(pw_old->pw_dir);
	pw_new->pw_shell = m_strdup(pw_old->pw_shell);

	return pw_new;
}

struct passwd *
dpkg_sysuser_from_name(const char *uname)
{
	struct passwd *pw;
	bool is_root = strcmp(uname, "root") == 0;

	if (is_root && root_pw != NULL)
		return root_pw;

	pw = getpwnam(uname);

	if (is_root)
		root_pw = dpkg_sysuser_copy(pw);

	return pw;
}

struct passwd *
dpkg_sysuser_from_uid(uid_t uid)
{
	return getpwuid(uid);
}

/*
 * Copy a sysgroup struct.
 *
 * Note: We only copy the portable subset that we care about, the rest will
 * be zeroed out.
 */
static struct group *
dpkg_sysgroup_copy(struct group *gr_old)
{
	struct group *gr_new;
	size_t n;

	gr_new = m_calloc(1, sizeof(*gr_new));
	gr_new->gr_name = m_strdup(gr_old->gr_name);
	gr_new->gr_gid = gr_old->gr_gid;

	for (n = 0; gr_old->gr_mem[n]; n++)
		;

	gr_new->gr_mem = m_calloc(n + 1, sizeof(char *));
	for (n = 0; gr_old->gr_mem[n]; n++)
		gr_new->gr_mem[n] = m_strdup(gr_old->gr_mem[n]);

	return gr_new;
}

struct group *
dpkg_sysgroup_from_name(const char *gname)
{
	struct group *gr;
	bool is_root = strcmp(gname, "root") == 0;

	if (is_root && root_gr != NULL)
		return root_gr;

	gr = getgrnam(gname);

	if (is_root)
		root_gr = dpkg_sysgroup_copy(gr);

	return gr;
}

struct group *
dpkg_sysgroup_from_gid(gid_t gid)
{
	return getgrgid(gid);
}
