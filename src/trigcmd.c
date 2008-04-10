/*
 * dpkg-trigger - trigger management utility
 *
 * Copyright (C) 2007 Canonical Ltd.
 * Written by Ian Jackson <ian@davenant.greenend.org.uk>
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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fnmatch.h>
#include <assert.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/termios.h>
#include <fcntl.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

static const char *bypackage, *activate, *admindir = ADMINDIR;
static int f_noact, f_check;

static void
noawait(const struct cmdinfo *ci, const char *value)
{
	bypackage = "-";
}

static const struct cmdinfo cmdinfos[] = {
	{ "admindir",        0,   1, NULL,     &admindir },
	{ "by-package",      'f', 1, NULL,     &bypackage },
	{ "no-await",        0,   0, NULL,     &bypackage, noawait },
	{ "no-act",          0,   0, &f_noact, NULL,       0, 1 },
	{ "check-supported", 0,   0, &f_check, NULL,       0, 1 },
	{ "help",            'h', 0, NULL,     NULL,       helponly },
	{ "version",         0,   0, NULL,     NULL,       versiononly },
	/* UK spelling */
	{ "licence",         0,   0, NULL,     NULL,       showcopyright },
	/* US spelling */
	{ "license",         0,   0, NULL,     NULL,       showcopyright },
	{  NULL  }
};

const char thisname[] = "dpkg-trigger";

const char printforhelp[] = N_(
"Type dpkg-trigger --help for help about this utility.");

void
printversion(void)
{
	if (printf(_("Debian %s package trigger utility.\n"), thisname) < 0)
		werr("stdout");

	if (printf(_(
"This is free software; see the GNU General Public License version 2 or\n"
"later for copying conditions. There is NO warranty.\n"
"See %s --license for copyright and license details.\n"), thisname) < 0)
		werr("stdout");
}

void
usage(void)
{
	if (printf(_(
"Usage: %s [<options> ...] <trigger-name>\n"
"       %s [<options> ...] <command>\n"
"\n"), thisname, thisname) < 0)
		werr ("stdout");

	if (printf(_(
"Commands:\n"
"  --check-supported                Check if the running dpkg supports triggers.\n"
"\n")) < 0)
		werr ("stdout");

	if (printf(_(
"  -h|--help                        Show this help message.\n"
"  --version                        Show the version.\n"
"  --license|--licence              Show the copyright licensing terms.\n"
"\n")) < 0)
		werr ("stdout");

	if (printf(_(
"Options:\n"
"  --admindir=<directory>           Use <directory> instead of %s.\n"
"  --by-package=<package>           Override trigger awaiter (normally set\n"
"                                     by dpkg).\n"
"  --no-await                       No package needs to await the processing.\n"
"  --no-act                         Just test - don't actually change anything.\n"
"\n"), admindir) < 0)
		werr("stdout");
}

static int done_trig, ctrig;

static void
yespackage(const char *awname)
{
	fprintf(trig_new_deferred, " %s", awname);
}

static void
tdm_add_trig_begin(const char *trig)
{
	ctrig = !strcmp(trig, activate);
	fputs(trig, trig_new_deferred);
	if (!ctrig || done_trig)
		return;
	yespackage(bypackage);
	done_trig = 1;
}

static void
tdm_add_package(const char *awname)
{
	if (ctrig && !strcmp(awname, bypackage))
		return;
	yespackage(awname);
}

static void
tdm_add_trig_end(void)
{
	fputc('\n', trig_new_deferred);
}

static const struct trigdefmeths tdm_add = {
	tdm_add_trig_begin,
	tdm_add_package,
	tdm_add_trig_end
};

static void
do_check(void)
{
	int uf;

	uf = trigdef_update_start(tduf_nolockok, admindir);
	switch (uf) {
	case -1:
		fprintf(stderr, _("%s: triggers data directory not yet created\n"),
		        thisname);
		exit(1);
	case -3:
		fprintf(stderr, _("%s: trigger records not yet in existence\n"),
		        thisname);
		exit(1);
	case 2:
	case -2:
		exit(0);
	default:
		abort();
	}
}

int
main(int argc, const char *const *argv)
{
	jmp_buf ejbuf;
	int uf;
	const char *badname;
	enum trigdef_updateflags tduf;

	standard_startup(&ejbuf, argc, &argv, NULL, 0, cmdinfos);
	setvbuf(stdout, NULL, _IONBF, 0);

	if (f_check) {
		if (*argv)
			badusage(_("dpkg-trigger --check-supported takes no arguments"));
		do_check();
	}

	if (!*argv || argv[1])
		badusage(_("dpkg-trigger takes one argument, the trigger name"));

	if (!bypackage) {
		bypackage = getenv(MAINTSCRIPTPKGENVVAR);
		if (!bypackage)
			ohshit(_("dpkg-trigger must be called from a maintainer script"
			       " (or with a --by-package option)"));
	}
	if (strcmp(bypackage, "-") &&
	    (badname = illegal_packagename(bypackage, NULL)))
		ohshit(_("dpkg-trigger: illegal awaited package name `%.250s': %.250s"),
		       bypackage, badname);

	activate = argv[0];
	if ((badname = illegal_triggername(activate)))
		badusage(_("dpkg-trigger: invalid trigger name `%.250s': %.250s"),
		         activate, badname);

	trigdef = &tdm_add;
	tduf = tduf_nolockok;
	if (!f_noact)
		tduf |= tduf_write | tduf_writeifempty;
	uf = trigdef_update_start(tduf, admindir);
	if (uf >= 0) {
		trigdef_yylex();
		if (!done_trig)
			fprintf(trig_new_deferred, "%s %s\n",
			        activate, bypackage);
		trigdef_process_done();
	}

	standard_shutdown(0);

	return 0;
}

