/*
 * libdpkg - Debian packaging suite library routines
 * cleanup.c - cleanup functions, used when we need to unwind
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <dpkg.h>
#include <stdio.h>
#include <unistd.h>
#include <dirent.h>

void
cu_closepipe(int argc, void **argv)
{
	int *p1 = (int *)argv[0];

	close(p1[0]);
	close(p1[1]);
}

void
cu_closefile(int argc, void **argv)
{
	FILE *f = (FILE *)(argv[0]);

	fclose(f);
}

void
cu_closedir(int argc, void **argv)
{
	DIR *d = (DIR *)(argv[0]);

	closedir(d);
}

void
cu_closefd(int argc, void **argv)
{
	int ip = *(int *)argv[0];

	close(ip);
}

