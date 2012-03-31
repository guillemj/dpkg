/*
 * dpkg-divert - override a package's version of a file
 *
 * Copyright © 1995 Ian Jackson
 * Copyright © 2000, 2001 Wichert Akkerman
 * Copyright © 2010 Guillem Jover <guillem@debian.org>
 * Copyright © 2011 Linaro Limited
 * Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
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
#include <sys/stat.h>

#include <errno.h>
#if HAVE_LOCALE_H
#include <locale.h>
#endif
#include <fcntl.h>
#include <fnmatch.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/arch.h>
#include <dpkg/file.h>
#include <dpkg/glob.h>
#include <dpkg/buffer.h>
#include <dpkg/options.h>

#include "filesdb.h"


static const char printforhelp[] = N_(
"Use --help for help about diverting files.");

static const char *admindir;

static bool opt_pkgname_match_any = true;
static const char *opt_pkgname = NULL;
static const char *opt_divertto = NULL;

static int opt_verbose = 1;
static int opt_test = 0;
static int opt_rename = 0;


static void
printversion(const struct cmdinfo *cip, const char *value)
{
	printf(_("Debian %s version %s.\n"), dpkg_get_progname(),
	       DPKG_VERSION_ARCH);

	printf(_(
"This is free software; see the GNU General Public License version 2 or\n"
"later for copying conditions. There is NO warranty.\n"));

	m_output(stdout, _("<standard output>"));

	exit(0);
}

static void
usage(const struct cmdinfo *cip, const char *value)
{
	printf(_(
"Usage: %s [<option> ...] <command>\n"
"\n"), dpkg_get_progname());

	printf(_(
"Commands:\n"
"  [--add] <file>           add a diversion.\n"
"  --remove <file>          remove the diversion.\n"
"  --list [<glob-pattern>]  show file diversions.\n"
"  --listpackage <file>     show what package diverts the file.\n"
"  --truename <file>        return the diverted file.\n"
"\n"));

	printf(_(
"Options:\n"
"  --package <package>      name of the package whose copy of <file> will not\n"
"                             be diverted.\n"
"  --local                  all packages' versions are diverted.\n"
"  --divert <divert-to>     the name used by other packages' versions.\n"
"  --rename                 actually move the file aside (or back).\n"
"  --admindir <directory>   set the directory with the diversions file.\n"
"  --test                   don't do anything, just demonstrate.\n"
"  --quiet                  quiet operation, minimal output.\n"
"  --help                   show this help message.\n"
"  --version                show the version.\n"
"\n"));

	printf(_(
"When adding, default is --local and --divert <original>.distrib.\n"
"When removing, --package or --local and --divert must match if specified.\n"
"Package preinst/postrm scripts should always specify --package and --divert.\n"));

	m_output(stdout, _("<standard output>"));

	exit(0);
}

struct file {
	const char *name;
	enum {
		file_stat_invalid,
		file_stat_valid,
		file_stat_nofile,
	} stat_state;
	struct stat stat;
};

static void
file_init(struct file *f, const char *filename)
{
	f->name = filename;
	f->stat_state = file_stat_invalid;
}

static void
file_stat(struct file *f)
{
	int ret;

	if (f->stat_state != file_stat_invalid)
		return;

	ret = lstat(f->name, &f->stat);
	if (ret && errno != ENOENT)
		ohshite(_("cannot stat file '%s'"), f->name);

	if (ret == 0)
		f->stat_state = file_stat_valid;
	else
		f->stat_state = file_stat_nofile;
}

static void
check_writable_dir(struct file *f)
{
	char *tmpname;
	int tmpfd;

	m_asprintf(&tmpname, "%s%s", f->name, ".dpkg-divert.tmp");

	tmpfd = creat(tmpname, 0600);
	if (tmpfd < 0)
		ohshite(_("error checking '%s'"), f->name);
	close(tmpfd);
	unlink(tmpname);

	free(tmpname);
}

static bool
check_rename(struct file *src, struct file *dst)
{
	file_stat(src);

	/* If the source file is not present and we are not going to do
	 * the rename anyway there's no point in checking any further. */
	if (src->stat_state == file_stat_nofile)
		return false;

	file_stat(dst);

	/*
	 * Unfortunately we have to check for write access in both places,
	 * just having +w is not enough, since people do mount things RO,
	 * and we need to fail before we start mucking around with things.
	 * So we open a file with the same name as the diversions but with
	 * an extension that (hopefully) wont overwrite anything. If it
	 * succeeds, we assume a writable filesystem.
	 */

	check_writable_dir(src);
	check_writable_dir(dst);

	if (src->stat_state == file_stat_valid &&
	    dst->stat_state == file_stat_valid &&
	    !(src->stat.st_dev == dst->stat.st_dev &&
	      src->stat.st_ino == dst->stat.st_ino))
		ohshit(_("rename involves overwriting `%s' with\n"
		         "  different file `%s', not allowed"),
		        dst->name, src->name);

	return true;
}

static void
file_copy(const char *src, const char *realdst)
{
	char *dst;
	int srcfd, dstfd;

	srcfd = open(src, O_RDONLY);
	if (srcfd < 0)
		ohshite(_("unable to open file '%s'"), src);

	m_asprintf(&dst, "%s%s", realdst, ".dpkg-divert.tmp");
	dstfd = creat(dst, 0600);
	if (dstfd < 0)
		ohshite(_("unable to create file '%s'"), dst);

	/* FIXME: leaves a dangling destination file on error. */

	fd_fd_copy(srcfd, dstfd, -1, _("file copy"));

	close(srcfd);

	if (fsync(dstfd))
		ohshite(_("unable to sync file '%s'"), dst);
	if (close(dstfd))
		ohshite(_("unable to close file '%s'"), dst);

	file_copy_perms(src, dst);

	if (rename(dst, realdst) != 0)
		ohshite(_("cannot rename '%s' to '%s'"), dst, realdst);

	free(dst);
}

static void
file_rename(struct file *src, struct file *dst)
{
	if (src->stat_state == file_stat_nofile)
		return;

	if (dst->stat_state == file_stat_valid) {
		if (unlink(src->name))
			ohshite(_("rename: remove duplicate old link '%s'"),
			        src->name);
	} else {
		if (rename(src->name, dst->name) == 0)
			return;

		/* If a rename didn't work try moving the file instead. */
		file_copy(src->name, dst->name);

		if (unlink(src->name))
			ohshite(_("unable to remove copied source file '%s'"),
			        src->name);
	}
}

static void
diversion_check_filename(const char *filename)
{
	if (filename[0] != '/')
		badusage(_("filename \"%s\" is not absolute"), filename);
	if (strchr(filename, '\n') != NULL)
		badusage(_("file may not contain newlines"));
}

static const char *
diversion_pkg_name(struct diversion *d)
{
	if (d->pkgset == NULL)
		return ":";
	else
		return d->pkgset->name;
}

static const char *
varbuf_diversion(struct varbuf *str, const char *pkgname,
                 const char *filename, const char *divertto)
{
	varbuf_reset(str);

	if (pkgname == NULL) {
		if (divertto == NULL)
			varbuf_printf(str, _("local diversion of %s"), filename);
		else
			varbuf_printf(str, _("local diversion of %s to %s"),
			              filename, divertto);
	} else {
		if (divertto == NULL)
			varbuf_printf(str, _("diversion of %s by %s"),
			              filename, pkgname);
		else
			varbuf_printf(str, _("diversion of %s to %s by %s"),
			              filename, divertto, pkgname);
	}

	return str->buf;
}

static const char *
diversion_current(const char *filename)
{
	static struct varbuf str = VARBUF_INIT;

	if (opt_pkgname_match_any) {
		varbuf_reset(&str);

		if (opt_divertto == NULL)
			varbuf_printf(&str, _("any diversion of %s"), filename);
		else
			varbuf_printf(&str, _("any diversion of %s to %s"),
			              filename, opt_divertto);
	} else {
		return varbuf_diversion(&str, opt_pkgname, filename, opt_divertto);
	}

	return str.buf;
}

static const char *
diversion_describe(struct diversion *d)
{
	static struct varbuf str = VARBUF_INIT;
	const char *pkgname;
	const char *name_from, *name_to;

	if (d->camefrom) {
		name_from = d->camefrom->name;
		name_to = d->camefrom->divert->useinstead->name;
	} else {
		name_from = d->useinstead->divert->camefrom->name;
		name_to = d->useinstead->name;
	}

	if (d->pkgset == NULL)
		pkgname = NULL;
	else
		pkgname = d->pkgset->name;

	return varbuf_diversion(&str, pkgname, name_from, name_to);
}

static void
divertdb_write(void)
{
	char *dbname;
	struct atomic_file *file;
	struct fileiterator *iter;
	struct filenamenode *namenode;

	dbname = dpkg_db_get_path(DIVERSIONSFILE);

	file = atomic_file_new(dbname, aff_backup);
	atomic_file_open(file);

	iter = files_db_iter_new();
	while ((namenode = files_db_iter_next(iter))) {
		struct diversion *d = namenode->divert;

		if (d == NULL || d->useinstead == NULL)
			continue;

		fprintf(file->fp, "%s\n%s\n%s\n",
		        d->useinstead->divert->camefrom->name,
		        d->useinstead->name,
		        diversion_pkg_name(d));
	}
	files_db_iter_free(iter);

	atomic_file_sync(file);
	atomic_file_close(file);
	atomic_file_commit(file);
	atomic_file_free(file);

	free(dbname);
}

static int
diversion_add(const char *const *argv)
{
	const char *filename = argv[0];
	struct file file_from, file_to;
	struct diversion *contest, *altname;
	struct filenamenode *fnn_from, *fnn_to;
	struct pkgset *pkgset;

	opt_pkgname_match_any = false;

	/* Handle filename. */
	if (!filename || argv[1])
		badusage(_("--%s needs a single argument"), cipaction->olong);

	diversion_check_filename(filename);

	file_init(&file_from, filename);
	file_stat(&file_from);

	if (file_from.stat_state == file_stat_valid &&
	    S_ISDIR(file_from.stat.st_mode))
		badusage(_("Cannot divert directories"));

	fnn_from = findnamenode(filename, 0);

	/* Handle divertto. */
	if (opt_divertto == NULL) {
		char *str;

		m_asprintf(&str, "%s.distrib", filename);
		opt_divertto = str;
	}

	if (strcmp(filename, opt_divertto) == 0)
		badusage(_("cannot divert file '%s' to itself"), filename);

	file_init(&file_to, opt_divertto);

	fnn_to = findnamenode(opt_divertto, 0);

	/* Handle package name. */
	if (opt_pkgname == NULL)
		pkgset = NULL;
	else
		pkgset = pkg_db_find_set(opt_pkgname);

	/* Check we are not stomping over an existing diversion. */
	if (fnn_from->divert || fnn_to->divert) {
		if (fnn_to->divert && fnn_to->divert->camefrom &&
		    strcmp(fnn_to->divert->camefrom->name, filename) == 0 &&
		    fnn_from->divert && fnn_from->divert->useinstead &&
		    strcmp(fnn_from->divert->useinstead->name, opt_divertto) == 0 &&
		    fnn_from->divert->pkgset == pkgset) {
			if (opt_verbose > 0)
				printf(_("Leaving '%s'\n"),
				       diversion_describe(fnn_from->divert));
			exit(0);
		}

		ohshit(_("`%s' clashes with `%s'"),
		       diversion_current(filename),
		       fnn_from->divert ?
		       diversion_describe(fnn_from->divert) :
		       diversion_describe(fnn_to->divert));
	}

	/* Create new diversion. */
	contest = nfmalloc(sizeof(*contest));
	altname = nfmalloc(sizeof(*altname));

	altname->camefrom = fnn_from;
	altname->camefrom->divert = contest;
	altname->useinstead = NULL;
	altname->pkgset = pkgset;

	contest->useinstead = fnn_to;
	contest->useinstead->divert = altname;
	contest->camefrom = NULL;
	contest->pkgset = pkgset;

	/* Update database and file system if needed. */
	if (opt_verbose > 0)
		printf(_("Adding '%s'\n"), diversion_describe(contest));
	if (opt_rename)
		opt_rename = check_rename(&file_from, &file_to);
	if (!opt_test) {
		divertdb_write();
		if (opt_rename)
			file_rename(&file_from, &file_to);
	}

	return 0;
}

static bool
diversion_is_shared(struct pkgset *set, struct filenamenode *namenode)
{
	const char *archname;
	struct pkginfo *pkg;
	struct dpkg_arch *arch;
	struct filepackages_iterator *iter;
	bool shared = false;

	if (set == NULL)
		return false;

	archname = getenv("DPKG_MAINTSCRIPT_ARCH");
	arch = dpkg_arch_find(archname);
	if (arch->type == arch_none || arch->type == arch_empty)
		return false;

	for (pkg = &set->pkg; pkg; pkg = pkg->arch_next)
		ensure_packagefiles_available(pkg);

	iter = filepackages_iter_new(namenode);
	while ((pkg = filepackages_iter_next(iter))) {
		if (pkg->set == set && pkg->installed.arch != arch) {
			shared = true;
			break;
		}
	}
	filepackages_iter_free(iter);

	return shared;
}

static int
diversion_remove(const char *const *argv)
{
	const char *filename = argv[0];
	struct filenamenode *namenode;
	struct diversion *contest, *altname;
	struct file file_from, file_to;
	struct pkgset *pkgset;

	if (!filename || argv[1])
		badusage(_("--%s needs a single argument"), cipaction->olong);

	diversion_check_filename(filename);

	namenode = findnamenode(filename, fnn_nonew);

	if (namenode == NULL || namenode->divert == NULL ||
	    namenode->divert->useinstead == NULL) {
		if (opt_verbose > 0)
			printf(_("No diversion '%s', none removed.\n"),
			       diversion_current(filename));
		return 0;
	}

	if (opt_pkgname == NULL)
		pkgset = NULL;
	else
		pkgset = pkg_db_find_set(opt_pkgname);

	contest = namenode->divert;
	altname = contest->useinstead->divert;

	if (opt_divertto != NULL &&
	    strcmp(opt_divertto, contest->useinstead->name) != 0)
		ohshit(_("mismatch on divert-to\n"
		         "  when removing `%s'\n"
		         "  found `%s'"),
		       diversion_current(filename),
		       diversion_describe(contest));

	if (!opt_pkgname_match_any && pkgset != contest->pkgset)
		ohshit(_("mismatch on package\n"
		         "  when removing `%s'\n"
		         "  found `%s'"),
		       diversion_current(filename),
		       diversion_describe(contest));

	/* Ignore removal request if the diverted file is still owned
	 * by another package in the same set. */
	if (diversion_is_shared(pkgset, namenode)) {
		if (opt_verbose > 0)
			printf(_("Ignoring request to remove shared diversion '%s'.\n"),
			       diversion_describe(contest));
		exit(0);
	}

	if (opt_verbose > 0)
		printf(_("Removing '%s'\n"), diversion_describe(contest));

	file_init(&file_from, altname->camefrom->name);
	file_init(&file_to, contest->useinstead->name);

	/* Remove entries from database. */
	contest->useinstead->divert = NULL;
	altname->camefrom->divert = NULL;

	if (opt_rename)
		opt_rename = check_rename(&file_to, &file_from);
	if (opt_rename && !opt_test)
		file_rename(&file_to, &file_from);

	if (!opt_test)
		divertdb_write();

	return 0;
}

static int
diversion_list(const char *const *argv)
{
	struct fileiterator *iter;
	struct filenamenode *namenode;
	struct glob_node *glob_list = NULL;
	const char *pattern;

	while ((pattern = *argv++))
		glob_list_prepend(&glob_list, m_strdup(pattern));

	if (glob_list == NULL)
		glob_list_prepend(&glob_list, m_strdup("*"));

	iter = files_db_iter_new();
	while ((namenode = files_db_iter_next(iter))) {
		struct glob_node *g;
		struct diversion *contest = namenode->divert;
		struct diversion *altname;
		const char *pkgname;

		if (contest->useinstead == NULL)
			continue;

		altname = contest->useinstead->divert;

		pkgname = diversion_pkg_name(contest);

		for (g = glob_list; g; g = g->next) {
			if (fnmatch(g->pattern, pkgname, 0) == 0 ||
			    fnmatch(g->pattern, contest->useinstead->name, 0) == 0 ||
			    fnmatch(g->pattern, altname->camefrom->name, 0) == 0) {
				printf("%s\n", diversion_describe(contest));
				break;
			}
		}
	}
	files_db_iter_free(iter);

	glob_list_free(glob_list);

	return 0;
}

static int
diversion_truename(const char *const *argv)
{
	const char *filename = argv[0];
	struct filenamenode *namenode;

	if (!filename || argv[1])
		badusage(_("--%s needs a single argument"), cipaction->olong);

	diversion_check_filename(filename);

	namenode = findnamenode(filename, fnn_nonew);

	/* Print the given name if file is not diverted. */
	if (namenode && namenode->divert->useinstead)
		printf("%s\n", namenode->divert->useinstead->name);
	else
		printf("%s\n", filename);

	return 0;
}

static int
diversion_listpackage(const char *const *argv)
{
	const char *filename = argv[0];
	struct filenamenode *namenode;

	if (!filename || argv[1])
		badusage(_("--%s needs a single argument"), cipaction->olong);

	diversion_check_filename(filename);

	namenode = findnamenode(filename, fnn_nonew);

	/* Print nothing if file is not diverted. */
	if (namenode == NULL)
		return 0;

	if (namenode->divert->pkgset == NULL)
		/* Indicate package is local using something not in package
		 * namespace. */
		printf("LOCAL\n");
	else
		printf("%s\n", namenode->divert->pkgset->name);

	return 0;
}

static void
setpackage(const struct cmdinfo *cip, const char *value)
{
	opt_pkgname_match_any = false;

	/* If value is NULL we are being called from --local. */
	opt_pkgname = value;

	if (opt_pkgname && strchr(opt_pkgname, '\n') != NULL)
		badusage(_("package may not contain newlines"));
}

static void
setdivertto(const struct cmdinfo *cip, const char *value)
{
	opt_divertto = value;

	if (opt_divertto[0] != '/')
		badusage(_("filename \"%s\" is not absolute"), opt_divertto);
	if (strchr(opt_divertto, '\n') != NULL)
		badusage(_("divert-to may not contain newlines"));
}

static const struct cmdinfo cmdinfo_add =
	ACTION("add",         0, 0, diversion_add);

static const struct cmdinfo cmdinfos[] = {
	ACTION("add",         0, 0, diversion_add),
	ACTION("remove",      0, 0, diversion_remove),
	ACTION("list",        0, 0, diversion_list),
	ACTION("listpackage", 0, 0, diversion_listpackage),
	ACTION("truename",    0, 0, diversion_truename),

	{ "admindir",   0,   1,  NULL,         &admindir, NULL          },
	{ "divert",     0,   1,  NULL,         NULL,      setdivertto   },
	{ "package",    0,   1,  NULL,         NULL,      setpackage    },
	{ "local",      0,   0,  NULL,         NULL,      setpackage    },
	{ "quiet",      0,   0,  &opt_verbose, NULL,      NULL, 0       },
	{ "rename",     0,   0,  &opt_rename,  NULL,      NULL, 1       },
	{ "test",       0,   0,  &opt_test,    NULL,      NULL, 1       },
	{ "help",       0,   0,  NULL,         NULL,      usage         },
	{ "version",    0,   0,  NULL,         NULL,      printversion  },
	{  NULL,        0                                               }
};

int
main(int argc, const char * const *argv)
{
	const char *env_pkgname;
	int ret;

	setlocale(LC_ALL, "");
	bindtextdomain(PACKAGE, LOCALEDIR);
	textdomain(PACKAGE);

	dpkg_set_progname("dpkg-divert");
	standard_startup();
	myopt(&argv, cmdinfos, printforhelp);

	admindir = dpkg_db_set_dir(admindir);

	env_pkgname = getenv("DPKG_MAINTSCRIPT_PACKAGE");
	if (opt_pkgname_match_any && env_pkgname)
		setpackage(NULL, env_pkgname);

	if (!cipaction)
		setaction(&cmdinfo_add, NULL);

	setvbuf(stdout, NULL, _IONBF, 0);

	modstatdb_open(msdbrw_readonly);
	filesdbinit();
	ensure_diversions();

	ret = cipaction->action(argv);

	modstatdb_shutdown();
	standard_shutdown();

	return ret;
}
