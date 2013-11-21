/*
 * dpkg - main program for package management
 * verify.c - verify package integrity
 *
 * Copyright © 2012 Guillem Jover <guillem@debian.org>
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

#include <string.h>
#include <stdbool.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-spec.h>
#include <dpkg/options.h>

#include "filesdb.h"
#include "infodb.h"
#include "main.h"


enum verify_result {
	VERIFY_NONE,
	VERIFY_PASS,
	VERIFY_FAIL,
};

struct verify_checks {
	enum verify_result md5sum;
};

typedef void verify_output_func(struct filenamenode *, struct verify_checks *);

static int
verify_result_rpm(enum verify_result result, int check)
{
	switch (result) {
	case VERIFY_FAIL:
		return check;
	case VERIFY_PASS:
		return '.';
	case VERIFY_NONE:
	default:
		return '?';
	}
}

static void
verify_output_rpm(struct filenamenode *namenode, struct verify_checks *checks)
{
	char result[9];
	int attr;

	memset(result, '?', sizeof(result));

	result[2] = verify_result_rpm(checks->md5sum, '5');

	if (namenode->flags & fnnf_old_conff)
		attr = 'c';
	else
		attr = ' ';

	printf("%.9s %c %s\n", result, attr, namenode->name);
}

static verify_output_func *verify_output = verify_output_rpm;

int
verify_set_output(const char *name)
{
	if (strcmp(name, "rpm") == 0)
		verify_output = verify_output_rpm;
	else
		return 1;

	return 0;
}

static void
verify_package(struct pkginfo *pkg)
{
	struct fileinlist *file;

	ensure_packagefiles_available(pkg);
	parse_filehash(pkg, &pkg->installed);
	oldconffsetflags(pkg->installed.conffiles);

	for (file = pkg->clientdata->files; file; file = file->next) {
		struct verify_checks checks;
		struct filenamenode *fnn;
		char hash[MD5HASHLEN + 1];
		int failures = 0;

		fnn = namenodetouse(file->namenode, pkg, &pkg->installed);

		if (strcmp(fnn->newhash, EMPTYHASHFLAG) == 0) {
			if (fnn->oldhash == NULL)
				continue;
			else
				fnn->newhash = fnn->oldhash;
		}

		memset(&checks, 0, sizeof(checks));

		md5hash(pkg, hash, fnn->name);
		if (strcmp(hash, fnn->newhash) != 0) {
			checks.md5sum = VERIFY_FAIL;
			failures++;
		}

		if (failures)
			verify_output(fnn, &checks);
	}
}

int
verify(const char *const *argv)
{
	struct pkginfo *pkg;

	modstatdb_open(msdbrw_readonly);
	ensure_diversions();

	if (!*argv) {
		struct pkgiterator *it;

		it = pkg_db_iter_new();
		while ((pkg = pkg_db_iter_next_pkg(it)))
			verify_package(pkg);
		pkg_db_iter_free(it);
	} else {
		const char *thisarg;

		while ((thisarg = *argv++)) {
			struct dpkg_error err;

			pkg = pkg_spec_parse_pkg(thisarg, &err);
			if (pkg == NULL)
				badusage(_("--%s needs a valid package name but '%.250s' is not: %s"),
				         cipaction->olong, thisarg, err.str);

			verify_package(pkg);
		}
	}

	modstatdb_shutdown();

	m_output(stdout, _("<standard output>"));

	return 0;
}
