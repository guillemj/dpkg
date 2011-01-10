/*
 * dpkg - main program for package management
 * configure.c - configure packages
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 1999, 2002 Wichert Akkerman <wichert@deephackmode.org>
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
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/termios.h>

#include <assert.h>
#include <errno.h>
#include <ctype.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/buffer.h>
#include <dpkg/file.h>
#include <dpkg/subproc.h>
#include <dpkg/command.h>
#include <dpkg/triglib.h>

#include "filesdb.h"
#include "main.h"

static int conffoptcells[2][2] = {
	/* Distro !edited. */	/* Distro edited. */
	{ cfo_keep,		cfo_install },		/* User !edited. */
	{ cfo_keep,		cfo_prompt_keep },	/* User edited. */
};

static void md5hash(struct pkginfo *pkg, char *hashbuf, const char *fn);
static void showdiff(const char *old, const char *new);
static enum conffopt promptconfaction(struct pkginfo *pkg, const char *cfgfile,
                                      const char *realold, const char *realnew,
                                      int useredited, int distedited,
                                      enum conffopt what);

static void
deferred_configure_conffile(struct pkginfo *pkg, struct conffile *conff)
{
	struct filenamenode *usenode;
	static const char EMPTY_HASH[] = "-";
	char currenthash[MD5HASHLEN + 1], newdisthash[MD5HASHLEN + 1];
	int useredited, distedited;
	enum conffopt what;
	struct stat stab;
	struct varbuf cdr = VARBUF_INIT, cdr2 = VARBUF_INIT;
	char *cdr2rest;
	int r;

	usenode = namenodetouse(findnamenode(conff->name, fnn_nocopy), pkg);

	r = conffderef(pkg, &cdr, usenode->name);
	if (r == -1) {
		conff->hash = EMPTY_HASH;
		return;
	}
	md5hash(pkg, currenthash, cdr.buf);

	varbuf_reset(&cdr2);
	varbuf_add_str(&cdr2, cdr.buf);
	varbuf_add_char(&cdr2, '\0');
	/* XXX: Make sure there's enough room for extensions. */
	varbuf_grow(&cdr2, 50);
	cdr2rest = cdr2.buf + strlen(cdr.buf);
	/* From now on we can just strcpy(cdr2rest, extension); */

	strcpy(cdr2rest, DPKGNEWEXT);
	/* If the .dpkg-new file is no longer there, ignore this one. */
	if (lstat(cdr2.buf, &stab)) {
		if (errno == ENOENT)
			return;
		ohshite(_("unable to stat new distributed conffile '%.250s'"),
		        cdr2.buf);
	}
	md5hash(pkg, newdisthash, cdr2.buf);

	/* Copy the permissions from the installed version to the new
	 * distributed version. */
	if (!stat(cdr.buf, &stab))
		file_copy_perms(cdr.buf, cdr2.buf);
	else if (errno != ENOENT)
		ohshite(_("unable to stat current installed conffile `%.250s'"),
		        cdr.buf);

	/* Select what to do. */
	if (!strcmp(currenthash, newdisthash)) {
		/* They're both the same so there's no point asking silly
		 * questions. */
		useredited = -1;
		distedited = -1;
		what = cfo_identical;
	} else if (!strcmp(currenthash, NONEXISTENTFLAG) && fc_conff_miss) {
		fprintf(stderr,
		        _("\n"
		          "Configuration file `%s', does not exist on system.\n"
		          "Installing new config file as you requested.\n"),
		        usenode->name);
		what = cfo_newconff;
		useredited = -1;
		distedited = -1;
	} else if (!strcmp(conff->hash, NEWCONFFILEFLAG)) {
		if (!strcmp(currenthash, NONEXISTENTFLAG)) {
			what = cfo_newconff;
			useredited = -1;
			distedited = -1;
		} else {
			useredited = 1;
			distedited = 1;
			what = conffoptcells[useredited][distedited] |
			       cfof_isnew;
		}
	} else {
		useredited = strcmp(conff->hash, currenthash) != 0;
		distedited = strcmp(conff->hash, newdisthash) != 0;

		if (fc_conff_ask && useredited)
			what = cfo_prompt_keep;
		else
			what = conffoptcells[useredited][distedited];

		if (!strcmp(currenthash, NONEXISTENTFLAG))
			what |= cfof_userrmd;
	}

	debug(dbg_conff,
	      "deferred_configure '%s' (= '%s') useredited=%d distedited=%d what=%o",
	      usenode->name, cdr.buf, useredited, distedited, what);

	what = promptconfaction(pkg, usenode->name, cdr.buf, cdr2.buf,
	                        useredited, distedited, what);

	switch (what & ~(cfof_isnew | cfof_userrmd)) {
	case cfo_keep | cfof_backup:
		strcpy(cdr2rest, DPKGOLDEXT);
		if (unlink(cdr2.buf) && errno != ENOENT)
			warning(_("%s: failed to remove old backup '%.250s': %s"),
			        pkg->name, cdr2.buf, strerror(errno));
		cdr.used--;
		varbuf_add_str(&cdr, DPKGDISTEXT);
		varbuf_add_char(&cdr, '\0');
		strcpy(cdr2rest, DPKGNEWEXT);
		trig_file_activate(usenode, pkg);
		if (rename(cdr2.buf, cdr.buf))
			warning(_("%s: failed to rename '%.250s' to '%.250s': %s"),
			        pkg->name, cdr2.buf, cdr.buf, strerror(errno));
		break;
	case cfo_keep:
		strcpy(cdr2rest, DPKGNEWEXT);
		if (unlink(cdr2.buf))
			warning(_("%s: failed to remove '%.250s': %s"),
			        pkg->name, cdr2.buf, strerror(errno));
		break;
	case cfo_install | cfof_backup:
		strcpy(cdr2rest, DPKGDISTEXT);
		if (unlink(cdr2.buf) && errno != ENOENT)
			warning(_("%s: failed to remove old distributed version '%.250s': %s"),
			        pkg->name, cdr2.buf, strerror(errno));
		strcpy(cdr2rest, DPKGOLDEXT);
		if (unlink(cdr2.buf) && errno != ENOENT)
			warning(_("%s: failed to remove '%.250s' (before overwrite): %s"),
			        pkg->name, cdr2.buf, strerror(errno));
		if (!(what & cfof_userrmd))
			if (link(cdr.buf, cdr2.buf))
				warning(_("%s: failed to link '%.250s' to '%.250s': %s"),
				        pkg->name, cdr.buf, cdr2.buf, strerror(errno));
		/* Fall through. */
	case cfo_install:
		printf(_("Installing new version of config file %s ...\n"),
		       usenode->name);
	case cfo_newconff:
		strcpy(cdr2rest, DPKGNEWEXT);
		trig_file_activate(usenode, pkg);
		if (rename(cdr2.buf, cdr.buf))
			ohshite(_("unable to install `%.250s' as `%.250s'"),
			        cdr2.buf, cdr.buf);
		break;
	default:
		internerr("unknown conffopt '%d'", what);
	}

	conff->hash = nfstrsave(newdisthash);
	modstatdb_note(pkg);

	varbuf_destroy(&cdr);
	varbuf_destroy(&cdr2);
}

/**
 * Process the deferred configure package.
 *
 * The algorithm for deciding what to configure first is as follows:
 * Loop through all packages doing a ‘try 1’ until we've been round
 * and nothing has been done, then do ‘try 2’ and ‘try 3’ likewise.
 * The incrementing of ‘dependtry’ is done by process_queue().
 *
 * Try 1:
 *   Are all dependencies of this package done? If so, do it.
 *   Are any of the dependencies missing or the wrong version?
 *     If so, abort (unless --force-depends, in which case defer).
 *   Will we need to configure a package we weren't given as an
 *     argument? If so, abort ─ except if --force-configure-any,
 *     in which case we add the package to the argument list.
 *   If none of the above, defer the package.
 *
 * Try 2:
 *   Find a cycle and break it (see above).
 *   Do as for try 1.
 *
 * Try 3 (only if --force-depends-version):
 *   Same as for try 2, but don't mind version number in dependencies.
 *
 * Try 4 (only if --force-depends):
 *   Do anyway.
 *
 * @param pkg The package to act on.
 */
void
deferred_configure(struct pkginfo *pkg)
{
	struct varbuf aemsgs = VARBUF_INIT;
	struct conffile *conff;
	int ok;

	if (pkg->status == stat_notinstalled)
		ohshit(_("no package named `%s' is installed, cannot configure"),
		       pkg->name);
	if (pkg->status == stat_installed)
		ohshit(_("package %.250s is already installed and configured"),
		       pkg->name);
	if (pkg->status != stat_unpacked && pkg->status != stat_halfconfigured)
		ohshit(_("package %.250s is not ready for configuration\n"
		         " cannot configure (current status `%.250s')"),
		       pkg->name, statusinfos[pkg->status].name);

	if (dependtry > 1)
		if (findbreakcycle(pkg))
			sincenothing = 0;

	ok = dependencies_ok(pkg, NULL, &aemsgs);
	if (ok == 1) {
		varbuf_destroy(&aemsgs);
		pkg->clientdata->istobe = itb_installnew;
		add_to_queue(pkg);
		return;
	}

	trigproc_reset_cycle();

	/*
	 * At this point removal from the queue is confirmed. This
	 * represents irreversible progress wrt trigger cycles. Only
	 * packages in stat_unpacked are automatically added to the
	 * configuration queue, and during configuration and trigger
	 * processing new packages can't enter into unpacked.
	 */

	ok = breakses_ok(pkg, &aemsgs) ? ok : 0;
	if (ok == 0) {
		sincenothing = 0;
		varbuf_add_char(&aemsgs, '\0');
		fprintf(stderr,
		        _("dpkg: dependency problems prevent configuration of %s:\n%s"),
		        pkg->name, aemsgs.buf);
		varbuf_destroy(&aemsgs);
		ohshit(_("dependency problems - leaving unconfigured"));
	} else if (aemsgs.used) {
		varbuf_add_char(&aemsgs, '\0');
		fprintf(stderr,
		        _("dpkg: %s: dependency problems, but configuring anyway as you requested:\n%s"),
		        pkg->name, aemsgs.buf);
	}
	varbuf_destroy(&aemsgs);
	sincenothing = 0;

	if (pkg->eflag & eflag_reinstreq)
		forcibleerr(fc_removereinstreq,
		            _("Package is in a very bad inconsistent state - you should\n"
		              " reinstall it before attempting configuration."));

	printf(_("Setting up %s (%s) ...\n"), pkg->name,
	       versiondescribe(&pkg->installed.version, vdew_nonambig));
	log_action("configure", pkg);

	trig_activate_packageprocessing(pkg);

	if (f_noact) {
		pkg->status = stat_installed;
		pkg->clientdata->istobe = itb_normal;
		return;
	}

	if (pkg->status == stat_unpacked) {
		debug(dbg_general, "deferred_configure updating conffiles");
		/* This will not do at all the right thing with overridden
		 * conffiles or conffiles that are the ‘target’ of an override;
		 * all the references here would be to the ‘contested’
		 * filename, and in any case there'd only be one hash for both
		 * ‘versions’ of the conffile.
		 *
		 * Overriding conffiles is a silly thing to do anyway :-). */

		modstatdb_note(pkg);

		/* On entry, the ‘new’ version of each conffile has been
		 * unpacked as ‘*.dpkg-new’, and the ‘installed’ version is
		 * as-yet untouched in ‘*’. The hash of the ‘old distributed’
		 * version is in the conffiles data for the package. If
		 * ‘*.dpkg-new’ no longer exists we assume that we've
		 * already processed this one. */
		for (conff = pkg->installed.conffiles; conff; conff = conff->next)
			deferred_configure_conffile(pkg, conff);

		pkg->status = stat_halfconfigured;
	}

	assert(pkg->status == stat_halfconfigured);

	modstatdb_note(pkg);

	maintainer_script_postinst(pkg, "configure",
	                           informativeversion(&pkg->configversion) ?
	                           versiondescribe(&pkg->configversion,
	                                           vdew_nonambig) : "",
	                           NULL);

	pkg->eflag = eflag_ok;
	post_postinst_tasks(pkg, stat_installed);
}

/**
 * Dereference a file by following all possibly used symlinks.
 *
 * @param[in] pkg The package to act on.
 * @param[out] result The dereference conffile path.
 * @param[in] in The conffile path to dereference.
 *
 * @return An error code for the operation.
 * @retval 0 Everything went ok.
 * @retval -1 Otherwise.
 */
int
conffderef(struct pkginfo *pkg, struct varbuf *result, const char *in)
{
	static struct varbuf target = VARBUF_INIT;
	struct stat stab;
	int r;
	int loopprotect;

	varbuf_reset(result);
	varbuf_add_str(result, instdir);
	if (*in != '/')
		varbuf_add_char(result, '/');
	varbuf_add_str(result, in);
	varbuf_add_char(result, '\0');

	loopprotect = 0;

	for (;;) {
		debug(dbg_conffdetail, "conffderef in='%s' current working='%s'",
		      in, result->buf);
		if (lstat(result->buf, &stab)) {
			if (errno != ENOENT)
				warning(_("%s: unable to stat config file '%s'\n"
				          " (= '%s'): %s"),
				        pkg->name, in, result->buf, strerror(errno));
			debug(dbg_conffdetail, "conffderef nonexistent");
			return 0;
		} else if (S_ISREG(stab.st_mode)) {
			debug(dbg_conff, "conffderef in='%s' result='%s'",
			      in, result->buf);
			return 0;
		} else if (S_ISLNK(stab.st_mode)) {
			debug(dbg_conffdetail, "conffderef symlink loopprotect=%d",
			      loopprotect);
			if (loopprotect++ >= 25) {
				warning(_("%s: config file '%s' is a circular link\n"
				          " (= '%s')"), pkg->name, in, result->buf);
				return -1;
			}

			varbuf_reset(&target);
			varbuf_grow(&target, stab.st_size + 1);
			r = readlink(result->buf, target.buf, target.size);
			if (r < 0) {
				warning(_("%s: unable to readlink conffile '%s'\n"
				          " (= '%s'): %s"),
				        pkg->name, in, result->buf, strerror(errno));
				return -1;
			}
			assert(r == stab.st_size); /* XXX: debug */
			varbuf_trunc(&target, r);
			varbuf_add_char(&target, '\0');

			debug(dbg_conffdetail,
			      "conffderef readlink gave %d, '%s'",
			      r, target.buf);

			if (target.buf[0] == '/') {
				varbuf_reset(result);
				varbuf_add_str(result, instdir);
				debug(dbg_conffdetail,
				      "conffderef readlink absolute");
			} else {
				for (r = result->used - 2; r > 0 && result->buf[r] != '/'; r--)
					;
				if (r < 0) {
					warning(_("%s: conffile '%.250s' resolves to degenerate filename\n"
					          " ('%s' is a symlink to '%s')"),
					        pkg->name, in, result->buf,
					        target.buf);
					return -1;
				}
				if (result->buf[r] == '/')
					r++;
				varbuf_trunc(result, r);
				debug(dbg_conffdetail,
				      "conffderef readlink relative to '%.*s'",
				      (int)result->used, result->buf);
			}
			varbuf_add_buf(result, target.buf, target.used);
			varbuf_add_char(result, '\0');
		} else {
			warning(_("%s: conffile '%.250s' is not a plain file or symlink (= '%s')"),
			        pkg->name, in, result->buf);
			return -1;
		}
	}
}

/**
 * Generate a file contents MD5 hash.
 *
 * The caller is responsible for providing a buffer for the hash result
 * at least MD5HASHLEN + 1 characters long.
 *
 * @param[in] pkg The package to act on.
 * @param[out] hashbuf The buffer to store the generated hash.
 * @param[in] fn The filename.
 */
static void
md5hash(struct pkginfo *pkg, char *hashbuf, const char *fn)
{
	static int fd;

	fd = open(fn, O_RDONLY);

	if (fd >= 0) {
		push_cleanup(cu_closefd, ehflag_bombout, NULL, 0, 1, &fd);
		fd_md5(fd, hashbuf, -1, _("md5hash"));
		pop_cleanup(ehflag_normaltidy); /* fd = open(cdr.buf) */
		close(fd);
	} else if (errno == ENOENT) {
		strcpy(hashbuf, NONEXISTENTFLAG);
	} else {
		warning(_("%s: unable to open conffile %s for hash: %s"),
		        pkg->name, fn, strerror(errno));
		strcpy(hashbuf, "-");
	}
}

/**
 * Show a diff between two files.
 *
 * @param old The path to the old file.
 * @param new The path to the new file.
 */
static void
showdiff(const char *old, const char *new)
{
	pid_t pid;

	pid = subproc_fork();
	if (!pid) {
		/* Child process. */
		const char *pager;
		char cmdbuf[1024];

		pager = getenv(PAGERENV);
		if (!pager || !*pager)
			pager = DEFAULTPAGER;

		sprintf(cmdbuf, DIFF " -Nu %.250s %.250s | %.250s",
		        old, new, pager);

		command_shell(cmdbuf, _("conffile difference visualizer"));
	}

	/* Parent process. */
	subproc_wait(pid, _("conffile difference visualizer"));
}

/**
 * Spawn a new shell.
 *
 * Create a subprocess and execute a shell to allow the user to manually
 * solve the conffile conflict.
 *
 * @param confold The path to the old conffile.
 * @param confnew The path to the new conffile.
 */
static void
spawn_shell(const char *confold, const char *confnew)
{
	pid_t pid;

	fputs(_("Type `exit' when you're done.\n"), stderr);

	pid = subproc_fork();
	if (!pid) {
		/* Set useful variables for the user. */
		setenv("DPKG_SHELL_REASON", "conffile-prompt", 1);
		setenv("DPKG_CONFFILE_OLD", confold, 1);
		setenv("DPKG_CONFFILE_NEW", confnew, 1);

		command_shell(NULL, _("conffile shell"));
	}

	/* Parent process. */
	subproc_wait(pid, _("conffile shell"));
}

/**
 * Prompt the user for how to resolve a conffile conflict.
 *
 * When encountering a conffile conflict during configuration, the user will
 * normally be presented with a textual menu of possible actions. This
 * behavior is modified via various --force flags and perhaps on whether
 * or not a terminal is available to do the prompting.
 *
 * @param pkg The package owning the conffile.
 * @param cfgfile The path to the old conffile.
 * @param realold The path to the old conffile, dereferenced in case of a
 *        symlink, otherwise equal to cfgfile.
 * @param realnew The path to the new conffile, dereferenced in case of a
 *        symlink).
 * @param useredited A flag to indicate whether the file has been edited
 *        locally. Set to nonzero to indicate that the file has been modified.
 * @param distedited A flag to indicate whether the file has been updated
 *        between package versions. Set to nonzero to indicate that the file
 *        has been updated.
 * @param what Hints on what action should be taken by defualt.
 *
 * @return The action which should be taken based on user input and/or the
 *         default actions as configured by cmdline/configuration options.
 */
static enum conffopt
promptconfaction(struct pkginfo *pkg, const char *cfgfile,
                 const char *realold, const char *realnew,
                 int useredited, int distedited, enum conffopt what)
{
	const char *s;
	int c, cc;

	if (!(what & cfof_prompt))
		return what;

	statusfd_send("status: %s : %s : '%s' '%s' %i %i ",
	              cfgfile, "conffile-prompt",
	              realold, realnew, useredited, distedited);

	do {
		/* Flush the terminal's input in case the user involuntarily
		 * typed some characters. */
		tcflush(STDIN_FILENO, TCIFLUSH);
		fprintf(stderr, _("\nConfiguration file `%s'"), cfgfile);
		if (strcmp(cfgfile, realold))
			fprintf(stderr, _(" (actually `%s')"), realold);

		if (what & cfof_isnew) {
			fprintf(stderr,
			        _("\n"
			          " ==> File on system created by you or by a script.\n"
			          " ==> File also in package provided by package maintainer.\n"));
		} else {
			fprintf(stderr, !useredited ?
			        _("\n     Not modified since installation.\n") :
			        !(what & cfof_userrmd) ?
			        _("\n ==> Modified (by you or by a script) since installation.\n") :
			        _("\n ==> Deleted (by you or by a script) since installation.\n"));

			fprintf(stderr, distedited ?
			        _(" ==> Package distributor has shipped an updated version.\n") :
			        _("     Version in package is the same as at last installation.\n"));
		}

		/* No --force-confdef but a forcible situtation. */
		/* TODO: check if this condition can not be simplified to
		 *       just !fc_conff_def */
		if (!(fc_conff_def && (what & (cfof_install | cfof_keep)))) {
			if (fc_conff_new) {
				fprintf(stderr, _(" ==> Using new file as you requested.\n"));
				cc = 'y';
				break;
			} else if (fc_conff_old) {
				fprintf(stderr, _(" ==> Using current old file as you requested.\n"));
				cc = 'n';
				break;
			}
		}

		/* Force the default action (if there is one. */
		if (fc_conff_def) {
			if (what & cfof_keep) {
				fprintf(stderr, _(" ==> Keeping old config file as default.\n"));
				cc = 'n';
				break;
			} else if (what & cfof_install) {
				fprintf(stderr, _(" ==> Using new config file as default.\n"));
				cc = 'y';
				break;
			}
		}

		fprintf(stderr,
		        _("   What would you like to do about it ?  Your options are:\n"
		          "    Y or I  : install the package maintainer's version\n"
		          "    N or O  : keep your currently-installed version\n"
		          "      D     : show the differences between the versions\n"
		          "      Z     : start a shell to examine the situation\n"));

		if (what & cfof_keep)
			fprintf(stderr, _(" The default action is to keep your current version.\n"));
		else if (what & cfof_install)
			fprintf(stderr, _(" The default action is to install the new version.\n"));

		s = strrchr(cfgfile, '/');
		if (!s || !*++s)
			s = cfgfile;
		fprintf(stderr, "*** %s (Y/I/N/O/D/Z) %s ? ",
		        s,
		        (what & cfof_keep) ? _("[default=N]") :
		        (what & cfof_install) ? _("[default=Y]") :
		        _("[no default]"));

		if (ferror(stderr))
			ohshite(_("error writing to stderr, discovered before conffile prompt"));

		cc = 0;
		while ((c = getchar()) != EOF && c != '\n')
			if (!isspace(c) && !cc)
				cc = tolower(c);

		if (c == EOF) {
			if (ferror(stdin))
				ohshite(_("read error on stdin at conffile prompt"));
			ohshit(_("EOF on stdin at conffile prompt"));
		}

		if (!cc) {
			if (what & cfof_keep) {
				cc = 'n';
				break;
			} else if (what & cfof_install) {
				cc = 'y';
				break;
			}
		}

		/* FIXME: Say something if silently not install. */
		if (cc == 'd')
			showdiff(realold, realnew);

		if (cc == 'z')
			spawn_shell(realold, realnew);
	} while (!strchr("yino", cc));

	log_message("conffile %s %s", cfgfile,
	            (cc == 'i' || cc == 'y') ? "install" : "keep");

	what &= cfof_userrmd;

	switch (cc) {
	case 'i':
	case 'y':
		what |= cfof_install | cfof_backup;
		break;

	case 'n':
	case 'o':
		what |= cfof_keep | cfof_backup;
		break;

	default:
		internerr("unknown response '%d'", cc);
	}

	return what;
}
