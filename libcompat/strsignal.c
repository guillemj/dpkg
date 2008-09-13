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

#include <signal.h>
#include <string.h>
#include <stdio.h>
#include <gettext.h>

#define _(str) gettext(str)

#ifndef HAVE_DECL_SYS_SIGLIST
const char *const sys_siglist[] = {
	"SIGHUP",	/* 1 */
	"SIGINT",	/* 2 */
	"SIGQUIT",	/* 3 */
	"SIGILL",	/* 4 */
	"SIGTRAP",	/* 5 */
	"SIGABRT",	/* 6 */
	"SIGEMT",	/* 7 */
	"SIGFPE",	/* 8 */
	"SIGKILL",	/* 9 */
	"SIGUSR1",	/* 10 */
	"SIGSEGV",	/* 11 */
	"SIGUSR2",	/* 12 */
	"SIGPIPE",	/* 13 */
	"SIGALRM",	/* 14 */
	"SIGTERM",	/* 15 */
	"SIGSTKFLT",	/* 16 */
	"SIGCHLD",	/* 17 */
	"SIGCONT",	/* 18 */
	"SIGSTOP",	/* 19 */
	"SIGTSTP",	/* 20 */
	"SIGTTIN",	/* 21 */
	"SIGTTOU",	/* 22 */
};
#else
extern const char *const sys_siglist[];
#endif

#ifndef HAVE_STRSIGNAL
const char *
strsignal(int s)
{
	static char buf[100];

	if (s >= 0 && s < sizeof(sys_siglist) / sizeof(sys_siglist[0]))
		return sys_siglist[s];

	sprintf(buf, _("Signal no.%d"), s);

	return buf;
}
#endif

