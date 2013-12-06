/*
 * libdpkg - Debian packaging suite library routines
 * fdio.c - safe file descriptor based input/output
 *
 * Copyright © 2009-2010 Guillem Jover <guillem@debian.org>
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

#include <errno.h>
#include <unistd.h>

#include <dpkg/fdio.h>

ssize_t
fd_read(int fd, void *buf, size_t len)
{
	ssize_t total = 0;
	char *ptr = buf;

	while (len > 0) {
		ssize_t n;

		n = read(fd, ptr + total, len);
		if (n == -1) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			return total ? -total : n;
		}
		if (n == 0)
			break;

		total += n;
		len -= n;
	}

	return total;
}

ssize_t
fd_write(int fd, const void *buf, size_t len)
{
	ssize_t total = 0;
	const char *ptr = buf;

	while (len > 0) {
		ssize_t n;

		n = write(fd, ptr + total, len);
		if (n == -1) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			return total ? -total : n;
		}
		if (n == 0)
			break;

		total += n;
		len -= n;
	}

	return total;
}
