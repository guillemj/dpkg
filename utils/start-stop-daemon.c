/*
 * A rewrite of the original Debian's start-stop-daemon Perl script
 * in C (faster - it is executed many times during system startup).
 *
 * Written by Marek Michalkiewicz <marekm@i17linuxb.ists.pwr.wroc.pl>,
 * public domain.  Based conceptually on start-stop-daemon.pl, by Ian
 * Jackson <ijackson@gnu.ai.mit.edu>.  May be used and distributed
 * freely for any purpose.  Changes by Christian Schwarz
 * <schwarz@monet.m.isar.de>, to make output conform to the Debian
 * Console Message Standard, also placed in public domain.  Minor
 * changes by Klee Dienes <klee@debian.org>, also placed in the Public
 * Domain.
 *
 * Changes by Ben Collins <bcollins@debian.org>, added --chuid, --background
 * and --make-pidfile options, placed in public domain as well.
 *
 * Port to OpenBSD by Sontri Tomo Huynh <huynh.29@osu.edu>
 *                 and Andreas Schuldei <andreas@schuldei.org>
 *
 * Changes by Ian Jackson: added --retry (and associated rearrangements).
 */

#include <config.h>
#include <compat.h>

#include <dpkg/macros.h>

#if defined(linux) || (defined(__FreeBSD_kernel__) && defined(__GLIBC__))
#  define OSLinux
#elif defined(__GNU__)
#  define OSHurd
#elif defined(__sun)
#  define OSsunos
#elif defined(OPENBSD) || defined(__OpenBSD__)
#  define OSOpenBSD
#elif defined(hpux)
#  define OShpux
#elif defined(__FreeBSD__)
#  define OSFreeBSD
#elif defined(__NetBSD__)
#  define OSNetBSD
#else
#  error Unknown architecture - cannot build start-stop-daemon
#endif

#define MIN_POLL_INTERVAL 20000 /* µs */

#ifdef HAVE_SYS_SYSCALL_H
#include <sys/syscall.h>
#endif

#if defined(OSHurd)
#include <hurd.h>
#include <ps.h>
#endif

#if defined(OSOpenBSD) || defined(OSFreeBSD) || defined(OSNetBSD)
#include <sys/param.h>
#include <sys/proc.h>

#include <err.h>
#endif

#ifdef HAVE_KVM_H
#include <sys/sysctl.h>
#include <sys/user.h>

#include <kvm.h>
#endif

#if defined(OShpux)
#include <sys/param.h>
#include <sys/pstat.h>
#endif

#include <sys/types.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/termios.h>

#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <fcntl.h>
#include <dirent.h>
#include <ctype.h>
#include <string.h>
#include <pwd.h>
#include <grp.h>
#include <signal.h>
#include <unistd.h>
#ifdef HAVE_STDDEF_H
#include <stddef.h>
#endif
#include <stdbool.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <getopt.h>

#ifdef HAVE_ERROR_H
#include <error.h>
#endif

#ifdef _POSIX_PRIORITY_SCHEDULING
#include <sched.h>
#else
#define SCHED_OTHER -1
#define SCHED_FIFO -1
#define SCHED_RR -1
#endif

#if defined(OSLinux)
/* This comes from TASK_COMM_LEN defined in Linux' include/linux/sched.h. */
#define PROCESS_NAME_SIZE 15
#elif defined(OSsunos)
#define PROCESS_NAME_SIZE 15
#elif defined(OSDarwin)
#define PROCESS_NAME_SIZE 16
#elif defined(OSNetBSD)
#define PROCESS_NAME_SIZE 16
#elif defined(OSOpenBSD)
#define PROCESS_NAME_SIZE 16
#elif defined(OSFreeBSD)
#define PROCESS_NAME_SIZE 19
#endif

#if defined(SYS_ioprio_set) && defined(linux)
#define HAVE_IOPRIO_SET
#endif

enum {
	IOPRIO_WHO_PROCESS = 1,
	IOPRIO_WHO_PGRP,
	IOPRIO_WHO_USER,
};

enum {
	IOPRIO_CLASS_NONE,
	IOPRIO_CLASS_RT,
	IOPRIO_CLASS_BE,
	IOPRIO_CLASS_IDLE,
};

enum action_code {
	action_none,
	action_start,
	action_stop,
	action_status,
};

static enum action_code action;
static int testmode = 0;
static int quietmode = 0;
static int exitnodo = 1;
static int background = 0;
static int mpidfile = 0;
static int signal_nr = SIGTERM;
static int user_id = -1;
static int runas_uid = -1;
static int runas_gid = -1;
static const char *userspec = NULL;
static char *changeuser = NULL;
static const char *changegroup = NULL;
static char *changeroot = NULL;
static const char *changedir = "/";
static const char *cmdname = NULL;
static char *execname = NULL;
static char *startas = NULL;
static const char *pidfile = NULL;
static char what_stop[1024];
static const char *progname = "";
static int nicelevel = 0;
static int umask_value = -1;

#define IOPRIO_CLASS_SHIFT 13
#define IOPRIO_PRIO_VALUE(class, prio) (((class) << IOPRIO_CLASS_SHIFT) | (prio))
#define IO_SCHED_PRIO_MIN 0
#define IO_SCHED_PRIO_MAX 7

static struct stat exec_stat;
#if defined(OSHurd)
static struct proc_stat_list *procset = NULL;
#endif

/* LSB Init Script process status exit codes. */
enum status_code {
	status_ok = 0,
	status_dead_pidfile = 1,
	status_dead_lockfile = 2,
	status_dead = 3,
	status_unknown = 4,
};

struct pid_list {
	struct pid_list *next;
	pid_t pid;
};

static struct pid_list *found = NULL;
static struct pid_list *killed = NULL;

/* Resource scheduling policy. */
struct res_schedule {
	const char *policy_name;
	int policy;
	int priority;
};

struct schedule_item {
	enum {
		sched_timeout,
		sched_signal,
		sched_goto,
		/* Only seen within parse_schedule and callees. */
		sched_forever,
	} type;
	/* Seconds, signal no., or index into array. */
	int value;
};

static struct res_schedule *proc_sched = NULL;
static struct res_schedule *io_sched = NULL;

static int schedule_length;
static struct schedule_item *schedule = NULL;


static void DPKG_ATTR_PRINTF(1)
warning(const char *format, ...)
{
	va_list arglist;

	fprintf(stderr, "%s: warning: ", progname);
	va_start(arglist, format);
	vfprintf(stderr, format, arglist);
	va_end(arglist);
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1)
fatal(const char *format, ...)
{
	va_list arglist;
	int errno_fatal = errno;

	fprintf(stderr, "%s: ", progname);
	va_start(arglist, format);
	vfprintf(stderr, format, arglist);
	va_end(arglist);
	if (errno_fatal)
		fprintf(stderr, " (%s)\n", strerror(errno_fatal));
	else
		fprintf(stderr, "\n");

	if (action == action_status)
		exit(status_unknown);
	else
		exit(2);
}

static void *
xmalloc(int size)
{
	void *ptr;

	ptr = malloc(size);
	if (ptr)
		return ptr;
	fatal("malloc(%d) failed", size);
}

static char *
xstrdup(const char *str)
{
	char *new_str;

	new_str = strdup(str);
	if (new_str)
		return new_str;
	fatal("strdup(%s) failed", str);
}

static void
xgettimeofday(struct timeval *tv)
{
	if (gettimeofday(tv, NULL) != 0)
		fatal("gettimeofday failed");
}

static void
tmul(struct timeval *a, int b)
{
	a->tv_sec *= b;
	a->tv_usec *= b;
	a->tv_sec = a->tv_sec + a->tv_usec / 1000000;
	a->tv_usec %= 1000000;
}

static char *
newpath(const char *dirname, const char *filename)
{
	char *path;
	size_t path_len;

	path_len = strlen(dirname) + 1 + strlen(filename) + 1;
	path = xmalloc(path_len);
	snprintf(path, path_len, "%s/%s", dirname, filename);

	return path;
}

static long
get_open_fd_max(void)
{
#ifdef HAVE_GETDTABLESIZE
	return getdtablesize();
#else
	return sysconf(_SC_OPEN_MAX);
#endif
}

#ifndef HAVE_SETSID
static void
detach_controlling_tty(void)
{
#ifdef HAVE_TIOCNOTTY
	int tty_fd;

	tty_fd = open("/dev/tty", O_RDWR);

	/* The current process does not have a controlling tty. */
	if (tty_fd < 0)
		return;

	if (ioctl(tty_fd, TIOCNOTTY, 0) != 0)
		fatal("unable to detach controlling tty");

	close(tty_fd);
#endif
}
#endif

static void
daemonize(void)
{
	pid_t pid;

	if (quietmode < 0)
		printf("Detaching to start %s...", startas);

	pid = fork();
	if (pid < 0)
		fatal("unable to do first fork");
	else if (pid) /* Parent. */
		_exit(0);

	/* Create a new session. */
#ifdef HAVE_SETSID
	setsid();
#else
	setpgid(0, 0);
	detach_controlling_tty();
#endif

	pid = fork();
	if (pid < 0)
		fatal("unable to do second fork");
	else if (pid) /* Parent. */
		_exit(0);

	if (quietmode < 0)
		printf("done.\n");
}

static void
pid_list_push(struct pid_list **list, pid_t pid)
{
	struct pid_list *p;

	p = xmalloc(sizeof(*p));
	p->next = *list;
	p->pid = pid;
	*list = p;
}

static void
pid_list_free(struct pid_list **list)
{
	struct pid_list *here, *next;

	for (here = *list; here != NULL; here = next) {
		next = here->next;
		free(here);
	}

	*list = NULL;
}

static void
usage(void)
{
	printf(
"Usage: start-stop-daemon [<option> ...] <command>\n"
"\n"
"Commands:\n"
"  -S|--start -- <argument> ...  start a program and pass <arguments> to it\n"
"  -K|--stop                     stop a program\n"
"  -T|--status                   get the program status\n"
"  -H|--help                     print help information\n"
"  -V|--version                  print version\n"
"\n"
"Matching options (at least one is required):\n"
"  -p|--pidfile <pid-file>       pid file to check\n"
"  -x|--exec <executable>        program to start/check if it is running\n"
"  -n|--name <process-name>      process name to check\n"
"  -u|--user <username|uid>      process owner to check\n"
"\n"
"Options:\n"
"  -g|--group <group|gid>        run process as this group\n"
"  -c|--chuid <name|uid[:group|gid]>\n"
"                                change to this user/group before starting\n"
"                                  process\n"
"  -s|--signal <signal>          signal to send (default TERM)\n"
"  -a|--startas <pathname>       program to start (default is <executable>)\n"
"  -r|--chroot <directory>       chroot to <directory> before starting\n"
"  -d|--chdir <directory>        change to <directory> (default is /)\n"
"  -N|--nicelevel <incr>         add incr to the process' nice level\n"
"  -P|--procsched <policy[:prio]>\n"
"                                use <policy> with <prio> for the kernel\n"
"                                  process scheduler (default prio is 0)\n"
"  -I|--iosched <class[:prio]>   use <class> with <prio> to set the IO\n"
"                                  scheduler (default prio is 4)\n"
"  -k|--umask <mask>             change the umask to <mask> before starting\n"
"  -b|--background               force the process to detach\n"
"  -m|--make-pidfile             create the pidfile before starting\n"
"  -R|--retry <schedule>         check whether processes die, and retry\n"
"  -t|--test                     test mode, don't do anything\n"
"  -o|--oknodo                   exit status 0 (not 1) if nothing done\n"
"  -q|--quiet                    be more quiet\n"
"  -v|--verbose                  be more verbose\n"
"\n"
"Retry <schedule> is <item>|/<item>/... where <item> is one of\n"
" -<signal-num>|[-]<signal-name>  send that signal\n"
" <timeout>                       wait that many seconds\n"
" forever                         repeat remainder forever\n"
"or <schedule> may be just <timeout>, meaning <signal>/<timeout>/KILL/<timeout>\n"
"\n"
"The process scheduler <policy> can be one of:\n"
"  other, fifo or rr\n"
"\n"
"The IO scheduler <class> can be one of:\n"
"  real-time, best-effort or idle\n"
"\n"
"Exit status:\n"
"  0 = done\n"
"  1 = nothing done (=> 0 if --oknodo)\n"
"  2 = with --retry, processes would not die\n"
"  3 = trouble\n"
"Exit status with --status:\n"
"  0 = program is running\n"
"  1 = program is not running and the pid file exists\n"
"  3 = program is not running\n"
"  4 = unable to determine status\n");
}

static void
do_version(void)
{
	printf("start-stop-daemon %s for Debian\n\n", VERSION);

	printf("Written by Marek Michalkiewicz, public domain.\n");
}

static void DPKG_ATTR_NORET
badusage(const char *msg)
{
	if (msg)
		fprintf(stderr, "%s: %s\n", progname, msg);
	fprintf(stderr, "Try '%s --help' for more information.\n", progname);

	if (action == action_status)
		exit(status_unknown);
	else
		exit(3);
}

struct sigpair {
	const char *name;
	int signal;
};

static const struct sigpair siglist[] = {
	{ "ABRT",	SIGABRT	},
	{ "ALRM",	SIGALRM	},
	{ "FPE",	SIGFPE	},
	{ "HUP",	SIGHUP	},
	{ "ILL",	SIGILL	},
	{ "INT",	SIGINT	},
	{ "KILL",	SIGKILL	},
	{ "PIPE",	SIGPIPE	},
	{ "QUIT",	SIGQUIT	},
	{ "SEGV",	SIGSEGV	},
	{ "TERM",	SIGTERM	},
	{ "USR1",	SIGUSR1	},
	{ "USR2",	SIGUSR2	},
	{ "CHLD",	SIGCHLD	},
	{ "CONT",	SIGCONT	},
	{ "STOP",	SIGSTOP	},
	{ "TSTP",	SIGTSTP	},
	{ "TTIN",	SIGTTIN	},
	{ "TTOU",	SIGTTOU	}
};

static int
parse_integer(const char *string, int *value_r)
{
	unsigned long ul;
	char *ep;

	if (!string[0])
		return -1;

	ul = strtoul(string, &ep, 10);
	if (string == ep || ul > INT_MAX || *ep != '\0')
		return -1;

	*value_r = ul;
	return 0;
}

static int
parse_signal(const char *sig_str, int *sig_num)
{
	unsigned int i;

	if (parse_integer(sig_str, sig_num) == 0)
		return 0;

	for (i = 0; i < array_count(siglist); i++) {
		if (strcmp(sig_str, siglist[i].name) == 0) {
			*sig_num = siglist[i].signal;
			return 0;
		}
	}
	return -1;
}

static int
parse_umask(const char *string, int *value_r)
{
	if (!string[0])
		return -1;

	errno = 0;
	*value_r = strtoul(string, NULL, 0);
	if (errno)
		return -1;
	else
		return 0;
}

static void
validate_proc_schedule(void)
{
#ifdef _POSIX_PRIORITY_SCHEDULING
	int prio_min, prio_max;

	prio_min = sched_get_priority_min(proc_sched->policy);
	prio_max = sched_get_priority_max(proc_sched->policy);

	if (proc_sched->priority < prio_min)
		badusage("process scheduler priority less than min");
	if (proc_sched->priority > prio_max)
		badusage("process scheduler priority greater than max");
#endif
}

static void
parse_proc_schedule(const char *string)
{
	char *policy_str, *prio_str;
	int prio = 0;

	policy_str = xstrdup(string);
	policy_str = strtok(policy_str, ":");
	prio_str = strtok(NULL, ":");

	if (prio_str && parse_integer(prio_str, &prio) != 0)
		fatal("invalid process scheduler priority");

	proc_sched = xmalloc(sizeof(*proc_sched));
	proc_sched->policy_name = policy_str;

	if (strcmp(policy_str, "other") == 0) {
		proc_sched->policy = SCHED_OTHER;
		proc_sched->priority = 0;
	} else if (strcmp(policy_str, "fifo") == 0) {
		proc_sched->policy = SCHED_FIFO;
		proc_sched->priority = prio;
	} else if (strcmp(policy_str, "rr") == 0) {
		proc_sched->policy = SCHED_RR;
		proc_sched->priority = prio;
	} else
		badusage("invalid process scheduler policy");

	validate_proc_schedule();
}

static void
parse_io_schedule(const char *string)
{
	char *class_str, *prio_str;
	int prio = 4;

	class_str = xstrdup(string);
	class_str = strtok(class_str, ":");
	prio_str = strtok(NULL, ":");

	if (prio_str && parse_integer(prio_str, &prio) != 0)
		fatal("invalid IO scheduler priority");

	io_sched = xmalloc(sizeof(*io_sched));
	io_sched->policy_name = class_str;

	if (strcmp(class_str, "real-time") == 0) {
		io_sched->policy = IOPRIO_CLASS_RT;
		io_sched->priority = prio;
	} else if (strcmp(class_str, "best-effort") == 0) {
		io_sched->policy = IOPRIO_CLASS_BE;
		io_sched->priority = prio;
	} else if (strcmp(class_str, "idle") == 0) {
		io_sched->policy = IOPRIO_CLASS_IDLE;
		io_sched->priority = 7;
	} else
		badusage("invalid IO scheduler policy");

	if (io_sched->priority < IO_SCHED_PRIO_MIN)
		badusage("IO scheduler priority less than min");
	if (io_sched->priority > IO_SCHED_PRIO_MAX)
		badusage("IO scheduler priority greater than max");
}

static void
set_proc_schedule(struct res_schedule *sched)
{
#ifdef _POSIX_PRIORITY_SCHEDULING
	struct sched_param param;

	param.sched_priority = sched->priority;

	if (sched_setscheduler(getpid(), sched->policy, &param) == -1)
		fatal("unable to set process scheduler");
#endif
}

#ifdef HAVE_IOPRIO_SET
static inline int
ioprio_set(int which, int who, int ioprio)
{
	return syscall(SYS_ioprio_set, which, who, ioprio);
}
#endif

static void
set_io_schedule(struct res_schedule *sched)
{
#ifdef HAVE_IOPRIO_SET
	int io_sched_mask;

	io_sched_mask = IOPRIO_PRIO_VALUE(sched->policy, sched->priority);
	if (ioprio_set(IOPRIO_WHO_PROCESS, getpid(), io_sched_mask) == -1)
		warning("unable to alter IO priority to mask %i (%s)\n",
		        io_sched_mask, strerror(errno));
#endif
}

static void
parse_schedule_item(const char *string, struct schedule_item *item)
{
	const char *after_hyph;

	if (strcmp(string, "forever") == 0) {
		item->type = sched_forever;
	} else if (isdigit(string[0])) {
		item->type = sched_timeout;
		if (parse_integer(string, &item->value) != 0)
			badusage("invalid timeout value in schedule");
	} else if ((after_hyph = string + (string[0] == '-')) &&
	           parse_signal(after_hyph, &item->value) == 0) {
		item->type = sched_signal;
	} else {
		badusage("invalid schedule item (must be [-]<signal-name>, "
		         "-<signal-number>, <timeout> or 'forever'");
	}
}

static void
parse_schedule(const char *schedule_str)
{
	char item_buf[20];
	const char *slash;
	int count, repeatat;
	size_t str_len;

	count = 0;
	for (slash = schedule_str; *slash; slash++)
		if (*slash == '/')
			count++;

	schedule_length = (count == 0) ? 4 : count + 1;
	schedule = xmalloc(sizeof(*schedule) * schedule_length);

	if (count == 0) {
		schedule[0].type = sched_signal;
		schedule[0].value = signal_nr;
		parse_schedule_item(schedule_str, &schedule[1]);
		if (schedule[1].type != sched_timeout) {
			badusage ("--retry takes timeout, or schedule list"
			          " of at least two items");
		}
		schedule[2].type = sched_signal;
		schedule[2].value = SIGKILL;
		schedule[3] = schedule[1];
	} else {
		count = 0;
		repeatat = -1;
		while (schedule_str != NULL) {
			slash = strchr(schedule_str, '/');
			str_len = slash ? (size_t)(slash - schedule_str) : strlen(schedule_str);
			if (str_len >= sizeof(item_buf))
				badusage("invalid schedule item: far too long"
				         " (you must delimit items with slashes)");
			memcpy(item_buf, schedule_str, str_len);
			item_buf[str_len] = '\0';
			schedule_str = slash ? slash + 1 : NULL;

			parse_schedule_item(item_buf, &schedule[count]);
			if (schedule[count].type == sched_forever) {
				if (repeatat >= 0)
					badusage("invalid schedule: 'forever'"
					         " appears more than once");
				repeatat = count;
				continue;
			}
			count++;
		}
		if (repeatat == count)
			badusage("invalid schedule: 'forever' appears last, "
			         "nothing to repeat");
		if (repeatat >= 0) {
			schedule[count].type = sched_goto;
			schedule[count].value = repeatat;
			count++;
		}
		assert(count == schedule_length);
	}
}

static void
set_action(enum action_code new_action)
{
	if (action == new_action)
		return;

	if (action != action_none)
		badusage("only one command can be specified");

	action = new_action;
}

static void
parse_options(int argc, char * const *argv)
{
	static struct option longopts[] = {
		{ "help",	  0, NULL, 'H'},
		{ "stop",	  0, NULL, 'K'},
		{ "start",	  0, NULL, 'S'},
		{ "status",	  0, NULL, 'T'},
		{ "version",	  0, NULL, 'V'},
		{ "startas",	  1, NULL, 'a'},
		{ "name",	  1, NULL, 'n'},
		{ "oknodo",	  0, NULL, 'o'},
		{ "pidfile",	  1, NULL, 'p'},
		{ "quiet",	  0, NULL, 'q'},
		{ "signal",	  1, NULL, 's'},
		{ "test",	  0, NULL, 't'},
		{ "user",	  1, NULL, 'u'},
		{ "group",	  1, NULL, 'g'},
		{ "chroot",	  1, NULL, 'r'},
		{ "verbose",	  0, NULL, 'v'},
		{ "exec",	  1, NULL, 'x'},
		{ "chuid",	  1, NULL, 'c'},
		{ "nicelevel",	  1, NULL, 'N'},
		{ "procsched",	  1, NULL, 'P'},
		{ "iosched",	  1, NULL, 'I'},
		{ "umask",	  1, NULL, 'k'},
		{ "background",	  0, NULL, 'b'},
		{ "make-pidfile", 0, NULL, 'm'},
		{ "retry",	  1, NULL, 'R'},
		{ "chdir",	  1, NULL, 'd'},
		{ NULL,		  0, NULL, 0  }
	};
	const char *umask_str = NULL;
	const char *signal_str = NULL;
	const char *schedule_str = NULL;
	const char *proc_schedule_str = NULL;
	const char *io_schedule_str = NULL;
	int c;

	for (;;) {
		c = getopt_long(argc, argv,
		                "HKSVTa:n:op:qr:s:tu:vx:c:N:P:I:k:bmR:g:d:",
		                longopts, NULL);
		if (c == -1)
			break;
		switch (c) {
		case 'H':  /* --help */
			usage();
			exit(0);
		case 'K':  /* --stop */
			set_action(action_stop);
			break;
		case 'S':  /* --start */
			set_action(action_start);
			break;
		case 'T':  /* --status */
			set_action(action_status);
			break;
		case 'V':  /* --version */
			do_version();
			exit(0);
		case 'a':  /* --startas <pathname> */
			startas = optarg;
			break;
		case 'n':  /* --name <process-name> */
			cmdname = optarg;
			break;
		case 'o':  /* --oknodo */
			exitnodo = 0;
			break;
		case 'p':  /* --pidfile <pid-file> */
			pidfile = optarg;
			break;
		case 'q':  /* --quiet */
			quietmode = 1;
			break;
		case 's':  /* --signal <signal> */
			signal_str = optarg;
			break;
		case 't':  /* --test */
			testmode = 1;
			break;
		case 'u':  /* --user <username>|<uid> */
			userspec = optarg;
			break;
		case 'v':  /* --verbose */
			quietmode = -1;
			break;
		case 'x':  /* --exec <executable> */
			execname = optarg;
			break;
		case 'c':  /* --chuid <username>|<uid> */
			/* We copy the string just in case we need the
			 * argument later. */
			changeuser = xstrdup(optarg);
			changeuser = strtok(changeuser, ":");
			changegroup = strtok(NULL, ":");
			break;
		case 'g':  /* --group <group>|<gid> */
			changegroup = optarg;
			break;
		case 'r':  /* --chroot /new/root */
			changeroot = optarg;
			break;
		case 'N':  /* --nice */
			nicelevel = atoi(optarg);
			break;
		case 'P':  /* --procsched */
			proc_schedule_str = optarg;
			break;
		case 'I':  /* --iosched */
			io_schedule_str = optarg;
			break;
		case 'k':  /* --umask <mask> */
			umask_str = optarg;
			break;
		case 'b':  /* --background */
			background = 1;
			break;
		case 'm':  /* --make-pidfile */
			mpidfile = 1;
			break;
		case 'R':  /* --retry <schedule>|<timeout> */
			schedule_str = optarg;
			break;
		case 'd':  /* --chdir /new/dir */
			changedir = optarg;
			break;
		default:
			/* Message printed by getopt. */
			badusage(NULL);
		}
	}

	if (signal_str != NULL) {
		if (parse_signal(signal_str, &signal_nr) != 0)
			badusage("signal value must be numeric or name"
			         " of signal (KILL, INT, ...)");
	}

	if (schedule_str != NULL) {
		parse_schedule(schedule_str);
	}

	if (proc_schedule_str != NULL)
		parse_proc_schedule(proc_schedule_str);

	if (io_schedule_str != NULL)
		parse_io_schedule(io_schedule_str);

	if (umask_str != NULL) {
		if (parse_umask(umask_str, &umask_value) != 0)
			badusage("umask value must be a positive number");
	}

	if (action == action_none)
		badusage("need one of --start or --stop or --status");

	if (!execname && !pidfile && !userspec && !cmdname)
		badusage("need at least one of --exec, --pidfile, --user or --name");

#ifdef PROCESS_NAME_SIZE
	if (cmdname && strlen(cmdname) > PROCESS_NAME_SIZE)
		warning("this system is not able to track process names\n"
		        "longer than %d characters, please use --exec "
		        "instead of --name.\n", PROCESS_NAME_SIZE);
#endif

	if (!startas)
		startas = execname;

	if (action == action_start && !startas)
		badusage("--start needs --exec or --startas");

	if (mpidfile && pidfile == NULL)
		badusage("--make-pidfile requires --pidfile");

	if (background && action != action_start)
		badusage("--background is only relevant with --start");
}

#if defined(OSHurd)
static void
init_procset(void)
{
	struct ps_context *context;
	error_t err;

	err = ps_context_create(getproc(), &context);
	if (err)
		error(1, err, "ps_context_create");

	err = proc_stat_list_create(context, &procset);
	if (err)
		error(1, err, "proc_stat_list_create");

	err = proc_stat_list_add_all(procset, 0, 0);
	if (err)
		error(1, err, "proc_stat_list_add_all");
}

static struct proc_stat *
get_proc_stat(pid_t pid, ps_flags_t flags)
{
	struct proc_stat *ps;
	ps_flags_t wanted_flags = PSTAT_PID | flags;

	if (!procset)
		init_procset();

	ps = proc_stat_list_pid_proc_stat(procset, pid);
	if (!ps)
		return NULL;
	if (proc_stat_set_flags(ps, wanted_flags))
		return NULL;
	if ((proc_stat_flags(ps) & wanted_flags) != wanted_flags)
		return NULL;

	return ps;
}
#endif

#if defined(OSLinux)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	char lname[32];
	char lcontents[_POSIX_PATH_MAX];
	const char deleted[] = " (deleted)";
	int nread;
	struct stat sb;

	sprintf(lname, "/proc/%d/exe", pid);
	nread = readlink(lname, lcontents, sizeof(lcontents));
	if (nread == -1)
		return false;

	lcontents[nread] = '\0';
	if (strcmp(lcontents + nread - strlen(deleted), deleted) == 0)
		lcontents[nread - strlen(deleted)] = '\0';

	if (stat(lcontents, &sb) != 0)
		return false;

	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}
#elif defined(OSHurd)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	struct proc_stat *ps;
	struct stat sb;
	const char *filename;

	ps = get_proc_stat(pid, PSTAT_ARGS);
	if (ps == NULL)
		return false;

	filename = proc_stat_args(ps);

	if (stat(filename, &sb) != 0)
		return false;

	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}
#elif defined(OShpux)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t)0, (int)pid) < 0)
		return false;
	return ((dev_t)pst.pst_text.psf_fsid.psfs_id == esb->st_dev &&
	        (ino_t)pst.pst_text.psf_fileid == esb->st_ino);
}
#elif defined(HAVE_KVM_H)
static bool
pid_is_exec(pid_t pid, const struct stat *esb)
{
	kvm_t *kd;
	int nentries, argv_len = 0;
	struct kinfo_proc *kp;
	struct stat sb;
	char errbuf[_POSIX2_LINE_MAX], buf[_POSIX2_LINE_MAX];
	char **pid_argv_p;
	char *start_argv_0_p, *end_argv_0_p;

	kd = kvm_openfiles(NULL, NULL, NULL, O_RDONLY, errbuf);
	if (kd == NULL)
		errx(1, "%s", errbuf);
	kp = kvm_getprocs(kd, KERN_PROC_PID, pid, &nentries);
	if (kp == NULL)
		errx(1, "%s", kvm_geterr(kd));
	pid_argv_p = kvm_getargv(kd, kp, argv_len);
	if (pid_argv_p == NULL)
		errx(1, "%s", kvm_geterr(kd));

	/* Find and compare string. */
	start_argv_0_p = *pid_argv_p;

	/* Find end of argv[0] then copy and cut of str there. */
	end_argv_0_p = strchr(*pid_argv_p, ' ');
	if (end_argv_0_p == NULL)
		/* There seems to be no space, so we have the command
		 * already in its desired form. */
		start_argv_0_p = *pid_argv_p;
	else {
		/* Tests indicate that this never happens, since
		 * kvm_getargv itself cuts of tailing stuff. This is
		 * not what the manpage says, however. */
		strncpy(buf, *pid_argv_p, (end_argv_0_p - start_argv_0_p));
		buf[(end_argv_0_p - start_argv_0_p) + 1] = '\0';
		start_argv_0_p = buf;
	}

	if (stat(start_argv_0_p, &sb) != 0)
		return false;

	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}
#endif

#if defined(OSLinux)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct stat sb;
	char buf[32];

	sprintf(buf, "/proc/%d", pid);
	if (stat(buf, &sb) != 0)
		return false;
	return (sb.st_uid == uid);
}
#elif defined(OSHurd)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct proc_stat *ps;

	ps = get_proc_stat(pid, PSTAT_OWNER_UID);
	return ps && (uid_t)proc_stat_owner_uid(ps) == uid;
}
#elif defined(OShpux)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t)0, (int)pid) < 0)
		return false;
	return ((uid_t)pst.pst_uid == uid);
}
#elif defined(HAVE_KVM_H)
static bool
pid_is_user(pid_t pid, uid_t uid)
{
	kvm_t *kd;
	int nentries; /* Value not used. */
	uid_t proc_uid;
	struct kinfo_proc *kp;
	char errbuf[_POSIX2_LINE_MAX];

	kd = kvm_openfiles(NULL, NULL, NULL, O_RDONLY, errbuf);
	if (kd == NULL)
		errx(1, "%s", errbuf);
	kp = kvm_getprocs(kd, KERN_PROC_PID, pid, &nentries);
	if (kp == NULL)
		errx(1, "%s", kvm_geterr(kd));
	if (kp->kp_proc.p_cred)
		kvm_read(kd, (u_long)&(kp->kp_proc.p_cred->p_ruid),
		         &proc_uid, sizeof(uid_t));
	else
		return false;
	return (proc_uid == (uid_t)uid);
}
#endif

#if defined(OSLinux)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	char buf[32];
	FILE *f;
	int c;

	sprintf(buf, "/proc/%d/stat", pid);
	f = fopen(buf, "r");
	if (!f)
		return false;
	while ((c = getc(f)) != EOF && c != '(')
		;
	if (c != '(') {
		fclose(f);
		return false;
	}
	/* This hopefully handles command names containing ‘)’. */
	while ((c = getc(f)) != EOF && c == *name)
		name++;
	fclose(f);
	return (c == ')' && *name == '\0');
}
#elif defined(OSHurd)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	struct proc_stat *ps;
	size_t argv0_len;
	const char *argv0;
	const char *binary_name;

	ps = get_proc_stat(pid, PSTAT_ARGS);
	if (ps == NULL)
		return false;

	argv0 = proc_stat_args(ps);
	argv0_len = strlen(argv0) + 1;

	binary_name = basename(argv0);
	if (strcmp(binary_name, name) == 0)
		return true;

	/* XXX: This is all kinds of ugly, but on the Hurd there's no way to
	 * know the command name of a process, so we have to try to match
	 * also on argv[1] for the case of an interpreted script. */
	if (proc_stat_args_len(ps) > argv0_len) {
		const char *script_name = basename(argv0 + argv0_len);

		return strcmp(script_name, name) == 0;
	}

	return false;
}
#elif defined(OShpux)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t)0, (int)pid) < 0)
		return false;
	return (strcmp(pst.pst_ucomm, name) == 0);
}
#elif defined(HAVE_KVM_H)
static bool
pid_is_cmd(pid_t pid, const char *name)
{
	kvm_t *kd;
	int nentries;
	struct kinfo_proc *kp;
	char errbuf[_POSIX2_LINE_MAX], *process_name;

	kd = kvm_openfiles(NULL, NULL, NULL, O_RDONLY, errbuf);
	if (kd == NULL)
		errx(1, "%s", errbuf);
	kp = kvm_getprocs(kd, KERN_PROC_PID, pid, &nentries);
	if (kp == NULL)
		errx(1, "%s", kvm_geterr(kd));
	process_name = (&kp->kp_proc)->p_comm;
	if (strlen(name) != strlen(process_name))
		return false;
	return (strcmp(name, process_name) == 0);
}
#endif

#if defined(OSHurd)
static bool
pid_is_running(pid_t pid)
{
	return get_proc_stat(pid, 0) != NULL;
}
#else /* !OSHurd */
static bool
pid_is_running(pid_t pid)
{
	if (kill(pid, 0) == 0 || errno == EPERM)
		return true;
	else if (errno == ESRCH)
		return false;
	else
		fatal("error checking pid %u status", pid);
}
#endif

static enum status_code
pid_check(pid_t pid)
{
	if (execname && !pid_is_exec(pid, &exec_stat))
		return status_dead;
	if (userspec && !pid_is_user(pid, user_id))
		return status_dead;
	if (cmdname && !pid_is_cmd(pid, cmdname))
		return status_dead;
	if (action != action_stop && !pid_is_running(pid))
		return status_dead;

	pid_list_push(&found, pid);

	return status_ok;
}

static enum status_code
do_pidfile(const char *name)
{
	FILE *f;
	static pid_t pid = 0;

	if (pid)
		return pid_check(pid);

	f = fopen(name, "r");
	if (f) {
		enum status_code pid_status;

		if (fscanf(f, "%d", &pid) == 1)
			pid_status = pid_check(pid);
		else
			pid_status = status_unknown;
		fclose(f);

		if (pid_status == status_dead)
			return status_dead_pidfile;
		else
			return pid_status;
	} else if (errno == ENOENT)
		return status_dead;
	else
		fatal("unable to open pidfile %s", name);
}

#if defined(OSLinux) || defined (OSsunos)
static enum status_code
do_procinit(void)
{
	DIR *procdir;
	struct dirent *entry;
	int foundany;
	pid_t pid;
	enum status_code prog_status = status_dead;

	procdir = opendir("/proc");
	if (!procdir)
		fatal("unable to opendir /proc");

	foundany = 0;
	while ((entry = readdir(procdir)) != NULL) {
		enum status_code pid_status;

		if (sscanf(entry->d_name, "%d", &pid) != 1)
			continue;
		foundany++;

		pid_status = pid_check(pid);
		if (pid_status < prog_status)
			prog_status = pid_status;
	}
	closedir(procdir);
	if (!foundany)
		fatal("nothing in /proc - not mounted?");

	return prog_status;
}
#elif defined(OSHurd)
static int
check_proc_stat(struct proc_stat *ps)
{
	pid_check(ps->pid);
	return 0;
}

static enum status_code
do_procinit(void)
{
	if (!procset)
		init_procset();

	proc_stat_list_for_each(procset, check_proc_stat);

	if (found)
		return status_ok;
	else
		return status_dead;
}
#elif defined(OShpux)
static enum status_code
do_procinit(void)
{
	struct pst_status pst[10];
	int i, count;
	int idx = 0;
	enum status_code prog_status = status_dead;

	while ((count = pstat_getproc(pst, sizeof(pst[0]), 10, idx)) > 0) {
		enum status_code pid_status;

		for (i = 0; i < count; i++) {
			pid_status = pid_check(pst[i].pst_pid);
			if (pid_status < prog_status)
				prog_status = pid_status;
		}
		idx = pst[count - 1].pst_idx + 1;
	}

	return prog_status;
}
#elif defined(HAVE_KVM_H)
static enum status_code
do_procinit(void)
{
	/* Nothing to do. */
	return status_unknown;
}
#endif

static enum status_code
do_findprocs(void)
{
	pid_list_free(&found);

	if (pidfile)
		return do_pidfile(pidfile);
	else
		return do_procinit();
}

static void
do_stop(int sig_num, int *n_killed, int *n_notkilled)
{
	struct pid_list *p;

	do_findprocs();

	*n_killed = 0;
	*n_notkilled = 0;

	if (!found)
		return;

	pid_list_free(&killed);

	for (p = found; p; p = p->next) {
		if (testmode) {
			if (quietmode <= 0)
				printf("Would send signal %d to %d.\n",
				       sig_num, p->pid);
			(*n_killed)++;
		} else if (kill(p->pid, sig_num) == 0) {
			pid_list_push(&killed, p->pid);
			(*n_killed)++;
		} else {
			if (sig_num)
				warning("failed to kill %d: %s\n",
				        p->pid, strerror(errno));
			(*n_notkilled)++;
		}
	}
}

static void
do_stop_summary(int retry_nr)
{
	struct pid_list *p;

	if (quietmode >= 0 || !killed)
		return;

	printf("Stopped %s (pid", what_stop);
	for (p = killed; p; p = p->next)
		printf(" %d", p->pid);
	putchar(')');
	if (retry_nr > 0)
		printf(", retry #%d", retry_nr);
	printf(".\n");
}

static void
set_what_stop(const char *str)
{
	strncpy(what_stop, str, sizeof(what_stop));
	what_stop[sizeof(what_stop) - 1] = '\0';
}

/*
 * We want to keep polling for the processes, to see if they've exited, or
 * until the timeout expires.
 *
 * This is a somewhat complicated algorithm to try to ensure that we notice
 * reasonably quickly when all the processes have exited, but don't spend
 * too much CPU time polling. In particular, on a fast machine with
 * quick-exiting daemons we don't want to delay system shutdown too much,
 * whereas on a slow one, or where processes are taking some time to exit,
 * we want to increase the polling interval.
 *
 * The algorithm is as follows: we measure the elapsed time it takes to do
 * one poll(), and wait a multiple of this time for the next poll. However,
 * if that would put us past the end of the timeout period we wait only as
 * long as the timeout period, but in any case we always wait at least
 * MIN_POLL_INTERVAL (20ms). The multiple (‘ratio’) starts out as 2, and
 * increases by 1 for each poll to a maximum of 10; so we use up to between
 * 30% and 10% of the machine's resources (assuming a few reasonable things
 * about system performance).
 */
static bool
do_stop_timeout(int timeout, int *n_killed, int *n_notkilled)
{
	struct timeval stopat, before, after, interval, maxinterval;
	int r, ratio;

	xgettimeofday(&stopat);
	stopat.tv_sec += timeout;
	ratio = 1;
	for (;;) {
		xgettimeofday(&before);
		if (timercmp(&before, &stopat, >))
			return false;

		do_stop(0, n_killed, n_notkilled);
		if (!*n_killed)
			return true;

		xgettimeofday(&after);

		if (!timercmp(&after, &stopat, <))
			return false;

		if (ratio < 10)
			ratio++;

		timersub(&stopat, &after, &maxinterval);
		timersub(&after, &before, &interval);
		tmul(&interval, ratio);

		if (interval.tv_sec < 0 || interval.tv_usec < 0)
			interval.tv_sec = interval.tv_usec = 0;

		if (timercmp(&interval, &maxinterval, >))
			interval = maxinterval;

		if (interval.tv_sec == 0 &&
		    interval.tv_usec <= MIN_POLL_INTERVAL)
			interval.tv_usec = MIN_POLL_INTERVAL;

		r = select(0, NULL, NULL, NULL, &interval);
		if (r < 0 && errno != EINTR)
			fatal("select() failed for pause");
	}
}

static int
finish_stop_schedule(bool anykilled)
{
	if (anykilled)
		return 0;

	if (quietmode <= 0)
		printf("No %s found running; none killed.\n", what_stop);

	return exitnodo;
}

static int
run_stop_schedule(void)
{
	int position, n_killed, n_notkilled, value, retry_nr;
	bool anykilled;

	if (testmode) {
		if (schedule != NULL) {
			if (quietmode <= 0)
				printf("Ignoring --retry in test mode\n");
			schedule = NULL;
		}
	}

	if (cmdname)
		set_what_stop(cmdname);
	else if (execname)
		set_what_stop(execname);
	else if (pidfile)
		sprintf(what_stop, "process in pidfile '%.200s'", pidfile);
	else if (userspec)
		sprintf(what_stop, "process(es) owned by '%.200s'", userspec);
	else
		fatal("internal error, no match option, please report");

	anykilled = false;
	retry_nr = 0;

	if (schedule == NULL) {
		do_stop(signal_nr, &n_killed, &n_notkilled);
		do_stop_summary(0);
		if (n_notkilled > 0 && quietmode <= 0)
			printf("%d pids were not killed\n", n_notkilled);
		if (n_killed)
			anykilled = true;
		return finish_stop_schedule(anykilled);
	}

	for (position = 0; position < schedule_length; position++) {
	reposition:
		value = schedule[position].value;
		n_notkilled = 0;

		switch (schedule[position].type) {
		case sched_goto:
			position = value;
			goto reposition;
		case sched_signal:
			do_stop(value, &n_killed, &n_notkilled);
			do_stop_summary(retry_nr++);
			if (!n_killed)
				return finish_stop_schedule(anykilled);
			else
				anykilled = true;
			continue;
		case sched_timeout:
			if (do_stop_timeout(value, &n_killed, &n_notkilled))
				return finish_stop_schedule(anykilled);
			else
				continue;
		default:
			assert(!"schedule[].type value must be valid");
		}
	}

	if (quietmode <= 0)
		printf("Program %s, %d process(es), refused to die.\n",
		       what_stop, n_killed);

	return 2;
}

int
main(int argc, char **argv)
{
	enum status_code prog_status;
	int devnull_fd = -1;
	gid_t rgid;
	uid_t ruid;
	progname = argv[0];

	parse_options(argc, argv);
	argc -= optind;
	argv += optind;

	if (execname) {
		char *fullexecname;


		if (changeroot)
			fullexecname = newpath(changeroot, execname);
		else
			fullexecname = execname;

		if (stat(fullexecname, &exec_stat))
			fatal("unable to stat %s", fullexecname);

		if (fullexecname != execname)
			free(fullexecname);
	}

	if (userspec && sscanf(userspec, "%d", &user_id) != 1) {
		struct passwd *pw;

		pw = getpwnam(userspec);
		if (!pw)
			fatal("user '%s' not found", userspec);

		user_id = pw->pw_uid;
	}

	if (changegroup && sscanf(changegroup, "%d", &runas_gid) != 1) {
		struct group *gr = getgrnam(changegroup);
		if (!gr)
			fatal("group '%s' not found", changegroup);
		changegroup = gr->gr_name;
		runas_gid = gr->gr_gid;
	}
	if (changeuser) {
		struct passwd *pw;
		struct stat st;

		if (sscanf(changeuser, "%d", &runas_uid) == 1)
			pw = getpwuid(runas_uid);
		else
			pw = getpwnam(changeuser);
		if (!pw)
			fatal("user '%s' not found", changeuser);
		changeuser = pw->pw_name;
		runas_uid = pw->pw_uid;
		if (changegroup == NULL) {
			/* Pass the default group of this user. */
			changegroup = ""; /* Just empty. */
			runas_gid = pw->pw_gid;
		}
		if (stat(pw->pw_dir, &st) == 0)
			setenv("HOME", pw->pw_dir, 1);
	}

	if (action == action_stop) {
		int i = run_stop_schedule();
		exit(i);
	}

	prog_status = do_findprocs();

	if (action == action_status)
		exit(prog_status);

	if (found) {
		if (quietmode <= 0)
			printf("%s already running.\n", execname ? execname : "process");
		exit(exitnodo);
	}
	if (testmode && quietmode <= 0) {
		printf("Would start %s ", startas);
		while (argc-- > 0)
			printf("%s ", *argv++);
		if (changeuser != NULL) {
			printf(" (as user %s[%d]", changeuser, runas_uid);
			if (changegroup != NULL)
				printf(", and group %s[%d])", changegroup, runas_gid);
			else
				printf(")");
		}
		if (changeroot != NULL)
			printf(" in directory %s", changeroot);
		if (nicelevel)
			printf(", and add %i to the priority", nicelevel);
		if (proc_sched)
			printf(", with scheduling policy %s with priority %i",
			       proc_sched->policy_name, proc_sched->priority);
		if (io_sched)
			printf(", with IO scheduling class %s with priority %i",
			       io_sched->policy_name, io_sched->priority);
		printf(".\n");
	}
	if (testmode)
		exit(0);
	if (quietmode < 0)
		printf("Starting %s...\n", startas);
	*--argv = startas;
	if (background) {
		/* Ok, we need to detach this process. */
		daemonize();

		devnull_fd = open("/dev/null", O_RDWR);
		if (devnull_fd < 0)
			fatal("unable to open '%s'", "/dev/null");
	}
	if (nicelevel) {
		errno = 0;
		if ((nice(nicelevel) == -1) && (errno != 0))
			fatal("unable to alter nice level by %i", nicelevel);
	}
	if (proc_sched)
		set_proc_schedule(proc_sched);
	if (io_sched)
		set_io_schedule(io_sched);
	if (umask_value >= 0)
		umask(umask_value);
	if (mpidfile && pidfile != NULL) {
		/* User wants _us_ to make the pidfile. */
		FILE *pidf = fopen(pidfile, "w");
		pid_t pidt = getpid();
		if (pidf == NULL)
			fatal("unable to open pidfile '%s' for writing",
			      pidfile);
		fprintf(pidf, "%d\n", pidt);
		if (fclose(pidf))
			fatal("unable to close pidfile '%s'", pidfile);
	}
	if (changeroot != NULL) {
		if (chdir(changeroot) < 0)
			fatal("unable to chdir() to %s", changeroot);
		if (chroot(changeroot) < 0)
			fatal("unable to chroot() to %s", changeroot);
	}
	if (chdir(changedir) < 0)
		fatal("unable to chdir() to %s", changedir);

	rgid = getgid();
	ruid = getuid();
	if (changegroup != NULL) {
		if (rgid != (gid_t)runas_gid)
			if (setgid(runas_gid))
				fatal("unable to set gid to %d", runas_gid);
	}
	if (changeuser != NULL) {
		/* We assume that if our real user and group are the same as
		 * the ones we should switch to, the supplementary groups
		 * will be already in place. */
		if (rgid != (gid_t)runas_gid || ruid != (uid_t)runas_uid)
			if (initgroups(changeuser, runas_gid))
				fatal("unable to set initgroups() with gid %d",
				      runas_gid);

		if (ruid != (uid_t)runas_uid)
			if (setuid(runas_uid))
				fatal("unable to set uid to %s", changeuser);
	}

	if (background) {
		int i;

		/* Set a default umask for dumb programs. */
		if (umask_value < 0)
			umask(022);

		dup2(devnull_fd, 0); /* stdin */
		dup2(devnull_fd, 1); /* stdout */
		dup2(devnull_fd, 2); /* stderr */

		 /* Now close all extra fds. */
		for (i = get_open_fd_max() - 1; i >= 3; --i)
			close(i);
	}
	execv(startas, argv);
	fatal("unable to start %s", startas);
}
