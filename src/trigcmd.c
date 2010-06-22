/*
 * dpkg-trigger - trigger management utility
 *
 * Copyright © 2007 Canonical Ltd.
 * Written by Ian Jackson <ian@davenant.greenend.org.uk>
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

#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/termios.h>

#include <fcntl.h>
#if HAVE_LOCALE_H
#include <locale.h>
#endif
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/myopt.h>
#include <dpkg/trigdeferred.h>
#include <dpkg/triglib.h>

const char thisname[] = "dpkg-trigger";

const char printforhelp[] = N_(
"Type dpkg-trigger --help for help about this utility.");

static void DPKG_ATTR_NORET
printversion(const struct cmdinfo *ci, const char *value)
{
	printf(_("Debian %s package trigger utility version %s.\n"),
	       thisname, DPKG_VERSION_ARCH);

	printf(_(
"This is free software; see the GNU General Public License version 2 or\n"
"later for copying conditions. There is NO warranty.\n"));

	m_output(stdout, _("<standard output>"));

	exit(0);
}

static void DPKG_ATTR_NORET
usage(const struct cmdinfo *ci, const char *value)
{
	printf(_(
"Usage: %s [<options> ...] <trigger-name>\n"
"       %s [<options> ...] <command>\n"
"\n"), thisname, thisname);

	printf(_(
"Commands:\n"
"  --check-supported                Check if the running dpkg supports triggers.\n"
"\n"));

	printf(_(
"  -h|--help                        Show this help message.\n"
"  --version                        Show the version.\n"
"\n"));

	printf(_(
"Options:\n"
"  --admindir=<directory>           Use <directory> instead of %s.\n"
"  --by-package=<package>           Override trigger awaiter (normally set\n"
"                                     by dpkg).\n"
"  --no-await                       No package needs to await the processing.\n"
"  --no-act                         Just test - don't actually change anything.\n"
"\n"), ADMINDIR);

	m_output(stdout, _("<standard output>"));

	exit(0);
}

static const char *admindir = ADMINDIR;
static int f_noact, f_check;

static const char *bypackage, *activate;
static bool done_trig, ctrig;

static void
noawait(const struct cmdinfo *ci, const char *value)
{
	bypackage = "-";
}

static void
yespackage(const char *awname)
{
	trigdef_update_printf(" %s", awname);
}

static void
tdm_add_trig_begin(const char *trig)
{
	ctrig = !strcmp(trig, activate);
	trigdef_update_printf("%s", trig);
	if (!ctrig || done_trig)
		return;
	yespackage(bypackage);
	done_trig = true;
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
	trigdef_update_printf("\n");
}

static const struct trigdefmeths tdm_add = {
	.trig_begin = tdm_add_trig_begin,
	.package = tdm_add_package,
	.trig_end = tdm_add_trig_end,
};

static void DPKG_ATTR_NORET
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
		internerr("unknown trigdef_update_start return value '%d'", uf);
	}
}

static const struct cmdinfo cmdinfos[] = {
	{ "admindir",        0,   1, NULL,     &admindir },
	{ "by-package",      'f', 1, NULL,     &bypackage },
	{ "no-await",        0,   0, NULL,     &bypackage, noawait },
	{ "no-act",          0,   0, &f_noact, NULL,       NULL, 1 },
	{ "check-supported", 0,   0, &f_check, NULL,       NULL, 1 },
	{ "help",            'h', 0, NULL,     NULL,       usage   },
	{ "version",         0,   0, NULL,     NULL,       printversion  },
	{  NULL  }
};

int
main(int argc, const char *const *argv)
{
	jmp_buf ejbuf;
	int uf;
	const char *badname;
	enum trigdef_updateflags tduf;

	setlocale(LC_ALL, "");
	bindtextdomain(PACKAGE, LOCALEDIR);
	textdomain(PACKAGE);

	standard_startup(&ejbuf);
	myopt(&argv, cmdinfos);

	setvbuf(stdout, NULL, _IONBF, 0);

	if (f_check) {
		if (*argv)
			badusage(_("--%s takes no arguments"),
			         "check-supported");
		do_check();
	}

	if (!*argv || argv[1])
		badusage(_("takes one argument, the trigger name"));

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
		badusage(_("invalid trigger name `%.250s': %.250s"),
		         activate, badname);

	trigdef_set_methods(&tdm_add);

	tduf = tduf_nolockok;
	if (!f_noact)
		tduf |= tduf_write | tduf_writeifempty;
	uf = trigdef_update_start(tduf, admindir);
	if (uf >= 0) {
		trigdef_yylex();
		if (!done_trig)
			trigdef_update_printf("%s %s\n", activate, bypackage);
		trigdef_process_done();
	}

	standard_shutdown();

	return 0;
}

