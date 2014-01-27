/*
 * libdpkg - Debian packaging suite library routines
 * ar.c - primitives for ar handling
 *
 * Copyright © 2010 Guillem Jover <guillem@debian.org>
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

#include <time.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/fdio.h>
#include <dpkg/buffer.h>
#include <dpkg/ar.h>

static void
dpkg_ar_member_init(struct dpkg_ar_member *member, const char *name, off_t size)
{
	member->name = name;
	member->size = size;
	member->time = time(NULL);
	member->mode = 0100644;
	member->uid = 0;
	member->gid = 0;
}

void
dpkg_ar_normalize_name(struct ar_hdr *arh)
{
	char *name = arh->ar_name;
	int i;

	/* Remove trailing spaces from the member name. */
	for (i = sizeof(arh->ar_name) - 1; i >= 0 && name[i] == ' '; i--)
		name[i] = '\0';

	/* Remove optional slash terminator (on GNU-style archives). */
	if (name[i] == '/')
		name[i] = '\0';
}

off_t
dpkg_ar_member_get_size(const char *ar_name, struct ar_hdr *arh)
{
	const char *str = arh->ar_size;
	int len = sizeof(arh->ar_size);
	off_t size = 0;

	while (len && *str == ' ')
		str++, len--;

	while (len--) {
		if (*str == ' ')
			break;
		if (*str < '0' || *str > '9')
			ohshit(_("invalid character '%c' in archive '%.250s' "
			         "member '%.16s' size"),
			       *str, arh->ar_name, ar_name);

		size *= 10;
		size += *str++ - '0';
	}

	return size;
}

bool
dpkg_ar_member_is_illegal(struct ar_hdr *arh)
{
	return memcmp(arh->ar_fmag, ARFMAG, sizeof(arh->ar_fmag)) != 0;
}

void
dpkg_ar_put_magic(const char *ar_name, int ar_fd)
{
	if (fd_write(ar_fd, DPKG_AR_MAGIC, strlen(DPKG_AR_MAGIC)) < 0)
		ohshite(_("unable to write file '%s'"), ar_name);
}

void
dpkg_ar_member_put_header(const char *ar_name, int ar_fd,
                          struct dpkg_ar_member *member)
{
	char header[sizeof(struct ar_hdr) + 1];
	int n;

	if (strlen(member->name) > 15)
		ohshit(_("ar member name '%s' length too long"), member->name);
	if (member->size > 9999999999L)
		ohshit(_("ar member size %jd too large"), member->size);

	n = sprintf(header, "%-16s%-12lu%-6lu%-6lu%-8lo%-10jd`\n",
	            member->name, (unsigned long)member->time,
	            (unsigned long)member->uid, (unsigned long)member->gid,
	            (unsigned long)member->mode, (intmax_t)member->size);
	if (n != sizeof(struct ar_hdr))
		ohshit(_("generated corrupt ar header for '%s'"), ar_name);

	if (fd_write(ar_fd, header, n) < 0)
		ohshite(_("unable to write file '%s'"), ar_name);
}

void
dpkg_ar_member_put_mem(const char *ar_name, int ar_fd,
                       const char *name, const void *data, size_t size)
{
	struct dpkg_ar_member member;

	dpkg_ar_member_init(&member, name, size);
	dpkg_ar_member_put_header(ar_name, ar_fd, &member);

	/* Copy data contents. */
	if (fd_write(ar_fd, data, size) < 0)
		ohshite(_("unable to write file '%s'"), ar_name);

	if (size & 1)
		if (fd_write(ar_fd, "\n", 1) < 0)
			ohshite(_("unable to write file '%s'"), ar_name);
}

void
dpkg_ar_member_put_file(const char *ar_name, int ar_fd,
                        const char *name, int fd, off_t size)
{
	struct dpkg_error err;
	struct dpkg_ar_member member;

	if (size <= 0) {
		struct stat st;

		if (fstat(fd, &st))
			ohshite(_("failed to fstat ar member file (%s)"), name);
		size = st.st_size;
	}

	dpkg_ar_member_init(&member, name, size);
	dpkg_ar_member_put_header(ar_name, ar_fd, &member);

	/* Copy data contents. */
	if (fd_fd_copy(fd, ar_fd, size, &err) < 0)
		ohshit(_("cannot append ar member file (%s) to '%s': %s"),
		       name, ar_name, err.str);

	if (size & 1)
		if (fd_write(ar_fd, "\n", 1) < 0)
			ohshite(_("unable to write file '%s'"), ar_name);
}
