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
 */

#include "config.h"
#define _GNU_SOURCE

#ifdef linux
#define OSLinux
#endif

#ifdef __GNU__
#define OSHURD
#endif

#ifdef HAVE_HURH_H
#include <hurd.h>
#endif
#ifdef HAVE_PS_H
#include <ps.h>
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <signal.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#include <getopt.h>
#include <pwd.h>
#include <grp.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <fcntl.h>

#ifdef HAVE_ERROR_H
#include <error.h>
#endif
#ifdef HURD_IHASH_H
#include <hurd/ihash.h>
#endif

static int testmode = 0;
static int quietmode = 0;
static int exitnodo = 1;
static int start = 0;
static int stop = 0;
static int background = 0;
static int mpidfile = 0;
static int signal_nr = 15;
static const char *signal_str = NULL;
static int user_id = -1;
static int runas_uid = -1;
static int runas_gid = -1;
static const char *userspec = NULL;
static char *changeuser = NULL;
static char *changegroup = NULL;
static const char *cmdname = NULL;
static char *execname = NULL;
static char *startas = NULL;
static const char *pidfile = NULL;
static const char *progname = "";

static struct stat exec_stat;
#if defined(OSHURD)
static struct ps_context *context;
static struct proc_stat_list *procset;
#endif


struct pid_list {
	struct pid_list *next;
	int pid;
};

static struct pid_list *found = NULL;
static struct pid_list *killed = NULL;

static void *xmalloc(int size);
static void push(struct pid_list **list, int pid);
static void do_help(void);
static void parse_options(int argc, char * const *argv);
static int pid_is_user(int pid, int uid);
static int pid_is_cmd(int pid, const char *name);
static void check(int pid);
static void do_pidfile(const char *name);
static int do_stop(void);
#if defined(OSLinux)
static int pid_is_exec(int pid, const struct stat *esb);
#endif
static void do_psinit(void);


#ifdef __GNUC__
static void fatal(const char *format, ...)
	__attribute__((noreturn, format(printf, 1, 2)));
static void badusage(const char *msg)
	__attribute__((noreturn));
#else
static void fatal(const char *format, ...);
static void badusage(const char *msg);
#endif

static void
fatal(const char *format, ...)
{
	va_list arglist;

	fprintf(stderr, "%s: ", progname);
	va_start(arglist, format);
	vfprintf(stderr, format, arglist);
	va_end(arglist);
	putc('\n', stderr);
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
push(struct pid_list **list, int pid)
{
	struct pid_list *p;

	p = xmalloc(sizeof(*p));
	p->next = *list;
	p->pid = pid;
	*list = p;
}


static void
do_help(void)
{
	printf("\
start-stop-daemon for Debian Linux - small and fast C version written by\n\
Marek Michalkiewicz <marekm@i17linuxb.ists.pwr.wroc.pl>, public domain.\n"
VERSION "\n\
\n\
Usage:
  start-stop-daemon -S|--start options ... -- arguments ...\n\
  start-stop-daemon -K|--stop options ...\n\
  start-stop-daemon -H|--help\n\
  start-stop-daemon -V|--version\n\
\n\
Options (at least one of --exec|--pidfile|--user is required):
  -x|--exec <executable>        program to start/check if it is running\n\
  -p|--pidfile <pid-file>       pid file to check\n\
  -c|--chuid <name|uid[:group|gid]>
  		change to this user/group before starting process\n\
  -u|--user <username>|<uid>    stop processes owned by this user\n\
  -n|--name <process-name>      stop processes with this name\n\
  -s|--signal <signal>          signal to send (default TERM)\n\
  -a|--startas <pathname>       program to start (default is <executable>)\n\
  -b|--background               force the process to detach\n\
  -m|--make-pidfile             create the pidfile before starting\n\
  -t|--test                     test mode, don't do anything\n\
  -o|--oknodo                   exit status 0 (not 1) if nothing done\n\
  -q|--quiet                    be more quiet\n\
  -v|--verbose                  be more verbose\n\
\n\
Exit status:  0 = done  1 = nothing done (=> 0 if --oknodo)  2 = trouble\n");
}


static void
badusage(const char *msg)
{
	if (msg)
		fprintf(stderr, "%s: %s\n", progname, msg);
	fprintf(stderr, "Try `%s --help' for more information.\n", progname);
	exit(2);
}

struct sigpair {
	const char *name;
	int signal;
};

const struct sigpair siglist[] = {
	{ "ABRT", SIGABRT },
	{ "ALRM", SIGALRM },
	{ "FPE", SIGFPE },
	{ "HUP", SIGHUP },
	{ "ILL", SIGILL },
	{ "INT", SIGINT },
	{ "KILL", SIGKILL },
	{ "PIPE", SIGPIPE },
	{ "QUIT", SIGQUIT },
	{ "SEGV", SIGSEGV },
	{ "TERM", SIGTERM },
	{ "USR1", SIGUSR1 },
	{ "USR2", SIGUSR2 },
	{ "CHLD", SIGCHLD },
	{ "CONT", SIGCONT },
	{ "STOP", SIGSTOP },
	{ "TSTP", SIGTSTP },
	{ "TTIN", SIGTTIN },
	{ "TTOU", SIGTTOU }
};

static int parse_signal (const char *signal_str, int *signal_nr)
{
	int i;
	for (i = 0; i < sizeof (siglist) / sizeof (siglist[0]); i++) {
		if (strcmp (signal_str, siglist[i].name) == 0) {
			*signal_nr = siglist[i].signal;
			return 0;
		}
	}
	return -1;
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
		{ "verbose",	  0, NULL, 'v'},
		{ "exec",	  1, NULL, 'x'},
		{ "chuid",	  1, NULL, 'c'},
		{ "background",   0, NULL, 'b'},
		{ "make-pidfile", 0, NULL, 'm'},
		{ NULL,		0, NULL, 0}
	};
	int c;

	for (;;) {
		c = getopt_long(argc, argv, "HKSVa:n:op:qs:tu:vx:c:bm",
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
		case 'b':  /* --background */
			background = 1;
			break;
		case 'm':  /* --make-pidfile */
			mpidfile = 1;
			break;
		default:
			badusage(NULL);  /* message printed by getopt */
		}
	}

	if (signal_str != NULL) {
		if (sscanf (signal_str, "%d", &signal_nr) != 1) {
			if (parse_signal (signal_str, &signal_nr) != 0) {
				badusage ("--signal takes a numeric argument or name of signal (KILL, INTR, ...)");
			}
		}	
	}

	if (start == stop)
		badusage("need one of --start or --stop");

	if (!execname && !pidfile && !userspec)
		badusage("need at least one of --exec, --pidfile or --user");

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
pid_is_exec(int pid, const struct stat *esb)
{
	struct stat sb;
	char buf[32];

	sprintf(buf, "/proc/%d/exe", pid);
	if (stat(buf, &sb) != 0)
		return 0;
	return (sb.st_dev == esb->st_dev && sb.st_ino == esb->st_ino);
}


static int
pid_is_user(int pid, int uid)
{
	struct stat sb;
	char buf[32];

	sprintf(buf, "/proc/%d", pid);
	if (stat(buf, &sb) != 0)
		return 0;
	return (sb.st_uid == uid);
}


static int
pid_is_cmd(int pid, const char *name)
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
static int
pid_is_user(int pid, int uid)
{
   struct stat sb;
   char buf[32];
   struct proc_stat *pstat;

   sprintf(buf, "/proc/%d", pid);
   if (stat(buf, &sb) != 0)
       return 0;
   return (sb.st_uid == uid);
   pstat = proc_stat_list_pid_proc_stat (procset, pid);
   if (pstat == NULL)
       fatal ("Error getting process information: NULL proc_stat struct");
   proc_stat_set_flags (pstat, PSTAT_PID | PSTAT_OWNER_UID);
   return (pstat->owner_uid == uid);
}

static int
pid_is_cmd(int pid, const char *name)
{
   struct proc_stat *pstat;
   pstat = proc_stat_list_pid_proc_stat (procset, pid);
   if (pstat == NULL)
       fatal ("Error getting process information: NULL proc_stat struct");
   proc_stat_set_flags (pstat, PSTAT_PID | PSTAT_ARGS);
   return (!strcmp (name, pstat->args));
}
#endif /* OSHURD */



static void
check(int pid)
{
#if defined(OSLinux)
	if (execname && !pid_is_exec(pid, &exec_stat))
#elif defined(OSHURD)
    /* I will try this to see if it works */
	if (execname && !pid_is_cmd(pid, execname))
#endif
		return;
	if (userspec && !pid_is_user(pid, user_id))
		return;
	if (cmdname && !pid_is_cmd(pid, cmdname))
		return;
	push(&found, pid);
}


static void
do_pidfile(const char *name)
{
	FILE *f;
	int pid;

	f = fopen(name, "r");
	if (f) {
		if (fscanf(f, "%d", &pid) == 1)
			check(pid);
		fclose(f);
	}
}


#if defined(OSLinux)
static void
do_procinit(void)
{
	DIR *procdir;
	struct dirent *entry;
	int foundany, pid;

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
error_t
check_all (void *ptr)
{
   struct proc_stat *pstat = ptr;

   check (pstat->pid);
   return (0);
}

static void
do_psinit(void)
   error_t err;

   err = ps_context_create (getproc (), &context);
   if (err)
       error (1, err, "ps_context_create");

   err = proc_stat_list_create (context, &procset);
   if (err)
       error (1, err, "proc_stat_list_create");

   err = proc_stat_list_add_all (procset, 0, 0);
   if (err)
       error (1, err, "proc_stat_list_add_all");

   /* Check all pids */
   ihash_iterate (context->procs, check_all);
}
#endif /* OSHURD */

/* return 1 on failure */
static int
do_stop(void)
{
	char what[1024];
	struct pid_list *p;
	int retval = 0;

	if (cmdname)
		strcpy(what, cmdname);
	else if (execname)
		strcpy(what, execname);
	else if (pidfile)
		sprintf(what, "process in pidfile `%s'", pidfile);
	else if (userspec)
		sprintf(what, "process(es) owned by `%s'", userspec);
	else
		fatal("internal error, please report");

	if (!found) {
		if (quietmode <= 0)
			printf("No %s found running; none killed.\n", what);
		exit(exitnodo);
	}
	for (p = found; p; p = p->next) {
		if (testmode)
			printf("Would send signal %d to %d.\n",
			       signal_nr, p->pid);
		else if (kill(p->pid, signal_nr) == 0)
			push(&killed, p->pid);
		else {
			printf("%s: warning: failed to kill %d: %s\n",
			       progname, p->pid, strerror(errno));
			retval += 1;
		}
	}
	if (quietmode < 0 && killed) {
		printf("Stopped %s (pid", what);
		for (p = killed; p; p = p->next)
			printf(" %d", p->pid);
		printf(").\n");
	}
	return retval;
}


int
main(int argc, char **argv)
{
	progname = argv[0];

	parse_options(argc, argv);
	argc -= optind;
	argv += optind;

	if (execname && stat(execname, &exec_stat))
		fatal("stat %s: %s", execname, strerror(errno));

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
	}

	if (pidfile)
		do_pidfile(pidfile);
	else
		do_procinit();

	if (stop) {
		int i = do_stop();
		if (i) {
			if (quietmode <= 0)
				printf("%d pids were not killed\n", i);
			exit(1);
		}
		exit(0);
	}

	if (found) {
		if (quietmode <= 0)
			printf("%s already running.\n", execname);
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
		printf(".\n");
		exit(0);
	}
	if (quietmode < 0)
		printf("Starting %s...\n", startas);
	*--argv = startas;
	if (changeuser != NULL) {
 		if (setgid(runas_gid))
 			fatal("Unable to set gid to %d", runas_gid);
		if (initgroups(changeuser, runas_gid))
			fatal("Unable to set initgroups() with gid %d", runas_gid);
		if (setuid(runas_uid))
			fatal("Unable to set uid to %s", changeuser);
	}
	
	if (background) { /* ok, we need to detach this process */
		int i, fd;
		if (quietmode < 0)
			printf("Detatching to start %s...", startas);
		i = fork();
		if (i<0) {
			fatal("Unable to fork.\n");
		}
		if (i) { /* parent */
			if (quietmode < 0)
				printf("done.\n");
			exit(0);
		}
		 /* child continues here */
		 /* now close all extra fds */
		for (i=getdtablesize()-1; i>=0; --i) close(i);
		 /* change tty */
		fd = open("/dev/tty", O_RDWR);
		ioctl(fd, TIOCNOTTY, 0);
		close(fd);
		chdir("/");
		umask(022); /* set a default for dumb programs */
		setpgrp();  /* set the process group */
		fd=open("/dev/null", O_RDWR); /* stdin */
		dup(fd); /* stdout */
		dup(fd); /* stderr */
	}
	if (mpidfile && pidfile != NULL) { /* user wants _us_ to make the pidfile :) */
		FILE *pidf = fopen(pidfile, "w");
		pid_t pidt = getpid();
		if (pidf == NULL)
			fatal("Unable to open pidfile `%s' for writing: %s", pidfile,
				strerror(errno));
		fprintf(pidf, "%d\n", pidt);
		fclose(pidf);
	}
	execv(startas, argv);
	fatal("Unable to start %s: %s", startas, strerror(errno));
}
