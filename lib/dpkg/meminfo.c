/*
 * libdpkg - Debian packaging suite library routines
 * meminfo.c - system memory information functions
 *
 * Copyright © 2021 Sebastian Andrzej Siewior <sebastian@breakpoint.cc>
 * Copyright © 2021-2022 Guillem Jover <guillem@debian.org>
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

#include <sys/stat.h>

#include <errno.h>
#include <inttypes.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#include <dpkg/dpkg.h>
#include <dpkg/fdio.h>
#include <dpkg/meminfo.h>

#ifdef __linux__
/*
 * An estimate of how much memory is available. Swap will not be used, the
 * page cache may be purged, not everything will be reclaimed that might be
 * reclaimed, watermarks are considered.
 */
static const char str_MemAvailable[] = "MemAvailable";
static const size_t len_MemAvailable = sizeof(str_MemAvailable) - 1;

int
meminfo_get_available(uint64_t *val)
{
	char buf[4096];
	char *str;
	ssize_t bytes;
	int fd;

	*val = 0;

	fd = open("/proc/meminfo", O_RDONLY);
	if (fd < 0)
		return -1;

	bytes = fd_read(fd, buf, sizeof(buf));
	close(fd);

	if (bytes <= 0)
		return -1;

	buf[bytes] = '\0';

	str = buf;
	while (1) {
		char *end;

		end = strchr(str, ':');
		if (end == 0)
			break;

		if ((end - str) == len_MemAvailable &&
		    strncmp(str, str_MemAvailable, len_MemAvailable) == 0) {
			intmax_t num;

			str = end + 1;
			errno = 0;
			num = strtoimax(str, &end, 10);
			if (num <= 0)
				return -1;
			if ((num == INTMAX_MAX) && errno == ERANGE)
				return -1;
			/* It should end with ' kB\n'. */
			if (*end != ' ' || *(end + 1) != 'k' ||
			    *(end + 2) != 'B')
				return -1;

			/* This should not overflow, but just in case. */
			if (num < (INTMAX_MAX / 1024))
				num *= 1024;
			*val = num;
			return 0;
		}

		end = strchr(end + 1, '\n');
		if (end == 0)
			break;
		str = end + 1;
	}
	return -1;
}
#else
int
meminfo_get_available(uint64_t *val)
{
	return -1;
}
#endif
