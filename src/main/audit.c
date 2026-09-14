/*
 * dpkg - main program for package management
 * audit.c - database sanity and consistency checks
 *
 * Copyright © 1995,1996 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2006, 2008-2016 Guillem Jover <guillem@debian.org>
 * Copyright © 2011 Linaro Limited
 * Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
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

#include <sys/types.h>

#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/arch.h>
#include <dpkg/pkg-array.h>
#include <dpkg/pkg-show.h>
#include <dpkg/triglib.h>
#include <dpkg/string.h>
#include <dpkg/options.h>
#include <dpkg/db-ctrl.h>
#include <dpkg/db-fsys.h>

#include "main.h"

struct audit_problem {
	bool (*check)(struct pkginfo *, const struct audit_problem *problem);
	union {
		int number;
		const char *string;
	} value;
	const char *explanation;
};

static bool
audit_reinstreq(struct pkginfo *pkg, const struct audit_problem *problem)
{
	return pkg->eflag & PKG_EFLAG_REINSTREQ;
}

static bool
audit_status(struct pkginfo *pkg, const struct audit_problem *problem)
{
	if (pkg->eflag & PKG_EFLAG_REINSTREQ)
		return false;

	return (int)pkg->status == problem->value.number;
}

static bool
audit_infofile(struct pkginfo *pkg, const struct audit_problem *problem)
{
	if (pkg->status < PKG_STAT_HALFINSTALLED)
		return false;

	return !pkg_infodb_has_file(pkg, &pkg->installed, problem->value.string);
}

static bool
audit_arch(struct pkginfo *pkg, const struct audit_problem *problem)
{
	if (pkg->status < PKG_STAT_HALFINSTALLED)
		return false;

	return pkg->installed.arch->type == (enum dpkg_arch_type)problem->value.number;
}

static const struct audit_problem audit_problems[] = {
	{
		.check = audit_reinstreq,
		.value.number = 0,
		.explanation = N_(
"The following packages are in a mess due to serious problems during\n"
"installation. They must be reinstalled for them (and any packages\n"
"that depend on them) to function properly:\n"
		),
	}, {
		.check = audit_status,
		.value.number = PKG_STAT_UNPACKED,
		.explanation = N_(
"The following packages have been unpacked but not yet configured.\n"
"They must be configured using dpkg --configure or the configure\n"
"menu option in dselect for them to work:\n"
		),
	}, {
		.check = audit_status,
		.value.number = PKG_STAT_HALFCONFIGURED,
		.explanation = N_(
"The following packages are only half configured, probably due to problems\n"
"configuring them the first time. The configuration should be retried using\n"
"dpkg --configure <package> or the configure menu option in dselect:\n"
		),
	}, {
		.check = audit_status,
		.value.number = PKG_STAT_HALFINSTALLED,
		.explanation = N_(
"The following packages are only half installed, due to problems during\n"
"installation. The installation can probably be completed by retrying it;\n"
"the packages can be removed using dselect or dpkg --remove:\n"
		),
	}, {
		.check = audit_status,
		.value.number = PKG_STAT_TRIGGERSAWAITED,
		.explanation = N_(
"The following packages are awaiting processing of triggers that they\n"
"have activated in other packages. This processing can be requested using\n"
"dselect or dpkg --configure --pending (or dpkg --triggers-only):\n"
		),
	}, {
		.check = audit_status,
		.value.number = PKG_STAT_TRIGGERSPENDING,
		.explanation = N_(
"The following packages have been triggered, but the trigger processing\n"
"has not yet been done. Trigger processing can be requested using\n"
"dselect or dpkg --configure --pending (or dpkg --triggers-only):\n"
		),
	}, {
		.check = audit_infofile,
		.value.string = LISTFILE,
		.explanation = N_(
"The following packages are missing the list control file in the\n"
"database, they need to be reinstalled:\n"
		),
	}, {
		.check = audit_infofile,
		.value.string = HASHFILE,
		.explanation = N_(
"The following packages are missing the md5sums control file in the\n"
"database, they need to be reinstalled:\n"
		),
	}, {
		.check = audit_arch,
		.value.number = DPKG_ARCH_EMPTY,
		.explanation = N_(
"The following packages do not have an architecture:\n"
		),
	}, {
		.check = audit_arch,
		.value.number = DPKG_ARCH_INVALID,
		.explanation = N_(
"The following packages have an invalid architecture:\n"
		),
	}, {
		.check = audit_arch,
		.value.number = DPKG_ARCH_UNKNOWN,
		.explanation = N_(
"The following packages have an unknown foreign architecture, which will\n"
"cause dependency issues on front-ends. This can be fixed by registering\n"
"the foreign architecture with dpkg --add-architecture:\n"
		),
	}, {
		.check = NULL,
	}
};

static struct pkginfo *
pkg_array_mapper(const char *name)
{
	struct pkginfo *pkg;

	pkg = dpkg_options_parse_pkgname(cipaction, name);
	if (pkg->status == PKG_STAT_NOTINSTALLED)
		notice(_("package '%s' is not installed"),
		       pkg_name(pkg, pnaw_nonambig));

	return pkg;
}

static bool
audit_db_is_known_file(const char *filename)
{
	const char *known_files[] = {
		DPKG_DB_LOCK_FILE,
		DPKG_DB_FRONTEND_LOCK_FILE,
		DPKG_DB_ARCH_FILE,
		DPKG_DB_ARCH_NATIVE_FILE,
		DPKG_DB_STATUS_FILE,
		DPKG_DB_STATUS_FILE "-old",
		DPKG_DB_DIVERSIONS_FILE,
		DPKG_DB_DIVERSIONS_FILE "-old",
		DPKG_DB_STATOVERRIDE_FILE,
		DPKG_DB_STATOVERRIDE_FILE "-old",
		DPKG_DB_AVAIL_FILE,
		DPKG_DB_AVAIL_FILE "-old",

		DPKG_DB_REASSEMBLE_TMPFILE,

		/* dselect method files. */
		DPKG_DB_METHODS_STATE_FILE,
		DPKG_DB_METHODS_LOCK_FILE,

		/* Let the database be tracked with git, such as with
		 * dpkg-db-keeper. */
		".gitattributes",
		".gitignore",
	};

	for (size_t i = 0; i < countof(known_files); i++)
		if (strcmp(filename, known_files[i]) == 0)
			return true;

	return false;
}

static bool
audit_db_is_known_dir(const char *dirname)
{
	const char *known_dirs[] = {
		DPKG_DB_CONTROL_TMPDIR,
		DPKG_DB_INFO_DIR,
		DPKG_DB_TRIGGERS_DIR,
		DPKG_DB_UPDATES_DIR,
		DPKG_DB_PARTS_DIR,
		DPKG_DB_METHODS_DIR,

		"alternatives",

		/* Let the database be tracked with git, such as with
		 * dpkg-db-keeper. */
		".git",
	};

	for (size_t i = 0; i < countof(known_dirs); i++)
		if (strcmp(dirname, known_dirs[i]) == 0)
			return true;

	return false;
}

static void
audit_db(void)
{
	DIR *db_dir;
	struct dirent *de;
	struct varbuf pathname = VARBUF_INIT;

	db_dir = opendir(dpkg_db_get_dir());

	while ((de = readdir(db_dir))) {
		struct stat st;

		if (strcmp(de->d_name, ".") == 0 ||
		    strcmp(de->d_name, "..") == 0)
			continue;

		varbuf_reset(&pathname);
		varbuf_add_str(&pathname, dpkg_db_get_dir());
		varbuf_add_char(&pathname, '/');
		varbuf_add_str(&pathname, de->d_name);

		if (lstat(pathname.buf, &st) < 0)
			ohshite(_("cannot get pathname '%s' metadata"),
			        pathname.buf);

		if (audit_db_is_known_file(de->d_name)) {
			if (!S_ISREG(st.st_mode))
				printf(_("pathname '%s' in database directory "
				         "is not a regular file\n"),
				       de->d_name);
			continue;
		}
		if (audit_db_is_known_dir(de->d_name)) {
			if (!S_ISDIR(st.st_mode))
				printf(_("pathname '%s' in database directory "
				         "is not a directory\n"),
				       de->d_name);
			continue;
		}

		printf(_("unknown entry '%s' in database directory\n"),
		       de->d_name);
	}

	closedir(db_dir);
}

int
audit(const char *const *argv)
{
	const struct audit_problem *problem;
	struct pkg_array array;
	bool head_running = false;
	int i;

	audit_db();

	modstatdb_open(msdbrw_readonly);

	if (!*argv)
		pkg_array_init_from_hash(&array);
	else
		pkg_array_init_from_names(&array, pkg_array_mapper, (const char **)argv);

	pkg_array_sort(&array, pkg_sorter_by_nonambig_name_arch);

	for (problem = audit_problems; problem->check; problem++) {
		bool head = false;

		for (i = 0; i < array.n_pkgs; i++) {
			struct pkginfo *pkg = array.pkgs[i];

			if (!problem->check(pkg, problem))
				continue;

			if (!head_running) {
				if (modstatdb_is_locked())
					puts(_(
"Another process has locked the database for writing, and might currently be\n"
"modifying it, some of the following problems might just be due to that.\n"));
				head_running = true;
			}
			if (!head) {
				fputs(gettext(problem->explanation), stdout);
				head = true;
			}

			printf("  %s\n", pkg_name(pkg, pnaw_nonambig));
		}

		if (head)
			putchar('\n');
	}

	pkg_array_destroy(&array);

	m_output(stdout, _("<standard output>"));

	return 0;
}
