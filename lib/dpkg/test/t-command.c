/*
 * libdpkg - Debian packaging suite library routines
 * t-command.c - test command implementation
 *
 * Copyright © 2010-2012 Guillem Jover <guillem@debian.org>
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
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

#include <dpkg/test.h>
#include <dpkg/subproc.h>
#include <dpkg/command.h>
#include <dpkg/dpkg.h>

static void
test_command_init(void)
{
	struct command cmd;

	command_init(&cmd, "/absolute/path/to/progname", NULL);
	test_str(cmd.filename, ==, "/absolute/path/to/progname");
	test_str(cmd.name, ==, "progname");
	test_pass(cmd.argc == 0);
	test_pass(cmd.argv[0] == NULL);

	command_destroy(&cmd);
	test_pass(cmd.filename == NULL);
	test_pass(cmd.name == NULL);
	test_pass(cmd.argc == 0);
	test_pass(cmd.argv == NULL);

	command_init(&cmd, "progname", NULL);
	test_str(cmd.filename, ==, "progname");
	test_str(cmd.name, ==, "progname");
	test_pass(cmd.argc == 0);
	test_pass(cmd.argv[0] == NULL);

	command_destroy(&cmd);

	command_init(&cmd, "progname", "description");
	test_str(cmd.filename, ==, "progname");
	test_str(cmd.name, ==, "description");
	test_pass(cmd.argc == 0);
	test_pass(cmd.argv[0] == NULL);

	command_destroy(&cmd);
}

static void
test_command_grow_argv(void)
{
	struct command cmd;
	int argv_size, i;

	command_init(&cmd, "test", NULL);

	argv_size = cmd.argv_size + 4;
	for (i = 0; i < argv_size; i++)
		command_add_arg(&cmd, "arg");

	test_pass(cmd.argc == argv_size);
	test_pass(cmd.argv_size >= argv_size);
	test_str(cmd.argv[0], ==, "arg");
	test_str(cmd.argv[argv_size - 1], ==, "arg");
	test_pass(cmd.argv[argv_size] == NULL);

	command_destroy(&cmd);
}

static void
test_command_add_arg(void)
{
	struct command cmd;

	command_init(&cmd, "test", NULL);

	command_add_arg(&cmd, "arg 0");
	test_pass(cmd.argc == 1);
	test_str(cmd.argv[0], ==, "arg 0");
	test_pass(cmd.argv[1] == NULL);

	command_add_arg(&cmd, "arg 1");
	test_pass(cmd.argc == 2);
	test_str(cmd.argv[0], ==, "arg 0");
	test_str(cmd.argv[1], ==, "arg 1");
	test_pass(cmd.argv[2] == NULL);

	command_add_arg(&cmd, "arg 2");
	test_pass(cmd.argc == 3);
	test_str(cmd.argv[0], ==, "arg 0");
	test_str(cmd.argv[1], ==, "arg 1");
	test_str(cmd.argv[2], ==, "arg 2");
	test_pass(cmd.argv[3] == NULL);

	command_destroy(&cmd);
}

static void
test_command_add_argl(void)
{
	struct command cmd;
	const char *args[] = {
		"arg 1",
		"arg 2",
		"arg 3",
		NULL,
	};

	command_init(&cmd, "test", NULL);

	command_add_arg(&cmd, "arg 0");

	command_add_argl(&cmd, args);
	test_pass(cmd.argc == 4);
	test_str(cmd.argv[0], ==, "arg 0");
	test_str(cmd.argv[1], ==, "arg 1");
	test_str(cmd.argv[2], ==, "arg 2");
	test_str(cmd.argv[3], ==, "arg 3");
	test_pass(cmd.argv[4] == NULL);

	command_destroy(&cmd);
}

static void
test_command_add_args(void)
{
	struct command cmd;

	command_init(&cmd, "test", NULL);

	command_add_arg(&cmd, "arg 0");

	command_add_args(&cmd, "arg 1", "arg 2", "arg 3", NULL);
	test_pass(cmd.argc == 4);
	test_str(cmd.argv[0], ==, "arg 0");
	test_str(cmd.argv[1], ==, "arg 1");
	test_str(cmd.argv[2], ==, "arg 2");
	test_str(cmd.argv[3], ==, "arg 3");
	test_pass(cmd.argv[4] == NULL);

	command_destroy(&cmd);
}

static void
test_command_exec(void)
{
	struct command cmd;
	pid_t pid;
	int ret;

	command_init(&cmd, "true", "exec test");

	command_add_arg(&cmd, "arg 0");
	command_add_arg(&cmd, "arg 1");

	pid = subproc_fork();

	if (pid == 0)
		command_exec(&cmd);

	ret = subproc_wait_check(pid, "command exec test", 0);
	test_pass(ret == 0);
}

static void
test_command_shell(void)
{
	pid_t pid;
	int ret;

	pid = subproc_fork();
	if (pid == 0)
		command_shell("true", "command shell pass test");
	ret = subproc_wait_check(pid, "command shell pass test", 0);
	test_pass(ret == 0);

	pid = subproc_fork();
	if (pid == 0)
		command_shell("false", "command shell fail test");
	ret = subproc_wait_check(pid, "command shell fail test", PROCNOERR);
	test_fail(ret == 0);

	unsetenv("SHELL");
	pid = subproc_fork();
	if (pid == 0)
		command_shell("true", "command default shell test");
	ret = subproc_wait_check(pid, "command default shell test", 0);
	test_pass(ret == 0);
}

static void
test_dup_file(int fd, const char *filename, int flags)
{
	int newfd;

	newfd = open(filename, flags);
	dup2(newfd, fd);
	close(newfd);
}

static void
test_command_pager(void)
{
	const char *pager, *default_pager;
	int origfd = dup(STDOUT_FILENO);

	/* Test stdout being a tty. */
	test_todo_block("environment might not expose controlling terminal") {
		test_dup_file(STDOUT_FILENO, "/dev/tty", O_WRONLY);
		setenv("PAGER", "test-pager", 1);
		pager = command_get_pager();
		unsetenv("PAGER");
		default_pager = command_get_pager();
		dup2(origfd, STDOUT_FILENO);
		test_str(pager, ==, "test-pager");
		test_str(default_pager, ==, DEFAULTPAGER);
	}

	/* Test stdout not being a tty. */
	test_dup_file(STDOUT_FILENO, "/dev/null", O_WRONLY);
	pager = command_get_pager();
	dup2(origfd, STDOUT_FILENO);
	test_str(pager, ==, CAT);
}

static void
test(void)
{
	test_plan(52);

	test_command_init();
	test_command_grow_argv();
	test_command_add_arg();
	test_command_add_argl();
	test_command_add_args();
	test_command_exec();
	test_command_shell();
	test_command_pager();
}
