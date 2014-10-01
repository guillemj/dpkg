/*
 * libdpkg - Debian packaging suite library routines
 * file.c - file handling functions
 *
 * Copyright © 1994, 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008-2012 Guillem Jover <guillem@debian.org>
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
#include <sys/stat.h>

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

#include <dpkg/dpkg.h>
#include <dpkg/i18n.h>
#include <dpkg/subproc.h>
#include <dpkg/command.h>
#include <dpkg/file.h>

/**
 * Copy file ownership and permissions from one file to another.
 *
 * @param src The source filename.
 * @param dst The destination filename.
 */
void
file_copy_perms(const char *src, const char *dst)
{
	struct stat stab;

	if (stat(src, &stab) == -1) {
		if (errno == ENOENT)
			return;
		ohshite(_("unable to stat source file '%.250s'"), src);
	}

	if (chown(dst, stab.st_uid, stab.st_gid) == -1)
		ohshite(_("unable to change ownership of target file '%.250s'"),
		        dst);

	if (chmod(dst, (stab.st_mode & 07777)) == -1)
		ohshite(_("unable to set mode of target file '%.250s'"), dst);
}

static void
file_lock_setup(struct flock *fl, short type)
{
	fl->l_type = type;
	fl->l_whence = SEEK_SET;
	fl->l_start = 0;
	fl->l_len = 0;
	fl->l_pid = 0;
}

/**
 * Unlock a previously locked file.
 */
void
file_unlock(int lockfd, const char *lock_desc)
{
	struct flock fl;

	assert(lockfd >= 0);

	file_lock_setup(&fl, F_UNLCK);

	if (fcntl(lockfd, F_SETLK, &fl) == -1)
		ohshite(_("unable to unlock %s"), lock_desc);
}

static void
file_unlock_cleanup(int argc, void **argv)
{
	int lockfd = *(int *)argv[0];
	const char *lock_desc = argv[1];

	file_unlock(lockfd, lock_desc);
}

/**
 * Check if a file has a lock acquired.
 *
 * @param lockfd The file descriptor for the lock.
 * @param filename The file name associated to the file descriptor.
 */
bool
file_is_locked(int lockfd, const char *filename)
{
	struct flock fl;

	file_lock_setup(&fl, F_WRLCK);

	if (fcntl(lockfd, F_GETLK, &fl) == -1)
		ohshit(_("unable to check file '%s' lock status"), filename);

	if (fl.l_type == F_WRLCK && fl.l_pid != getpid())
		return true;
	else
		return false;
}

/**
 * Lock a file.
 *
 * @param lockfd The pointer to the lock file descriptor. It must be allocated
 *        statically as its addresses is passed to a cleanup handler.
 * @param flags The lock flags specifying what type of locking to perform.
 * @param filename The name of the file to lock.
 * @param desc The description of the file to lock.
 */
void
file_lock(int *lockfd, enum file_lock_flags flags, const char *filename,
          const char *desc)
{
	struct flock fl;
	int lock_cmd;

	setcloexec(*lockfd, filename);

	file_lock_setup(&fl, F_WRLCK);

	if (flags == FILE_LOCK_WAIT)
		lock_cmd = F_SETLKW;
	else
		lock_cmd = F_SETLK;

	if (fcntl(*lockfd, lock_cmd, &fl) == -1) {
		if (errno == EACCES || errno == EAGAIN)
			ohshit(_("%s is locked by another process"), desc);
		else
			ohshite(_("unable to lock %s"), desc);
	}

	push_cleanup(file_unlock_cleanup, ~0, NULL, 0, 2, lockfd, desc);
}

void
file_show(const char *filename)
{
	pid_t pid;

	if (filename == NULL)
		internerr("file '%s' does not exist", filename);

	pid = subproc_fork();
	if (pid == 0) {
		struct command cmd;
		const char *pager;

		pager = command_get_pager();

		command_init(&cmd, pager, _("showing file on pager"));
		command_add_arg(&cmd, pager);
		command_add_arg(&cmd, filename);
		command_exec(&cmd);
	}
	subproc_reap(pid, _("showing file on pager"), SUBPROC_NOCHECK);
}
