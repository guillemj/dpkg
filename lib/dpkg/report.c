/*
 * libdpkg - Debian packaging suite library routines
 * reoport.c - message reporting
 *
 * Copyright © 2004-2005 Scott James Remnant <scott@netsplit.com>
 * Copyright © 2008-2012 Guillem Jover <guillem@debian.org>
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

#include <stdarg.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/progname.h>
#include <dpkg/report.h>

static int warn_count = 0;

int
warning_get_count(void)
{
	return warn_count;
}

void
warningv(const char *fmt, va_list args)
{
	char buf[1024];

	warn_count++;
	vsnprintf(buf, sizeof(buf), fmt, args);
	fprintf(stderr, _("%s: warning: %s\n"), dpkg_get_progname(), buf);
}

void
warning(const char *fmt, ...)
{
	va_list args;

	va_start(args, fmt);
	warningv(fmt, args);
	va_end(args);
}
