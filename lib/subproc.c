/*
 * libdpkg - Debian packaging suite library routines
 * subproc.c - subprocess helper routines
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

#include <config.h>

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>

#include <dpkg.h>
#include <dpkg-priv.h>

#define NCATCHSIGNALS (int)(sizeof(catch_signals) / sizeof(int) - 1)
static int catch_signals[] = { SIGQUIT, SIGINT, 0 };
static struct sigaction uncatch_signals[NCATCHSIGNALS];

void
setup_subproc_signals(const char *name)
{
	int i;
	struct sigaction catchsig;

	onerr_abort++;
	memset(&catchsig, 0, sizeof(catchsig));
	catchsig.sa_handler = SIG_IGN;
	sigemptyset(&catchsig.sa_mask);
	catchsig.sa_flags = 0;
	for (i = 0; i < NCATCHSIGNALS; i++)
	if (sigaction(catch_signals[i], &catchsig, &uncatch_signals[i]))
		ohshite(_("unable to ignore signal %s before running %.250s"),
		        strsignal(catch_signals[i]), name);
	push_cleanup(cu_subproc_signals, ~0, NULL, 0, 0);
	onerr_abort--;
}

void
cu_subproc_signals(int argc, void **argv)
{
	int i;

	for (i = 0; i < NCATCHSIGNALS; i++) {
		if (sigaction(catch_signals[i], &uncatch_signals[i], NULL)) {
			fprintf(stderr, _("error un-catching signal %s: %s\n"),
			        strsignal(catch_signals[i]), strerror(errno));
			onerr_abort++;
		}
	}
}

