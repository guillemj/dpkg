/*
 * libdpkg - Debian packaging suite library routines
 * term.c - terminal support
 *
 * Copyright © 2026 Guillem Jover <guillem@debian.org>
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

#include <sys/ioctl.h>

#include <limits.h>
#include <errno.h>
#include <fcntl.h>
#include <termios.h>
#include <stdlib.h>
#include <unistd.h>

#include <dpkg/macros.h>
#include <dpkg/term.h>

int
term_get_width(void)
{
	const char *columns;
	long width;
	int fd;
	struct winsize ws;

	columns = getenv("COLUMNS");
	if (columns) {
		char *endptr;

		errno = 0;
		width = strtol(columns, &endptr, 10);
		if (errno == 0 && columns != endptr && *endptr == '\0' &&
		    width > 0 && width < INT_MAX)
			return width;
	}

	width = 80;
	fd = open("/dev/tty", O_RDONLY);
	if (fd >= 0) {
		if (ioctl(fd, TIOCGWINSZ, &ws) == 0)
			width = ws.ws_col;
		close(fd);
	}

	return width;
}
