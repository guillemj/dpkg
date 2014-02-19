/*
 * libdpkg - Debian packaging suite library routines
 * t-subproc.c - test sub-process module
 *
 * Copyright © 2011 Guillem Jover <guillem@debian.org>
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

#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>

#include <dpkg/test.h>
#include <dpkg/subproc.h>

static void
test_subproc_fork(void)
{
	pid_t pid;
	int ret;

	/* Test exit(). */
	pid = subproc_fork();
	if (pid == 0)
		exit(0);
	ret = subproc_wait_check(pid, "subproc exit pass", PROCNOERR);
	test_pass(ret == 0);

	pid = subproc_fork();
	if (pid == 0)
		exit(128);
	ret = subproc_wait_check(pid, "subproc exit fail", PROCNOERR);
	test_pass(ret == 128);

	/* Test signals. */
	pid = subproc_fork();
	if (pid == 0)
		raise(SIGINT);
	ret = subproc_wait_check(pid, "subproc signal", PROCWARN);
	test_pass(ret == -1);

	pid = subproc_fork();
	if (pid == 0)
		raise(SIGTERM);
	ret = subproc_wait_check(pid, "subproc signal", PROCWARN);
	test_pass(ret == -1);

	pid = subproc_fork();
	if (pid == 0)
		raise(SIGPIPE);
	ret = subproc_wait_check(pid, "subproc SIGPIPE", PROCWARN | PROCPIPE);
	test_pass(ret == 0);

	pid = subproc_fork();
	if (pid == 0)
		raise(SIGPIPE);
	ret = subproc_wait_check(pid, "subproc SIGPIPE", PROCWARN);
	test_pass(ret == -1);
}

static void
test(void)
{
	int fd;

	/* XXX: Shut up stderr, we don't want the error output. */
	fd = open("/dev/null", O_RDWR);
	test_pass(fd >= 0);
	dup2(fd, 2);

	test_subproc_fork();
}
