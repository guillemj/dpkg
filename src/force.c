/*
 * dpkg - main program for package management
 * force.c - force operation support
 *
 * Copyright © 1994,1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2006-2019 Guillem Jover <guillem@debian.org>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <errno.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/options.h>

#include "force.h"

int fc_architecture = 0;
int fc_badpath = 0;
int fc_badverify = 0;
int fc_badversion = 0;
int fc_breaks = 0;
int fc_conff_ask = 0;
int fc_conff_def = 0;
int fc_conff_miss = 0;
int fc_conff_new = 0;
int fc_conff_old = 0;
int fc_configureany = 0;
int fc_conflicts = 0;
int fc_depends = 0;
int fc_dependsversion = 0;
int fc_downgrade = 1;
int fc_hold = 0;
int fc_nonroot = 0;
int fc_overwrite = 0;
int fc_overwritedir = 0;
int fc_overwritediverted = 0;
int fc_removeessential = 0;
int fc_removereinstreq = 0;
int fc_script_chrootless = 0;
int fc_unsafe_io = 0;

static const char *
forcetype_str(char type)
{
	switch (type) {
	case '\0':
	case ' ':
		return "   ";
	case '*':
		return "[*]";
	case '!':
		return "[!]";
	default:
		internerr("unknown force type '%c'", type);
	}
}

static const struct forceinfo {
	const char *name;
	int *opt;
	char type;
	const char *desc;
} forceinfos[] = {
	{
		"all",
		NULL,
		'!',
		N_("Set all force options"),
	}, {
		"downgrade",
		&fc_downgrade,
		'*',
		N_("Replace a package with a lower version"),
	}, {
		"configure-any",
		&fc_configureany,
		' ',
		N_("Configure any package which may help this one"),
	}, {
		"hold",
		&fc_hold,
		' ',
		N_("Process incidental packages even when on hold"),
	}, {
		"not-root",
		&fc_nonroot,
		' ',
		N_("Try to (de)install things even when not root"),
	}, {
		"bad-path",
		&fc_badpath,
		' ',
		N_("PATH is missing important programs, problems likely"),
	}, {
		"bad-verify",
		&fc_badverify,
		' ',
		N_("Install a package even if it fails authenticity check"),
	}, {
		"bad-version",
		&fc_badversion,
		' ',
		N_("Process even packages with wrong versions"),
	}, {
		"overwrite",
		&fc_overwrite,
		' ',
		N_("Overwrite a file from one package with another"),
	}, {
		"overwrite-diverted",
		&fc_overwritediverted,
		' ',
		N_("Overwrite a diverted file with an undiverted version"),
	}, {
		"overwrite-dir",
		&fc_overwritedir,
		'!',
		N_("Overwrite one package's directory with another's file"),
	}, {
		"unsafe-io",
		&fc_unsafe_io,
		'!',
		N_("Do not perform safe I/O operations when unpacking"),
	}, {
		"script-chrootless",
		&fc_script_chrootless,
		'!',
		N_("Do not chroot into maintainer script environment"),
	}, {
		"confnew",
		&fc_conff_new,
		'!',
		N_("Always use the new config files, don't prompt"),
	}, {
		"confold",
		&fc_conff_old,
		'!',
		N_("Always use the old config files, don't prompt"),
	}, {
		"confdef",
		&fc_conff_def,
		'!',
		N_("Use the default option for new config files if one\n"
		   "is available, don't prompt. If no default can be found,\n"
		   "you will be prompted unless one of the confold or\n"
		   "confnew options is also given"),
	}, {
		"confmiss",
		&fc_conff_miss,
		'!',
		N_("Always install missing config files"),
	}, {
		"confask",
		&fc_conff_ask,
		'!',
		N_("Offer to replace config files with no new versions"),
	}, {
		"architecture",
		&fc_architecture,
		'!',
		N_("Process even packages with wrong or no architecture"),
	}, {
		"breaks",
		&fc_breaks,
		'!',
		N_("Install even if it would break another package"),
	}, {
		"conflicts",
		&fc_conflicts,
		'!',
		N_("Allow installation of conflicting packages"),
	}, {
		"depends",
		&fc_depends,
		'!',
		N_("Turn all dependency problems into warnings"),
	}, {
		"depends-version",
		&fc_dependsversion,
		'!',
		N_("Turn dependency version problems into warnings"),
	}, {
		"remove-reinstreq",
		&fc_removereinstreq,
		'!',
		N_("Remove packages which require installation"),
	}, {
		"remove-essential",
		&fc_removeessential,
		'!',
		N_("Remove an essential package"),
	}, {
		NULL
	}
};

static inline void
print_forceinfo_line(int type, const char *name, const char *desc)
{
	printf("  %s %-18s %s\n", forcetype_str(type), name, desc);
}

static void
print_forceinfo(const struct forceinfo *fi)
{
	char *desc, *line;

	desc = m_strdup(gettext(fi->desc));

	line = strtok(desc, "\n");
	print_forceinfo_line(fi->type, fi->name, line);
	while ((line = strtok(NULL, "\n")))
		print_forceinfo_line(' ', "", line);

	free(desc);
}

void
set_force(const struct cmdinfo *cip, const char *value)
{
	const char *comma;
	size_t l;
	const struct forceinfo *fip;

	if (strcmp(value, "help") == 0) {
		printf(_(
"%s forcing options - control behaviour when problems found:\n"
"  warn but continue:  --force-<thing>,<thing>,...\n"
"  stop with error:    --refuse-<thing>,<thing>,... | --no-force-<thing>,...\n"
" Forcing things:\n"), DPKG);

		for (fip = forceinfos; fip->name; fip++)
			print_forceinfo(fip);

		printf(_(
"\n"
"WARNING - use of options marked [!] can seriously damage your installation.\n"
"Forcing options marked [*] are enabled by default.\n"));
		m_output(stdout, _("<standard output>"));
		exit(0);
	}

	for (;;) {
		comma = strchrnul(value, ',');
		l = (size_t)(comma - value);
		for (fip = forceinfos; fip->name; fip++)
			if (strncmp(fip->name, value, l) == 0 &&
			    strlen(fip->name) == l)
				break;

		if (!fip->name) {
			badusage(_("unknown force/refuse option '%.*s'"),
			         (int)min(l, 250), value);
		} else if (strcmp(fip->name, "all") == 0) {
			for (fip = forceinfos; fip->name; fip++)
				if (fip->opt)
					*fip->opt = cip->arg_int;
		} else if (fip->opt) {
			*fip->opt = cip->arg_int;
		} else {
			warning(_("obsolete force/refuse option '%s'"),
			        fip->name);
		}

		if (*comma == '\0')
			break;
		value = ++comma;
	}
}

void
forcibleerr(int forceflag, const char *fmt, ...)
{
	va_list args;

	va_start(args, fmt);
	if (forceflag) {
		warning(_("overriding problem because --force enabled:"));
		warningv(fmt, args);
	} else {
		ohshitv(fmt, args);
	}
	va_end(args);
}

int
forcible_nonroot_error(int rc)
{
	if (fc_nonroot && errno == EPERM)
		return 0;
	return rc;
}
