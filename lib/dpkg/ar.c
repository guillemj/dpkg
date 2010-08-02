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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <time.h>
#include <unistd.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/buffer.h>
#include <dpkg/ar.h>

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

void
dpkg_ar_put_magic(const char *ar_name, int ar_fd)
{
	if (write(ar_fd, DPKG_AR_MAGIC, strlen(DPKG_AR_MAGIC)) < 0)
		ohshite(_("unable to write file '%s'"), ar_name);
}

void
dpkg_ar_member_put_header(const char *ar_name, int ar_fd,
                          const char *name, size_t size)
{
	char header[sizeof(struct ar_hdr) + 1];
	int n;

	n = sprintf(header, "%-16s%-12lu0     0     100644  %-10lu`\n",
	            name, time(NULL), (unsigned long)size);
	if (n != sizeof(struct ar_hdr))
		ohshit(_("generated corrupt ar header for '%s'"), ar_name);

	if (write(ar_fd, header, n) < 0)
		ohshite(_("unable to write file '%s'"), ar_name);
}

void
dpkg_ar_member_put_mem(const char *ar_name, int ar_fd,
                       const char *name, const void *data, size_t size)
{
	dpkg_ar_member_put_header(ar_name, ar_fd, name, size);

	/* Copy data contents. */
	if (write(ar_fd, data, size) < 0)
		ohshite(_("unable to write file '%s'"), ar_name);

	if (size & 1)
		if (write(ar_fd, "\n", 1) < 0)
			ohshite(_("unable to write file '%s'"), ar_name);
}

void
dpkg_ar_member_put_file(const char *ar_name, int ar_fd,
                        const char *name, int fd)
{
	struct stat st;

	if (fstat(fd, &st))
		ohshite(_("failed to fstat ar member file (%s)"), name);

	dpkg_ar_member_put_header(ar_name, ar_fd, name, st.st_size);

	/* Copy data contents. */
	fd_fd_copy(fd, ar_fd, -1, name);

	if (st.st_size & 1)
		if (write(ar_fd, "\n", 1) < 0)
			ohshite(_("unable to write file '%s'"), ar_name);
}
