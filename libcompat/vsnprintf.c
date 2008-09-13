/*
 * libcompat - system compatibility library
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2,
 * or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

#ifndef HAVE_VSNPRINTF
int
vsnprintf(char *buf, size_t maxsize, const char *fmt, va_list al)
{
	static FILE *file = NULL;

	size_t want, nr;
	int total;

	if (maxsize == 0)
		return -1;

	if (!file) {
		file = tmpfile();
		if (!file)
			return -1;
	} else {
		if (fseek(file, 0, 0))
			return -1;
		if (ftruncate(fileno(file), 0))
			return -1;
	}

	total = vfprintf(file, fmt, al);
	if (total < 0)
		return -1;
	if (total >= (int)maxsize)
		want = maxsize - 1;
	else
		want = total;
	if (fflush(file))
		return -1;
	if (fseek(file, 0, SEEK_SET))
		return -1;

	nr = fread(buf, 1, want, file);
	if (nr != want)
		return -1;
	buf[want] = '\0';

	return total;
}
#endif

