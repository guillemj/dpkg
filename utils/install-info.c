/*
 * install-info.c - transitional ginstall-info wrapper
 *
 * Copyright © 2009 Raphaël Hertzog <hertzog@debian.org>
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

#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#define SELF "/usr/sbin/install-info"
#define WRAPPED "/usr/bin/install-info"

#if HAVE_C99
#define warn(...) fprintf(stderr, "install-info: warning: " __VA_ARGS__)
#define error(...) fprintf(stderr, "install-info: error: " __VA_ARGS__)
#else
#define warn(msg...) fprintf(stderr, "install-info: warning: " msg)
#define error(msg...) fprintf(stderr, "install-info: error: " msg)
#endif

int
main(int argc, char **argv)
{
    if (strcmp(argv[0], SELF) == 0) {
	warn("don't call programs like install-info with an absolute path,\n");
	warn("%s provided by dpkg is deprecated and will go away soon;\n",
	     SELF);
	warn("its replacement lives in /usr/bin/.\n");
    }

    if (access(WRAPPED, X_OK) == 0) {
	execv(WRAPPED, argv);
	error("can't execute %s: %s\n", WRAPPED, strerror(errno));
	return 1; /* exec failed */
    } else {
	if (errno == ENOENT) {
	    if (getenv("DPKG_RUNNING_VERSION") != NULL) {
		const char *pkg;

		pkg = getenv("DPKG_MAINTSCRIPT_PACKAGE");

		warn("maintainer scripts should not call install-info anymore,\n");
		warn("this is handled now by a dpkg trigger provided by the\n");
		warn("install-info package; package %s should be updated.\n",
		     pkg);
	    } else {
		warn("nothing done since %s doesn't exist,\n", WRAPPED);
		warn("you might want to install an info-browser package.\n");
	    }
	} else {
	    error("can't execute %s: %s\n", WRAPPED, strerror(errno));
	    return 1;
	}
    }

    return 0;
}
