/*
 * libdpkg - Debian packaging suite library routines
 * utils.c - Helper functions for dpkg
 *
 * Copyright (C) 2001 Wichert Akkerman <wakkerma@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of version 2 of the GNU General Public
 * License version 2 as published by the Free Software Foundation.
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
#include <dpkg.h>

/* Reimplementation of the standard ctype.h is* functions. Since gettext
 * has overloaded the meaning of LC_CTYPE we can't use that to force C
 * locale, so use these cis* functions instead.
 */
int cisdigit(int c) {
	return (c>='0') && (c<='9');
}

int cisalpha(int c) {
	return ((c>='a') && (c<='z')) || ((c>='A') && (c<='Z'));
}
