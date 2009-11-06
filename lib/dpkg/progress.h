/*
 * dpkg - main program for package management
 * progress.c - generic progress reporting
 *
 * Copyright © 2009 Guillem Jover <guillem@debian.org>
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

#ifndef LIBDPKG_PROGRESS_H
#define LIBDPKG_PROGRESS_H

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

struct progress {
	const char *text;

	int max;
	int cur;
	int last_percent;

	int on_tty;
};

void progress_init(struct progress *progress, const char *text, int max);
void progress_step(struct progress *progress);
void progress_done(struct progress *progress);

DPKG_END_DECLS

#endif

