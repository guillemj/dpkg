/*
 * dpkg - main program for package management
 * script.c - maintainer script routines
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2007-2013 Guillem Jover <guillem@debian.org>
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

#include <assert.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

#ifdef WITH_SELINUX
#include <selinux/selinux.h>
#include <selinux/flask.h>
#include <selinux/context.h>
#endif

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg.h>
#include <dpkg/subproc.h>
#include <dpkg/command.h>
#include <dpkg/triglib.h>

#include "filesdb.h"
#include "infodb.h"
#include "main.h"

void
post_postinst_tasks(struct pkginfo *pkg, enum pkgstatus new_status)
{
	if (new_status < stat_triggersawaited)
		pkg_set_status(pkg, new_status);
	else if (pkg->trigaw.head)
		pkg_set_status(pkg, stat_triggersawaited);
	else if (pkg->trigpend_head)
		pkg_set_status(pkg, stat_triggerspending);
	else
		pkg_set_status(pkg, stat_installed);
	modstatdb_note(pkg);

	post_postinst_tasks_core(pkg);
}

void
post_postinst_tasks_core(struct pkginfo *pkg)
{
	debug(dbg_triggersdetail, "post_postinst_tasks_core - trig_incorporate");
	trig_incorporate(modstatdb_get_status());
}

static void
post_script_tasks(void)
{
	ensure_diversions();

	debug(dbg_triggersdetail,
	      "post_script_tasks - ensure_diversions; trig_incorporate");
	trig_incorporate(modstatdb_get_status());
}

static void
cu_post_script_tasks(int argc, void **argv)
{
	post_script_tasks();
}

static void
setexecute(const char *path, struct stat *stab)
{
	if ((stab->st_mode & 0555) == 0555)
		return;
	if (!chmod(path, 0755))
		return;
	ohshite(_("unable to set execute permissions on `%.250s'"), path);
}

/**
 * Returns the path to the script inside the chroot.
 */
static const char *
maintscript_pre_exec(struct command *cmd)
{
	const char *admindir = dpkg_db_get_dir();
	size_t instdirl = strlen(instdir);

	if (*instdir) {
		if (strncmp(admindir, instdir, instdirl) != 0)
			ohshit(_("admindir must be inside instdir for dpkg to work properly"));
		if (setenv("DPKG_ADMINDIR", admindir + instdirl, 1) < 0)
			ohshite(_("unable to setenv for subprocesses"));

		if (chroot(instdir))
			ohshite(_("failed to chroot to `%.250s'"), instdir);
	}
	/* Switch to a known good directory to give the maintainer script
	 * a saner environment, also needed after the chroot(). */
	if (chdir("/"))
		ohshite(_("failed to chdir to `%.255s'"), "/");
	if (debug_has_flag(dbg_scripts)) {
		struct varbuf args = VARBUF_INIT;
		const char **argv = cmd->argv;

		while (*++argv) {
			varbuf_add_char(&args, ' ');
			varbuf_add_str(&args, *argv);
		}
		varbuf_end_str(&args);
		debug(dbg_scripts, "fork/exec %s (%s )", cmd->filename,
		      args.buf);
		varbuf_destroy(&args);
	}
	if (!instdirl)
		return cmd->filename;

	assert(strlen(cmd->filename) >= instdirl);
	return cmd->filename + instdirl;
}

/**
 * Set a new security execution context for the maintainer script.
 *
 * Try to create a new execution context based on the current one and the
 * specific maintainer script filename. If it's the same as the current
 * one, use the given fallback.
 */
static int
maintscript_set_exec_context(struct command *cmd, const char *fallback)
{
	int rc = 0;
#ifdef WITH_SELINUX
	security_context_t curcon = NULL, newcon = NULL, filecon = NULL;
	context_t tmpcon = NULL;

	if (is_selinux_enabled() < 1)
		return 0;

	rc = getcon(&curcon);
	if (rc < 0)
		goto out;

	rc = getfilecon(cmd->filename, &filecon);
	if (rc < 0)
		goto out;

	rc = security_compute_create(curcon, filecon, SECCLASS_PROCESS, &newcon);
	if (rc < 0)
		goto out;

	if (strcmp(curcon, newcon) == 0) {
		/* No default transition, use fallback for now. */
		rc = -1;
		tmpcon = context_new(curcon);
		if (tmpcon == NULL)
			goto out;
		if (context_type_set(tmpcon, fallback))
			goto out;
		freecon(newcon);
		newcon = strdup(context_str(tmpcon));
		if (newcon == NULL)
			goto out;
	}

	rc = setexeccon(newcon);

out:
	if (rc < 0 && security_getenforce() == 0)
		rc = 0;

	context_free(tmpcon);
	freecon(newcon);
	freecon(curcon);
	freecon(filecon);
#endif

	return rc < 0 ? rc : 0;
}

static int
maintscript_exec(struct pkginfo *pkg, struct pkgbin *pkgbin,
                 struct command *cmd, struct stat *stab, int warn)
{
	pid_t pid;
	int r;

	setexecute(cmd->filename, stab);

	push_cleanup(cu_post_script_tasks, ehflag_bombout, NULL, 0, 0);

	pid = subproc_fork();
	if (pid == 0) {
		char *pkg_count;

		m_asprintf(&pkg_count, "%d", pkgset_installed_instances(pkg->set));

		if (setenv("DPKG_MAINTSCRIPT_PACKAGE", pkg->set->name, 1) ||
		    setenv("DPKG_MAINTSCRIPT_PACKAGE_REFCOUNT", pkg_count, 1) ||
		    setenv("DPKG_MAINTSCRIPT_ARCH", pkgbin->arch->name, 1) ||
		    setenv("DPKG_MAINTSCRIPT_NAME", cmd->argv[0], 1) ||
		    setenv("DPKG_RUNNING_VERSION", PACKAGE_VERSION, 1))
			ohshite(_("unable to setenv for maintainer script"));

		cmd->filename = cmd->argv[0] = maintscript_pre_exec(cmd);

		if (maintscript_set_exec_context(cmd, "dpkg_script_t") < 0)
			ohshite(_("cannot set security execution context for "
			          "maintainer script"));

		command_exec(cmd);
	}
	subproc_signals_setup(cmd->name); /* This does a push_cleanup(). */
	r = subproc_wait_check(pid, cmd->name, warn);
	pop_cleanup(ehflag_normaltidy);

	pop_cleanup(ehflag_normaltidy);

	return r;
}

static int
vmaintscript_installed(struct pkginfo *pkg, const char *scriptname,
                       const char *desc, va_list args)
{
	struct command cmd;
	const char *scriptpath;
	struct stat stab;
	char buf[100];

	scriptpath = pkg_infodb_get_file(pkg, &pkg->installed, scriptname);
	sprintf(buf, _("installed %s script"), desc);

	command_init(&cmd, scriptpath, buf);
	command_add_arg(&cmd, scriptname);
	command_add_argv(&cmd, args);

	if (stat(scriptpath, &stab)) {
		command_destroy(&cmd);
		if (errno == ENOENT) {
			debug(dbg_scripts,
			      "vmaintscript_installed nonexistent %s",
			      scriptname);
			return 0;
		}
		ohshite(_("unable to stat %s `%.250s'"), buf, scriptpath);
	}
	maintscript_exec(pkg, &pkg->installed, &cmd, &stab, 0);

	command_destroy(&cmd);

	return 1;
}

/*
 * All ...'s in maintscript_* are const char *'s.
 */

int
maintscript_installed(struct pkginfo *pkg, const char *scriptname,
                      const char *desc, ...)
{
	va_list args;
	int r;

	va_start(args, desc);
	r = vmaintscript_installed(pkg, scriptname, desc, args);
	va_end(args);

	if (r)
		post_script_tasks();

	return r;
}

int
maintscript_postinst(struct pkginfo *pkg, ...)
{
	va_list args;
	int r;

	va_start(args, pkg);
	r = vmaintscript_installed(pkg, POSTINSTFILE, "post-installation", args);
	va_end(args);

	if (r)
		ensure_diversions();

	return r;
}

int
maintscript_new(struct pkginfo *pkg, const char *scriptname,
                const char *desc, const char *cidir, char *cidirrest, ...)
{
	struct command cmd;
	struct stat stab;
	va_list args;
	char buf[100];

	strcpy(cidirrest, scriptname);
	sprintf(buf, _("new %s script"), desc);

	va_start(args, cidirrest);
	command_init(&cmd, cidir, buf);
	command_add_arg(&cmd, scriptname);
	command_add_argv(&cmd, args);
	va_end(args);

	if (stat(cidir, &stab)) {
		command_destroy(&cmd);
		if (errno == ENOENT) {
			debug(dbg_scripts,
			      "maintscript_new nonexistent %s '%s'",
			      scriptname, cidir);
			return 0;
		}
		ohshite(_("unable to stat %s `%.250s'"), buf, cidir);
	}
	maintscript_exec(pkg, &pkg->available, &cmd, &stab, 0);

	command_destroy(&cmd);
	post_script_tasks();

	return 1;
}

int
maintscript_fallback(struct pkginfo *pkg,
                     const char *scriptname, const char *desc,
                     const char *cidir, char *cidirrest,
                     const char *ifok, const char *iffallback)
{
	struct command cmd;
	const char *oldscriptpath;
	struct stat stab;
	char buf[100];

	oldscriptpath = pkg_infodb_get_file(pkg, &pkg->installed, scriptname);
	sprintf(buf, _("old %s script"), desc);

	command_init(&cmd, oldscriptpath, buf);
	command_add_args(&cmd, scriptname, ifok,
	                 versiondescribe(&pkg->available.version, vdew_nonambig),
	                 NULL);

	if (stat(oldscriptpath, &stab)) {
		if (errno == ENOENT) {
			debug(dbg_scripts,
			      "maintscript_fallback nonexistent %s '%s'",
			      scriptname, oldscriptpath);
			command_destroy(&cmd);
			return 0;
		}
		warning(_("unable to stat %s '%.250s': %s"),
		        cmd.name, oldscriptpath, strerror(errno));
	} else {
		if (!maintscript_exec(pkg, &pkg->installed, &cmd, &stab, PROCWARN)) {
			command_destroy(&cmd);
			post_script_tasks();
			return 1;
		}
	}
	notice(_("trying script from the new package instead ..."));

	strcpy(cidirrest, scriptname);
	sprintf(buf, _("new %s script"), desc);

	command_destroy(&cmd);
	command_init(&cmd, cidir, buf);
	command_add_args(&cmd, scriptname, iffallback,
	                 versiondescribe(&pkg->installed.version, vdew_nonambig),
	                 NULL);

	if (stat(cidir, &stab)) {
		command_destroy(&cmd);
		if (errno == ENOENT)
			ohshit(_("there is no script in the new version of the package - giving up"));
		else
			ohshite(_("unable to stat %s `%.250s'"), buf, cidir);
	}

	maintscript_exec(pkg, &pkg->available, &cmd, &stab, 0);
	notice(_("... it looks like that went OK"));

	command_destroy(&cmd);
	post_script_tasks();

	return 1;
}
