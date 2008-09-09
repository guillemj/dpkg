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

#include <sys/types.h>
#include <sys/stat.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

#ifndef HAVE_VSNPRINTF
int
vsnprintf(char *buf, size_t maxsize, const char *fmt, va_list al)
{
	static FILE *file = NULL;

	struct stat stab;
	unsigned long want, nr;
	int retval;

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

	if (vfprintf(file, fmt, al) == EOF)
		return -1;
	if (fflush(file))
		return -1;
	if (fstat(fileno(file), &stab))
		return -1;
	if (fseek(file, 0, 0))
		return -1;

	want = stab.st_size;
	if (want >= maxsize) {
		want = maxsize - 1;
		retval = -1;
	} else {
		retval = want;
	}

	nr = fread(buf, 1, want - 1, file);
	if (nr != want - 1)
		return -1;
	buf[want] = NULL;

	return retval;
}
#endif

