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
 * and --make-pidfile options, placed in public domain aswell.
 *
 * Port to OpenBSD by Sontri Tomo Huynh <huynh.29@osu.edu>
 *                 and Andreas Schuldei <andreas@schuldei.org>
 *
 * Changes by Ian Jackson: added --retry (and associated rearrangements).
 */

#include "config.h"

#if defined(linux) || (defined(__FreeBSD_kernel__) && defined(__GLIBC__))
#  define OSLinux
#elif defined(__GNU__)
#  define OSHURD
#elif defined(__sparc__)
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

#define MIN_POLL_INTERVAL 20000 /*us*/

#if defined(OSHURD)
#  include <hurd.h>
#  include <ps.h>
#endif

#if  defined(OSOpenBSD) || defined(OSFreeBSD) || defined(OSNetBSD)
#include <sys/param.h>
#include <sys/proc.h>
#include <sys/stat.h>
#include <sys/types.h>

#include <err.h>
#include <limits.h>
#endif
 
#ifdef HAVE_KVM_H
#include <kvm.h>
#include <sys/sysctl.h>
#include <sys/user.h>
#endif

#if defined(OShpux)
#include <sys/param.h>
#include <sys/pstat.h>
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <signal.h>
#include <sys/stat.h>
#include <dirent.h>
#include <sys/time.h>
#include <unistd.h>
#include <getopt.h>
#include <pwd.h>
#include <grp.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/termios.h>
#include <fcntl.h>
#include <limits.h>
#include <assert.h>
#include <ctype.h>

#ifdef HAVE_SYS_CDEFS_H
#include <sys/cdefs.h>
#endif

#ifdef HAVE_STDDEF_H
#include <stddef.h>
#endif

#ifdef HAVE_ERROR_H
#  include <error.h>
#endif

#if HAVE_C_ATTRIBUTE
# define CONSTANT __attribute__((constant))
# define PRINTFFORMAT(si, tc) __attribute__((format(printf,si,tc)))
# define NONRETURNING __attribute__((noreturn))
# define UNUSED __attribute__((unused))
# define NONRETURNPRINTFFORMAT(si, tc) __attribute__((format(printf,si,tc),noreturn))
#else
# define CONSTANT
# define PRINTFFORMAT(si, tc)
# define NONRETURNING
# define UNUSED
# define NONRETURNPRINTFFORMAT(si, tc)
#endif

static int testmode = 0;
static int quietmode = 0;
static int exitnodo = 1;
static int start = 0;
static int stop = 0;
static int background = 0;
static int mpidfile = 0;
static int signal_nr = 15;
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

static struct stat exec_stat;
#if defined(OSHURD)
static struct proc_stat_list *procset = NULL;
#endif


struct pid_list {
	struct pid_list *next;
	pid_t pid;
};

static struct pid_list *found = NULL;
static struct pid_list *killed = NULL;

struct schedule_item {
	enum { sched_timeout, sched_signal, sched_goto, sched_forever } type;
	int value; /* seconds, signal no., or index into array */
	/* sched_forever is only seen within parse_schedule and callees */
};

static int schedule_length;
static struct schedule_item *schedule = NULL;

static void *xmalloc(int size);
static void push(struct pid_list **list, pid_t pid);
static void do_help(void);
static void parse_options(int argc, char * const *argv);
static int pid_is_user(pid_t pid, uid_t uid);
static int pid_is_cmd(pid_t pid, const char *name);
static void check(pid_t pid);
static void do_pidfile(const char *name);
static void do_stop(int signal_nr, int quietmode,
		    int *n_killed, int *n_notkilled, int retry_nr);
#if defined(OSLinux) || defined(OShpux)
static int pid_is_exec(pid_t pid, const struct stat *esb);
#endif


#ifdef __GNUC__
static void fatal(const char *format, ...)
	NONRETURNPRINTFFORMAT(1, 2);
static void badusage(const char *msg)
	NONRETURNING;
#else
static void fatal(const char *format, ...);
static void badusage(const char *msg);
#endif

/* This next part serves only to construct the TVCALC macro, which
 * is used for doing arithmetic on struct timeval's.  It works like this:
 *   TVCALC(result, expression);
 * where result is a struct timeval (and must be an lvalue) and
 * expression is the single expression for both components.  In this
 * expression you can use the special values TVELEM, which when fed a
 * const struct timeval* gives you the relevant component, and
 * TVADJUST.  TVADJUST is necessary when subtracting timevals, to make
 * it easier to renormalise.  Whenver you subtract timeval elements,
 * you must make sure that TVADJUST is added to the result of the
 * subtraction (before any resulting multiplication or what have you).
 * TVELEM must be linear in TVADJUST.
 */
typedef long tvselector(const struct timeval*);
static long tvselector_sec(const struct timeval *tv) { return tv->tv_sec; }
static long tvselector_usec(const struct timeval *tv) { return tv->tv_usec; }
#define TVCALC_ELEM(result, expr, sec, adj)                           \
{								      \
  const long TVADJUST = adj;					      \
  long (*const TVELEM)(const struct timeval*) = tvselector_##sec;     \
  (result).tv_##sec = (expr);					      \
}
#define TVCALC(result,expr)					      \
do {								      \
  TVCALC_ELEM(result, expr, sec, (-1));				      \
  TVCALC_ELEM(result, expr, usec, (+1000000));			      \
  (result).tv_sec += (result).tv_usec / 1000000;		      \
  (result).tv_usec %= 1000000;					      \
} while(0)


static void
fatal(const char *format, ...)
{
	va_list arglist;

	fprintf(stderr, "%s: ", progname);
	va_start(arglist, format);
	vfprintf(stderr, format, arglist);
	va_end(arglist);
	fprintf(stderr, " (%s)\n", strerror (errno));
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


static void
xgettimeofday(struct timeval *tv)
{
	if (gettimeofday(tv,0) != 0)
		fatal("gettimeofday failed: %s", strerror(errno));
}

static void
daemonize(void)
{
	pid_t pid;

	if (quietmode < 0)
		printf("Detaching to start %s...", startas);

	pid = fork();
	if (pid < 0)
		fatal("Unable to do first fork.\n");
	else if (pid) /* Parent */
		_exit(0);

	/* Create a new session */
#ifdef HAVE_SETSID
	setsid();
#else
	setpgid(0, 0);
#endif

	pid = fork();
	if (pid < 0)
		fatal("Unable to do second fork.\n");
	else if (pid) /* Parent */
		_exit(0);

	if (quietmode < 0)
		printf("done.\n");
}

static void
push(struct pid_list **list, pid_t pid)
{
	struct pid_list *p;

	p = xmalloc(sizeof(*p));
	p->next = *list;
	p->pid = pid;
	*list = p;
}

static void
clear(struct pid_list **list)
{
	struct pid_list *here, *next;

	for (here = *list; here != NULL; here = next) {
		next = here->next;
		free(here);
	}

	*list = NULL;
}

static void
do_help(void)
{
	printf(
"start-stop-daemon %s for Debian - small and fast C version written by\n"
"Marek Michalkiewicz <marekm@i17linuxb.ists.pwr.wroc.pl>, public domain.\n"
"\n"
"Usage: start-stop-daemon [<option> ...] <command>\n"
"\n"
"Commands:\n"
"  -S|--start -- <argument> ...  start a program and pass <arguments> to it\n"
"  -K|--stop                     stop a program\n"
"  -H|--help                     print help information\n"
"  -V|--version                  print version\n"
"\n"
"Options (at least one of --exec|--pidfile|--user is required):\n"
"  -x|--exec <executable>        program to start/check if it is running\n"
"  -p|--pidfile <pid-file>       pid file to check\n"
"  -c|--chuid <name|uid[:group|gid]>\n"
"                                change to this user/group before starting\n"
"                                  process\n"
"  -u|--user <username>|<uid>    stop processes owned by this user\n"
"  -g|--group <group|gid>        run process as this group\n"
"  -n|--name <process-name>      stop processes with this name\n"
"  -s|--signal <signal>          signal to send (default TERM)\n"
"  -a|--startas <pathname>       program to start (default is <executable>)\n"
"  -r|--chroot <directory>       chroot to <directory> before starting\n"
"  -d|--chdir <directory>        change to <directory> (default is /)\n"
"  -N|--nicelevel <incr>         add incr to the process's nice level\n"
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
"Exit status:  0 = done      1 = nothing done (=> 0 if --oknodo)\n"
"              3 = trouble   2 = with --retry, processes wouldn't die\n",
	       VERSION);
}


static void
badusage(const char *msg)
{
	if (msg)
		fprintf(stderr, "%s: %s\n", progname, msg);
	fprintf(stderr, "Try `%s --help' for more information.\n", progname);
	exit(3);
}

struct sigpair {
	const char *name;
	int signal;
};

const struct sigpair siglist[] = {
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

static int parse_integer(const char *string, int *value_r) {
	unsigned long ul;
	char *ep;

	if (!string[0])
		return -1;

	ul= strtoul(string,&ep,10);
	if (ul > INT_MAX || *ep != '\0')
		return -1;

	*value_r= ul;
	return 0;
}

static int parse_signal(const char *signal_str, int *signal_nr)
{
	unsigned int i;

	if (parse_integer(signal_str, signal_nr) == 0)
		return 0;

	for (i = 0; i < sizeof (siglist) / sizeof (siglist[0]); i++) {
		if (strcmp (signal_str, siglist[i].name) == 0) {
			*signal_nr = siglist[i].signal;
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
parse_schedule_item(const char *string, struct schedule_item *item) {
	const char *after_hyph;

	if (!strcmp(string,"forever")) {
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
			 "-<signal-number>, <timeout> or `forever'");
	}
}

static void
parse_schedule(const char *schedule_str) {
	char item_buf[20];
	const char *slash;
	int count, repeatat;
	ptrdiff_t str_len;

	count = 0;
	for (slash = schedule_str; *slash; slash++)
		if (*slash == '/')
			count++;

	schedule_length = (count == 0) ? 4 : count+1;
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
		schedule[3]= schedule[1];
	} else {
		count = 0;
		repeatat = -1;
		while (schedule_str != NULL) {
			slash = strchr(schedule_str,'/');
			str_len = slash ? slash - schedule_str : strlen(schedule_str);
			if (str_len >= (ptrdiff_t)sizeof(item_buf))
				badusage("invalid schedule item: far too long"
					 " (you must delimit items with slashes)");
			memcpy(item_buf, schedule_str, str_len);
			item_buf[str_len] = 0;
			schedule_str = slash ? slash+1 : NULL;

			parse_schedule_item(item_buf, &schedule[count]);
			if (schedule[count].type == sched_forever) {
				if (repeatat >= 0)
					badusage("invalid schedule: `forever'"
						 " appears more than once");
				repeatat = count;
				continue;
			}
			count++;
		}
		if (repeatat >= 0) {
			schedule[count].type = sched_goto;
			schedule[count].value = repeatat;
			count++;
		}
		assert(count == schedule_length);
	}
}

static void
parse_options(int argc, char * const *argv)
{
	static struct option longopts[] = {
		{ "help",	  0, NULL, 'H'},
		{ "stop",	  0, NULL, 'K'},
		{ "start",	  0, NULL, 'S'},
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
		{ "umask",	  1, NULL, 'k'},
		{ "background",   0, NULL, 'b'},
		{ "make-pidfile", 0, NULL, 'm'},
 		{ "retry",        1, NULL, 'R'},
		{ "chdir",        1, NULL, 'd'},
		{ NULL,		0, NULL, 0}
	};
	const char *umask_str = NULL;
	const char *signal_str = NULL;
	const char *schedule_str = NULL;
	int c;

	for (;;) {
		c = getopt_long(argc, argv, "HKSVa:n:op:qr:s:tu:vx:c:N:k:bmR:g:d:",
				longopts, (int *) 0);
		if (c == -1)
			break;
		switch (c) {
		case 'H':  /* --help */
			do_help();
			exit(0);
		case 'K':  /* --stop */
			stop = 1;
			break;
		case 'S':  /* --start */
			start = 1;
			break;
		case 'V':  /* --version */
			printf("start-stop-daemon " VERSION "\n");
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
			/* we copy the string just in case we need the
			 * argument later. */
			changeuser = strdup(optarg);
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
			badusage(NULL);  /* message printed by getopt */
		}
	}

	if (signal_str != NULL) {
		if (parse_signal (signal_str, &signal_nr) != 0)
			badusage("signal value must be numeric or name"
				 " of signal (KILL, INT, ...)");
	}

	if (schedule_str != NULL) {
		parse_schedule(schedule_str);
	}

	if (umask_str != NULL) {
		if (parse_umask(umask_str, &umask_value) != 0)
			badusage("umask value must be a positive number");
	}

	if (start == stop)
		badusage("need one of --start or --stop");

	if (!execname && !pidfile && !userspec && !cmdname)
		badusage("need at least one of --exec, --pidfile, --user or --name");

	if (!startas)
		startas = execname;

	if (start && !startas)
		badusage("--start needs --exec or --startas");

	if (mpidfile && pidfile == NULL)
		badusage("--make-pidfile is only relevant with --pidfile");

	if (background && !start)
		badusage("--background is only relevant with --start");

}

#if defined(OSLinux)
static int
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
		return 0;

	lcontents[nread] = '\0';
	if (strcmp(lcontents + nread - strlen(deleted), deleted) == 0)
		lcontents[nread - strlen(deleted)] = '\0';

	if (stat(lcontents, &sb) != 0)
		return 0;

	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}


static int
pid_is_user(pid_t pid, uid_t uid)
{
	struct stat sb;
	char buf[32];

	sprintf(buf, "/proc/%d", pid);
	if (stat(buf, &sb) != 0)
		return 0;
	return (sb.st_uid == uid);
}


static int
pid_is_cmd(pid_t pid, const char *name)
{
	char buf[32];
	FILE *f;
	int c;

	sprintf(buf, "/proc/%d/stat", pid);
	f = fopen(buf, "r");
	if (!f)
		return 0;
	while ((c = getc(f)) != EOF && c != '(')
		;
	if (c != '(') {
		fclose(f);
		return 0;
	}
	/* this hopefully handles command names containing ')' */
	while ((c = getc(f)) != EOF && c == *name)
		name++;
	fclose(f);
	return (c == ')' && *name == '\0');
}
#endif /* OSLinux */


#if defined(OSHURD)
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
get_proc_stat (pid_t pid, ps_flags_t flags)
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

static int
pid_is_user(pid_t pid, uid_t uid)
{
	struct proc_stat *ps;

	ps = get_proc_stat(pid, PSTAT_OWNER_UID);
	return ps && proc_stat_owner_uid(ps) == uid;
}

static int
pid_is_cmd(pid_t pid, const char *name)
{
	struct proc_stat *ps;

	ps = get_proc_stat(pid, PSTAT_ARGS);
	return ps && !strcmp(proc_stat_args(ps), name);
}

static int
pid_is_running(pid_t pid)
{
	return get_proc_stat(pid, 0) != NULL;
}

#else /* !OSHURD */

static int
pid_is_running(pid_t pid)
{
	struct stat sb;
	char buf[32];

	sprintf(buf, "/proc/%d", pid);
	if (stat(buf, &sb) != 0) {
		if (errno!=ENOENT)
			fatal("Error stating %s: %s", buf, strerror(errno));
		return 0;
	}

	return 1;
}

#endif /* OSHURD */

static void
check(pid_t pid)
{
#if defined(OSLinux) || defined(OShpux)
	if (execname && !pid_is_exec(pid, &exec_stat))
#elif defined(OSHURD) || defined(OSFreeBSD) || defined(OSNetBSD)
    /* I will try this to see if it works */
	if (execname && !pid_is_cmd(pid, execname))
#endif
		return;
	if (userspec && !pid_is_user(pid, user_id))
		return;
	if (cmdname && !pid_is_cmd(pid, cmdname))
		return;
	if (start && !pid_is_running(pid))
		return;
	push(&found, pid);
}

static void
do_pidfile(const char *name)
{
	FILE *f;
	pid_t pid;

	f = fopen(name, "r");
	if (f) {
		if (fscanf(f, "%d", &pid) == 1)
			check(pid);
		fclose(f);
	} else if (errno != ENOENT)
		fatal("open pidfile %s: %s", name, strerror(errno));

}

/* WTA: this  needs to be an autoconf check for /proc/pid existance.
 */

#if defined(OSLinux) || defined (OSsunos)
static void
do_procinit(void)
{
	DIR *procdir;
	struct dirent *entry;
	int foundany;
	pid_t pid;

	procdir = opendir("/proc");
	if (!procdir)
		fatal("opendir /proc: %s", strerror(errno));

	foundany = 0;
	while ((entry = readdir(procdir)) != NULL) {
		if (sscanf(entry->d_name, "%d", &pid) != 1)
			continue;
		foundany++;
		check(pid);
	}
	closedir(procdir);
	if (!foundany)
		fatal("nothing in /proc - not mounted?");
}
#endif /* OSLinux */


#if defined(OSHURD)
static int
check_proc_stat (struct proc_stat *ps)
{
	check(ps->pid);
	return 0;
}

static void
do_procinit(void)
{
	if (!procset)
		init_procset();

	proc_stat_list_for_each (procset, check_proc_stat);
}
#endif /* OSHURD */


#ifdef HAVE_KVM_H
static int
pid_is_cmd(pid_t pid, const char *name)
{
        kvm_t *kd;
        int nentries, argv_len=0;
        struct kinfo_proc *kp;
        char  errbuf[_POSIX2_LINE_MAX], buf[_POSIX2_LINE_MAX];
	char  **pid_argv_p;
	char  *start_argv_0_p, *end_argv_0_p;
 
 
        kd = kvm_openfiles(NULL, NULL, NULL, O_RDONLY, errbuf);
        if (kd == 0)
                errx(1, "%s", errbuf);
        if ((kp = kvm_getprocs(kd, KERN_PROC_PID, pid, &nentries)) == 0)
                errx(1, "%s", kvm_geterr(kd));
	if ((pid_argv_p = kvm_getargv(kd, kp, argv_len)) == 0)
		errx(1, "%s", kvm_geterr(kd)); 

	start_argv_0_p = *pid_argv_p;
	/* find and compare string */
	  
	/* find end of argv[0] then copy and cut of str there. */
	if ((end_argv_0_p = strchr(*pid_argv_p, ' ')) == 0 ) 	
	/* There seems to be no space, so we have the command
	 * allready in its desired form. */
	  start_argv_0_p = *pid_argv_p;
	else {
	  /* Tests indicate that this never happens, since
	   * kvm_getargv itselfe cuts of tailing stuff. This is
	   * not what the manpage says, however. */
	  strncpy(buf, *pid_argv_p, (end_argv_0_p - start_argv_0_p));
	  buf[(end_argv_0_p - start_argv_0_p) + 1] = '\0';
	  start_argv_0_p = buf;
	}
        
	if (strlen(name) != strlen(start_argv_0_p))
               return 0;
        return (strcmp(name, start_argv_0_p) == 0) ? 1 : 0;
}
 
static int
pid_is_user(pid_t pid, uid_t uid)
{
	kvm_t *kd;
	int nentries;   /* Value not used */
	uid_t proc_uid;
	struct kinfo_proc *kp;
	char  errbuf[_POSIX2_LINE_MAX];


	kd = kvm_openfiles(NULL, NULL, NULL, O_RDONLY, errbuf);
	if (kd == 0)
		errx(1, "%s", errbuf);
	if ((kp = kvm_getprocs(kd, KERN_PROC_PID, pid, &nentries)) == 0)
		errx(1, "%s", kvm_geterr(kd));
	if (kp->kp_proc.p_cred )
		kvm_read(kd, (u_long)&(kp->kp_proc.p_cred->p_ruid),
			&proc_uid, sizeof(uid_t));
	else
		return 0;
	return (proc_uid == (uid_t)uid);
}

static int
pid_is_exec(pid_t pid, const char *name)
{
	kvm_t *kd;
	int nentries;
	struct kinfo_proc *kp;
	char errbuf[_POSIX2_LINE_MAX], *pidexec;

	kd = kvm_openfiles(NULL, NULL, NULL, O_RDONLY, errbuf);
	if (kd == 0)
		errx(1, "%s", errbuf);
	if ((kp = kvm_getprocs(kd, KERN_PROC_PID, pid, &nentries)) == 0)
		errx(1, "%s", kvm_geterr(kd));
	pidexec = (&kp->kp_proc)->p_comm;
	if (strlen(name) != strlen(pidexec))
		return 0;
	return (strcmp(name, pidexec) == 0) ? 1 : 0;
}


static void
do_procinit(void)
{
	/* Nothing to do */
}

#endif /* OSOpenBSD */


#if defined(OShpux)
static int
pid_is_user(pid_t pid, uid_t uid)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t) 0, (int) pid) < 0)
		return 0;
	return ((uid_t) pst.pst_uid == uid);
}

static int
pid_is_cmd(pid_t pid, const char *name)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t) 0, (int) pid) < 0)
		return 0;
	return (strcmp(pst.pst_ucomm, name) == 0);
}

static int
pid_is_exec(pid_t pid, const struct stat *esb)
{
	struct pst_status pst;

	if (pstat_getproc(&pst, sizeof(pst), (size_t) 0, (int) pid) < 0)
		return 0;
	return ((dev_t) pst.pst_text.psf_fsid.psfs_id == esb->st_dev
		&& (ino_t) pst.pst_text.psf_fileid == esb->st_ino);
}

static void
do_procinit(void)
{
	struct pst_status pst[10];
	int i, count;
	int idx = 0;

	while ((count = pstat_getproc(pst, sizeof(pst[0]), 10, idx)) > 0) {
                for (i = 0; i < count; i++)
			check(pst[i].pst_pid);
                idx = pst[count - 1].pst_idx + 1;
	}
}
#endif /* OShpux */


static void
do_findprocs(void)
{
	clear(&found);
	
	if (pidfile)
		do_pidfile(pidfile);
	else
		do_procinit();
}

/* return 1 on failure */
static void
do_stop(int signal_nr, int quietmode, int *n_killed, int *n_notkilled, int retry_nr)
{
	struct pid_list *p;

 	do_findprocs();
 
 	*n_killed = 0;
 	*n_notkilled = 0;
 
 	if (!found)
 		return;
 
 	clear(&killed);

	for (p = found; p; p = p->next) {
		if (testmode) {
			printf("Would send signal %d to %d.\n",
			       signal_nr, p->pid);
			(*n_killed)++;
		} else if (kill(p->pid, signal_nr) == 0) {
			push(&killed, p->pid);
 			(*n_killed)++;
		} else {
			printf("%s: warning: failed to kill %d: %s\n",
			       progname, p->pid, strerror(errno));
 			(*n_notkilled)++;
		}
	}
	if (quietmode < 0 && killed) {
 		printf("Stopped %s (pid", what_stop);
		for (p = killed; p; p = p->next)
			printf(" %d", p->pid);
 		putchar(')');
 		if (retry_nr > 0)
 			printf(", retry #%d", retry_nr);
 		printf(".\n");
	}
}


static void
set_what_stop(const char *str)
{
	strncpy(what_stop, str, sizeof(what_stop));
	what_stop[sizeof(what_stop)-1] = '\0';
}

static int
run_stop_schedule(void)
{
	int r, position, n_killed, n_notkilled, value, ratio, anykilled, retry_nr;
	struct timeval stopat, before, after, interval, maxinterval;

	if (testmode) {
		if (schedule != NULL) {
			printf("Ignoring --retry in test mode\n");
			schedule = NULL;
		}
	}

	if (cmdname)
		set_what_stop(cmdname);
	else if (execname)
		set_what_stop(execname);
	else if (pidfile)
		sprintf(what_stop, "process in pidfile `%.200s'", pidfile);
	else if (userspec)
		sprintf(what_stop, "process(es) owned by `%.200s'", userspec);
	else
		fatal("internal error, please report");

	anykilled = 0;
	retry_nr = 0;

	if (schedule == NULL) {
		do_stop(signal_nr, quietmode, &n_killed, &n_notkilled, 0);
		if (n_notkilled > 0 && quietmode <= 0)
			printf("%d pids were not killed\n", n_notkilled);
		if (n_killed)
			anykilled = 1;
		goto x_finished;
	}

	for (position = 0; position < schedule_length; ) {
		value= schedule[position].value;
		n_notkilled = 0;

		switch (schedule[position].type) {

		case sched_goto:
			position = value;
			continue;

		case sched_signal:
			do_stop(value, quietmode, &n_killed, &n_notkilled, retry_nr++);
			if (!n_killed)
				goto x_finished;
			else
				anykilled = 1;
			goto next_item;

		case sched_timeout:
 /* We want to keep polling for the processes, to see if they've exited,
  * or until the timeout expires.
  *
  * This is a somewhat complicated algorithm to try to ensure that we
  * notice reasonably quickly when all the processes have exited, but
  * don't spend too much CPU time polling.  In particular, on a fast
  * machine with quick-exiting daemons we don't want to delay system
  * shutdown too much, whereas on a slow one, or where processes are
  * taking some time to exit, we want to increase the polling
  * interval.
  *
  * The algorithm is as follows: we measure the elapsed time it takes
  * to do one poll(), and wait a multiple of this time for the next
  * poll.  However, if that would put us past the end of the timeout
  * period we wait only as long as the timeout period, but in any case
  * we always wait at least MIN_POLL_INTERVAL (20ms).  The multiple
  * (`ratio') starts out as 2, and increases by 1 for each poll to a
  * maximum of 10; so we use up to between 30% and 10% of the
  * machine's resources (assuming a few reasonable things about system
  * performance).
  */
			xgettimeofday(&stopat);
			stopat.tv_sec += value;
			ratio = 1;
			for (;;) {
				xgettimeofday(&before);
				if (timercmp(&before,&stopat,>))
					goto next_item;

				do_stop(0, 1, &n_killed, &n_notkilled, 0);
				if (!n_killed)
					goto x_finished;

				xgettimeofday(&after);

				if (!timercmp(&after,&stopat,<))
					goto next_item;

				if (ratio < 10)
					ratio++;

 TVCALC(interval,    ratio * (TVELEM(&after) - TVELEM(&before) + TVADJUST));
 TVCALC(maxinterval,          TVELEM(&stopat) - TVELEM(&after) + TVADJUST);

				if (timercmp(&interval,&maxinterval,>))
					interval = maxinterval;

				if (interval.tv_sec == 0 &&
				    interval.tv_usec <= MIN_POLL_INTERVAL)
				        interval.tv_usec = MIN_POLL_INTERVAL;

				r = select(0,0,0,0,&interval);
				if (r < 0 && errno != EINTR)
					fatal("select() failed for pause: %s",
					      strerror(errno));
			}

		default:
			assert(!"schedule[].type value must be valid");

		}

	next_item:
		position++;
	}

	if (quietmode <= 0)
		printf("Program %s, %d process(es), refused to die.\n",
		       what_stop, n_killed);

	return 2;

x_finished:
	if (!anykilled) {
		if (quietmode <= 0)
			printf("No %s found running; none killed.\n", what_stop);
		return exitnodo;
	} else {
		return 0;
	}
}


int
main(int argc, char **argv)
{
	int devnull_fd = -1;
#ifdef HAVE_TIOCNOTTY
	int tty_fd = -1;
#endif
	progname = argv[0];

	parse_options(argc, argv);
	argc -= optind;
	argv += optind;

	if (execname) {
		char *fullexecname;

		if (changeroot) {
			int fullexecname_len = strlen(changeroot) + 1 +
					       strlen(execname) + 1;

			fullexecname = xmalloc(fullexecname_len);
			snprintf(fullexecname, fullexecname_len, "%s/%s",
				 changeroot, execname);
		} else
			fullexecname = execname;

		if (stat(fullexecname, &exec_stat))
			fatal("stat %s: %s", fullexecname, strerror(errno));

		if (fullexecname != execname)
			free(fullexecname);
	}

	if (userspec && sscanf(userspec, "%d", &user_id) != 1) {
		struct passwd *pw;

		pw = getpwnam(userspec);
		if (!pw)
			fatal("user `%s' not found\n", userspec);

		user_id = pw->pw_uid;
	}

	if (changegroup && sscanf(changegroup, "%d", &runas_gid) != 1) {
		struct group *gr = getgrnam(changegroup);
		if (!gr)
			fatal("group `%s' not found\n", changegroup);
		runas_gid = gr->gr_gid;
	}
	if (changeuser && sscanf(changeuser, "%d", &runas_uid) != 1) {
		struct passwd *pw = getpwnam(changeuser);
		if (!pw)
			fatal("user `%s' not found\n", changeuser);
		runas_uid = pw->pw_uid;
		if (changegroup == NULL) { /* pass the default group of this user */
			changegroup = ""; /* just empty */
			runas_gid = pw->pw_gid;
		}
		if (access(pw->pw_dir, F_OK) == 0)
			setenv("HOME", pw->pw_dir, 1);
	}

	if (stop) {
		int i = run_stop_schedule();
		exit(i);
	}

	do_findprocs();

	if (found) {
		if (quietmode <= 0)
			printf("%s already running.\n", execname ? execname : "process");
		exit(exitnodo);
	}
	if (testmode) {
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
		printf(".\n");
		exit(0);
	}
	if (quietmode < 0)
		printf("Starting %s...\n", startas);
	*--argv = startas;
	if (background) { /* ok, we need to detach this process */
		daemonize();

#ifdef HAVE_TIOCNOTTY
		tty_fd=open("/dev/tty", O_RDWR);
#endif
		devnull_fd=open("/dev/null", O_RDWR);
	}
	if (nicelevel) {
		errno=0;
		if ((nice(nicelevel)==-1) && (errno!=0))
			fatal("Unable to alter nice level by %i: %s", nicelevel,
				strerror(errno));
	}
	if (umask_value >= 0)
		umask(umask_value);
	if (mpidfile && pidfile != NULL) { /* user wants _us_ to make the pidfile :) */
		FILE *pidf = fopen(pidfile, "w");
		pid_t pidt = getpid();
		if (pidf == NULL)
			fatal("Unable to open pidfile `%s' for writing: %s", pidfile,
				strerror(errno));
		fprintf(pidf, "%d\n", pidt);
		fclose(pidf);
	}
	if (changeroot != NULL) {
		if (chdir(changeroot) < 0)
			fatal("Unable to chdir() to %s", changeroot);
		if (chroot(changeroot) < 0)
			fatal("Unable to chroot() to %s", changeroot);
	}
	if (chdir(changedir) < 0)
		fatal("Unable to chdir() to %s", changedir);
	if (changeuser != NULL) {
 		if (setgid(runas_gid))
 			fatal("Unable to set gid to %d", runas_gid);
		if (initgroups(changeuser, runas_gid))
			fatal("Unable to set initgroups() with gid %d", runas_gid);
		if (setuid(runas_uid))
			fatal("Unable to set uid to %s", changeuser);
	}
	if (background) { /* continue background setup */
		int i;
#ifdef HAVE_TIOCNOTTY
		 /* change tty */
		ioctl(tty_fd, TIOCNOTTY, 0);
		close(tty_fd);
#endif
		if (umask_value < 0)
			umask(022); /* set a default for dumb programs */
		dup2(devnull_fd,0); /* stdin */
		dup2(devnull_fd,1); /* stdout */
		dup2(devnull_fd,2); /* stderr */
#if defined(OShpux)
		 /* now close all extra fds */
		for (i=sysconf(_SC_OPEN_MAX)-1; i>=3; --i) close(i);
#else
		 /* now close all extra fds */
		for (i=getdtablesize()-1; i>=3; --i) close(i);
#endif
	}
	execv(startas, argv);
	fatal("Unable to start %s: %s", startas, strerror(errno));
}

