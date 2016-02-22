/*
 * update-alternatives
 *
 * Copyright © 1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2000-2002 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2006-2015 Guillem Jover <guillem@debian.org>
 * Copyright © 2008 Pierre Habouzit <madcoder@debian.org>
 * Copyright © 2009-2010 Raphaël Hertzog <hertzog@debian.org>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>
#include <time.h>
#include <setjmp.h>
#include <assert.h>
#include <locale.h>
#include <ctype.h>
#include <limits.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>

/* Global variables: */

#define PROGNAME "update-alternatives"

static const char *altdir = SYSCONFDIR "/alternatives";
static const char *admdir;

static const char *prog_path = "update-alternatives";

/* Action to perform */
static const char *action = NULL;
static const char *log_file = LOGDIR "/alternatives.log";
/* Skip alternatives properly configured in auto mode (for --config) */
static int opt_skip_auto = 0;
static int opt_verbose = 0;
static int opt_force = 0;

#define ALT_TMP_EXT ".dpkg-tmp"

/*
 * Functions.
 */

static void
version(void)
{
	printf(_("Debian %s version %s.\n"), PROGNAME, VERSION);
	printf("\n");

	printf(_(
"This is free software; see the GNU General Public License version 2 or\n"
"later for copying conditions. There is NO warranty.\n"));
}

static void
usage(void)
{
	printf(_(
"Usage: %s [<option> ...] <command>\n"
"\n"), PROGNAME);

	printf(_(
"Commands:\n"
"  --install <link> <name> <path> <priority>\n"
"    [--slave <link> <name> <path>] ...\n"
"                           add a group of alternatives to the system.\n"
"  --remove <name> <path>   remove <path> from the <name> group alternative.\n"
"  --remove-all <name>      remove <name> group from the alternatives system.\n"
"  --auto <name>            switch the master link <name> to automatic mode.\n"
"  --display <name>         display information about the <name> group.\n"
"  --query <name>           machine parseable version of --display <name>.\n"
"  --list <name>            display all targets of the <name> group.\n"
"  --get-selections         list master alternative names and their status.\n"
"  --set-selections         read alternative status from standard input.\n"
"  --config <name>          show alternatives for the <name> group and ask the\n"
"                           user to select which one to use.\n"
"  --set <name> <path>      set <path> as alternative for <name>.\n"
"  --all                    call --config on all alternatives.\n"
"\n"));

	printf(_(
"<link> is the symlink pointing to %s/<name>.\n"
"  (e.g. /usr/bin/pager)\n"
"<name> is the master name for this link group.\n"
"  (e.g. pager)\n"
"<path> is the location of one of the alternative target files.\n"
"  (e.g. /usr/bin/less)\n"
"<priority> is an integer; options with higher numbers have higher priority in\n"
"  automatic mode.\n"
"\n"), altdir);

	printf(_(
"Options:\n"
"  --altdir <directory>     change the alternatives directory.\n"
"  --admindir <directory>   change the administrative directory.\n"
"  --log <file>             change the log file.\n"
"  --force                  allow replacing files with alternative links.\n"
"  --skip-auto              skip prompt for alternatives correctly configured\n"
"                           in automatic mode (relevant for --config only)\n"
"  --verbose                verbose operation, more output.\n"
"  --quiet                  quiet operation, minimal output.\n"
"  --help                   show this help message.\n"
"  --version                show the version.\n"
));
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1)
error(char const *fmt, ...)
{
	va_list args;

	fprintf(stderr, "%s: %s: ", PROGNAME, _("error"));
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, "\n");
	exit(2);
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1)
syserr(char const *fmt, ...)
{
	va_list args;

	fprintf(stderr, "%s: %s: ", PROGNAME, _("error"));
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, ": %s\n", strerror(errno));
	exit(2);
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1)
badusage(char const *fmt, ...)
{
	va_list args;

	fprintf(stderr, "%s: ", PROGNAME);
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, "\n\n");
	fprintf(stderr, _("Use '%s --help' for program usage information."),
	        PROGNAME);
	fprintf(stderr, "\n");
	exit(2);
}

static void DPKG_ATTR_PRINTF(1)
warning(char const *fmt, ...)
{
	va_list args;

	if (opt_verbose < 0)
		return;

	fprintf(stderr, "%s: %s: ", PROGNAME, _("warning"));
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, "\n");
}

static void DPKG_ATTR_PRINTF(1)
debug(char const *fmt, ...)
{
#if 0
	va_list args;

	fprintf(stderr, "DEBUG: ");
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, "\n");
#endif
}

static void DPKG_ATTR_PRINTF(1)
verbose(char const *fmt, ...)
{
	va_list args;

	if (opt_verbose < 1)
		return;

	printf("%s: ", PROGNAME);
	va_start(args, fmt);
	vprintf(fmt, args);
	va_end(args);
	printf("\n");
}

static void DPKG_ATTR_PRINTF(1)
info(char const *fmt, ...)
{
	va_list args;

	if (opt_verbose < 0)
		return;

	printf("%s: ", PROGNAME);
	va_start(args, fmt);
	vprintf(fmt, args);
	va_end(args);
	printf("\n");
}

static void DPKG_ATTR_PRINTF(1)
pr(char const *fmt, ...)
{
	va_list args;

	va_start(args, fmt);
	vprintf(fmt, args);
	va_end(args);
	printf("\n");
}

static void *
xmalloc(size_t size)
{
	void *ptr;

	ptr = malloc(size);
	if (!ptr)
		error(_("malloc failed (%zu bytes)"), size);

	return ptr;
}

static char *
xstrdup(const char *str)
{
	char *new_str;

	if (!str)
		return NULL;

	new_str = strdup(str);
	if (!new_str)
		error(_("failed to allocate memory"));

	return new_str;
}

static char *
areadlink(const char *linkname)
{
	struct stat st;
	char *buf;
	ssize_t size;

	/* Allocate required memory to store the value of the symlink */
	if (lstat(linkname, &st))
		return NULL;

	if (!S_ISLNK(st.st_mode)) {
		errno = EINVAL;
		return NULL;
	}

	buf = xmalloc(st.st_size + 1);

	/* Read it and terminate the string properly */
	size = readlink(linkname, buf, st.st_size);
	if (size == -1) {
		int saved_errno = errno;

		free(buf);
		errno = saved_errno;

		return NULL;
	}
	buf[size] = '\0';

	return buf;
}

static char *
xreadlink(const char *linkname)
{
	char *buf;

	buf = areadlink(linkname);
	if (buf == NULL)
		syserr(_("unable to read link '%.255s'"), linkname);

	return buf;
}

static char * DPKG_ATTR_VPRINTF(1)
xvasprintf(const char *fmt, va_list args)
{
	char *str;

	if (vasprintf(&str, fmt, args) < 0)
		error(_("failed to allocate memory"));

	return str;
}

static char * DPKG_ATTR_PRINTF(1)
xasprintf(const char *fmt, ...)
{
	va_list args;
	char *str;

	va_start(args, fmt);
	str = xvasprintf(fmt, args);
	va_end(args);

	return str;
}

static void
set_action(const char *new_action)
{
	if (action)
		badusage(_("two commands specified: --%s and --%s"),
		         action, new_action);
	action = new_action;
}

static const char *
admindir_init(void)
{
	const char *basedir, *basedir_env;

	/* Try to get the admindir from an environment variable, usually set
	 * by the system package manager. */
	basedir_env = getenv(ADMINDIR_ENVVAR);
	if (basedir_env)
		basedir = basedir_env;
	else
		basedir = ADMINDIR;

	return xasprintf("%s/%s", basedir, "alternatives");
}

static FILE *fh_log = NULL;

static void DPKG_ATTR_PRINTF(1)
log_msg(const char *fmt, ...)
{
	va_list args;

	if (fh_log == NULL) {
		fh_log = fopen(log_file, "a");
		if (fh_log == NULL && errno != EACCES)
			syserr(_("cannot append to '%s'"), log_file);
	}

	if (fh_log) {
		char timestamp[64];
		time_t now;

		time(&now);
		strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S",
		         localtime(&now));
		fprintf(fh_log, "%s %s: ", PROGNAME, timestamp);
		va_start(args, fmt);
		vfprintf(fh_log, fmt, args);
		va_end(args);
		fprintf(fh_log, "\n");
	}
}

static int
spawn(const char *prog, const char *args[])
{
	pid_t pid, dead_pid;
	int status;

	pid = fork();
	if (pid == -1)
		error(_("fork failed"));
	if (pid == 0) {
		execvp(prog, (char *const *)args);
		syserr(_("unable to execute %s (%s)"), prog, prog);
	}
	while ((dead_pid = waitpid(pid, &status, 0)) == -1 && errno == EINTR) ;
	if (dead_pid != pid)
		error(_("wait for subprocess %s failed"), prog);

	return status;
}

static bool
rename_mv(const char *src, const char *dst)
{
	const char *args[] = { "mv", src, dst, NULL };
	int rc;

	if (rename(src, dst) == 0)
		return true;
	if (errno == ENOENT)
		return false;

	rc = spawn("mv", args);
	if (WIFEXITED(rc) && WEXITSTATUS(rc) == 0)
		return true;

	return false;
}

static void
checked_symlink(const char *filename, const char *linkname)
{
	if (symlink(filename, linkname))
		syserr(_("error creating symbolic link '%.255s'"), linkname);
}

static void
checked_mv(const char *src, const char *dst)
{
	if (!rename_mv(src, dst))
		syserr(_("unable to install '%.250s' as '%.250s'"), src, dst);
}

static void
checked_rm(const char *f)
{
	if (!unlink(f))
		return;

	if (errno != ENOENT)
		syserr(_("unable to remove '%s'"), f);
}

static void DPKG_ATTR_PRINTF(1)
checked_rm_args(const char *fmt, ...)
{
	va_list args;
	char *path;

	va_start(args, fmt);
	path = xvasprintf(fmt, args);
	va_end(args);

	checked_rm(path);
	free(path);
}

/*
 * OBJECTS
 */

struct fileset {
	struct fileset *next;

	char *master_file;
	int priority;

	struct slave_file {
		struct slave_file *next;
		char *name;
		char *file;
	} *slaves;
};

static struct fileset *
fileset_new(const char *master_file, int prio)
{
	struct fileset *fs;

	fs = xmalloc(sizeof(*fs));
	fs->next = NULL;
	fs->master_file = xstrdup(master_file);
	fs->priority = prio;
	fs->slaves = NULL;

	return fs;
}

static void
fileset_free(struct fileset *fs)
{
	struct slave_file *slave, *next;

	free(fs->master_file);
	for (slave = fs->slaves; slave; slave = next) {
		next = slave->next;
		free(slave->name);
		free(slave->file);
		free(slave);
	}
	free(fs);
}

/* name and file must be allocated with malloc */
static void
fileset_add_slave(struct fileset *fs, char *name, char *file)
{
	struct slave_file *sl, *cur, *prev = NULL;

	/* Replace existing first */
	for (cur = fs->slaves; cur; cur = cur->next) {
		if (strcmp(cur->name, name) == 0) {
			free(cur->file);
			cur->file = xstrdup(file);
			return;
		}
		prev = cur;
	}

	/* Otherwise add new at the end */
	sl = xmalloc(sizeof(*sl));
	sl->next = NULL;
	sl->name = name;
	sl->file = file;
	if (prev)
		prev->next = sl;
	else
		fs->slaves = sl;
}

static const char *
fileset_get_slave(struct fileset *fs, const char *name)
{
	struct slave_file *slave;

	for (slave = fs->slaves; slave; slave = slave->next) {
		if (strcmp(slave->name, name) == 0)
			return slave->file;
	}

	return NULL;
}

static bool
fileset_has_slave(struct fileset *fs, const char *name)
{
	const char *file = fileset_get_slave(fs, name);

	if (file == NULL)
		return false;

	return file[0] != '\0';
}

static bool
fileset_can_install_slave(struct fileset *fs, const char *slave_name)
{
	struct stat st;

	/* Decide whether the slave alternative must be setup */
	if (fileset_has_slave(fs, slave_name)) {
		const char *slave = fileset_get_slave(fs, slave_name);

		errno = 0;
		if (stat(slave, &st) == -1 && errno != ENOENT)
			syserr(_("cannot stat file '%s'"), slave);
		if (errno == 0)
			return true;
	}

	return false;
}

struct slave_link {
	struct slave_link *next;
	char *name;
	char *link;
	bool updated;
};

struct commit_operation {
	struct commit_operation *next;

	enum opcode {
		OPCODE_NOP,
		OPCODE_RM,
		OPCODE_MV,
	} opcode;

	char *arg_a;
	char *arg_b;
};

enum alternative_update_reason {
	ALT_UPDATE_NO,
	ALT_UPDATE_SLAVE_CHANGED,
	ALT_UPDATE_LINK_BROKEN,
};

struct alternative {
	char *master_name;
	char *master_link;
	char *current;

	enum alternative_status {
		ALT_ST_UNKNOWN,
		ALT_ST_AUTO,
		ALT_ST_MANUAL,
	} status;

	struct slave_link *slaves;
	struct fileset *choices;

	struct commit_operation *commit_ops;

	int ref_count;
	bool modified;
	bool known_current;
};

static void
slave_link_free(struct slave_link *slave)
{
	free(slave->name);
	free(slave->link);
	free(slave);
}

static void
commit_operation_free(struct commit_operation *commit_op)
{
	free(commit_op->arg_a);
	free(commit_op->arg_b);
	free(commit_op);
}

static struct alternative *
alternative_new(const char *name)
{
	struct alternative *alt;

	alt = xmalloc(sizeof(*alt));
	alt->master_name = xstrdup(name);
	alt->master_link = NULL;
	alt->current = NULL;
	alt->status = ALT_ST_UNKNOWN;
	alt->slaves = NULL;
	alt->choices = NULL;
	alt->commit_ops = NULL;
	alt->modified = false;
	alt->known_current = false;
	alt->ref_count = 1;

	return alt;
}

static inline void
alternative_ref(struct alternative *a)
{
	a->ref_count++;
}

static inline bool
alternative_unref(struct alternative *a)
{
	return --a->ref_count == 0;
}

static void
alternative_choices_free(struct alternative *a)
{
	struct fileset *fs;

	if (a->choices)
		a->modified = true;

	while (a->choices) {
		fs = a->choices;
		a->choices = fs->next;
		fileset_free(fs);
	}
}

static void
alternative_commit_operations_free(struct alternative *a)
{
	struct commit_operation *op;

	while (a->commit_ops) {
		op = a->commit_ops;
		a->commit_ops = op->next;
		commit_operation_free(op);
	}
}

static void
alternative_reset(struct alternative *alt)
{
	struct slave_link *slave;

	free(alt->current);
	alt->current = NULL;
	free(alt->master_link);
	alt->master_link = NULL;
	while (alt->slaves) {
		slave = alt->slaves;
		alt->slaves = slave->next;
		slave_link_free(slave);
	}
	alternative_choices_free(alt);
	alternative_commit_operations_free(alt);
	alt->modified = false;
	alt->known_current = false;
}

static void
alternative_free(struct alternative *alt)
{
	if (!alternative_unref(alt))
		return;

	alternative_reset(alt);
	free(alt->master_name);
	free(alt);
}

static int
alternative_choices_count(struct alternative *alt)
{
	struct fileset *fs;
	int count = 0;

	for (fs = alt->choices; fs; fs = fs->next)
		count++;

	return count;
}

static int
alternative_slaves_count(struct alternative *alt)
{
	struct slave_link *sl;
	int count = 0;

	for (sl = alt->slaves; sl; sl = sl->next)
		count++;

	return count;
}

static int
compare_fileset(const void *va, const void *vb)
{
	const struct fileset *a = *(const struct fileset **)va;
	const struct fileset *b = *(const struct fileset **)vb;

	assert(a && a->master_file);
	assert(b && b->master_file);

	return strcmp(a->master_file, b->master_file);
}

static int
compare_slave_link(const void *va, const void *vb)
{
	const struct slave_link *a = *(const struct slave_link **)va;
	const struct slave_link *b = *(const struct slave_link **)vb;

	assert(a && a->name);
	assert(b && b->name);

	return strcmp(a->name, b->name);
}

static void
alternative_sort_choices(struct alternative *a)
{
	int count, i;
	struct fileset **table, *fs;

	count = alternative_choices_count(a);
	if (count < 2) /* Nothing to sort */
		return;

	/* Store objects in a table instead of a linked list */
	table = xmalloc(sizeof(fs) * count);
	for (fs = a->choices, i = 0; fs; fs = fs->next) {
		assert(fs->master_file);
		table[i++] = fs;
	}

	qsort(table, count, sizeof(fs), compare_fileset);

	/* Rewrite the linked list from the sorted table */
	a->choices = fs = table[0];
	table[count - 1]->next = NULL;
	for (i = 1; i < count; fs = fs->next, i++)
		fs->next = table[i];
	free(table);
}

static void
alternative_sort_slaves(struct alternative *a)
{
	int count, i;
	struct slave_link **table, *sl;

	count = alternative_slaves_count(a);
	if (count < 2) /* Nothing to sort */
		return;

	/* Store objects in a table instead of a linked list */
	table = xmalloc(sizeof(sl) * count);
	for (sl = a->slaves, i = 0; sl; sl = sl->next, i++) {
		table[i] = sl;
	}

	qsort(table, count, sizeof(sl), compare_slave_link);

	/* Rewrite the linked list from the sorted table */
	a->slaves = sl = table[0];
	table[count - 1]->next = NULL;
	for (i = 1; i < count; sl = sl->next, i++)
		sl->next = table[i];
	free(table);
}

static struct fileset *
alternative_get_fileset(struct alternative *a, const char *file)
{
	struct fileset *fs;

	for (fs = a->choices; fs; fs = fs->next)
		if (strcmp(fs->master_file, file) == 0)
			return fs;

	return NULL;
}

static struct slave_link *
alternative_get_slave(struct alternative *a, const char *name)
{
	struct slave_link *sl;

	for (sl = a->slaves; sl; sl = sl->next)
		if (strcmp(sl->name, name) == 0)
			return sl;

	return NULL;
}

static bool
alternative_has_slave(struct alternative *a, const char *name)
{
	return alternative_get_slave(a, name) != NULL;
}

static bool
alternative_has_choice(struct alternative *a, const char *file)
{
	return alternative_get_fileset(a, file) != NULL;
}

static void
alternative_add_choice(struct alternative *a, struct fileset *fs)
{
	struct fileset *cur, *prev = NULL;

	/* Replace if already existing */
	for (cur = a->choices; cur; cur = cur->next) {
		if (strcmp(cur->master_file, fs->master_file) == 0) {
			fs->next = cur->next;
			fileset_free(cur);
			if (prev)
				prev->next = fs;
			else
				a->choices = fs;

			/* XXX: Be smarter in detecting change? */
			a->modified = true;
			return;
		}
		prev = cur;
	}

	/* Otherwise add at the end */
	if (prev == NULL)
		a->choices = fs;
	else
		prev->next = fs;
	fs->next = NULL;
	a->modified = true;
}

/* slave_name and slave_link must be allocated with malloc */
static struct slave_link *
alternative_add_slave(struct alternative *a, char *slave_name,
                      char *slave_link)
{
	struct slave_link *sl, *new;

	/* Replace if already existing */
	for (sl = a->slaves; sl; sl = sl->next) {
		if (strcmp(sl->name, slave_name) == 0) {
			free(sl->link);
			sl->link = xstrdup(slave_link);
			return sl;
		}
		if (sl->next == NULL)
			break;
	}

	/* Otherwise create new and add at the end */
	new = xmalloc(sizeof(*new));
	new->name = slave_name;
	new->link = slave_link;
	new->updated = false;
	new->next = NULL;
	if (sl)
		sl->next = new;
	else
		a->slaves = new;

	return new;
}

static void
alternative_copy_slave(struct alternative *a, struct slave_link *sl)
{
	struct slave_link *sl_new;

	sl_new = alternative_add_slave(a, xstrdup(sl->name), xstrdup(sl->link));
	sl_new->updated = sl->updated;
}

static const char *
alternative_status_string(enum alternative_status status)
{
	return (status == ALT_ST_AUTO) ? "auto" : "manual";
}

static const char *
alternative_status_describe(enum alternative_status status)
{
	return (status == ALT_ST_AUTO) ? _("auto mode") : _("manual mode");
}

static void
alternative_set_status(struct alternative *a, enum alternative_status status)
{
	if (a->status == ALT_ST_UNKNOWN || status != a->status)
		a->modified = true;

	if (a->status != ALT_ST_UNKNOWN && status != a->status)
		log_msg("status of link group %s set to %s", a->master_link,
		        alternative_status_string(status));

	a->status = status;
}

/* link must be allocated with malloc */
static void
alternative_set_link(struct alternative *a, char *linkname)
{
	if (a->master_link == NULL || strcmp(linkname, a->master_link) != 0)
		a->modified = true;

	free(a->master_link);
	a->master_link = linkname;
}

static bool
alternative_remove_choice(struct alternative *a, const char *file)
{
	struct fileset *fs, *fs_prev;

	fs_prev = NULL;
	for (fs = a->choices; fs; fs = fs->next) {
		if (strcmp(fs->master_file, file) != 0) {
			fs_prev = fs;
			continue;
		}
		if (fs_prev)
			fs_prev->next = fs->next;
		else
			a->choices = fs->next;
		fileset_free(fs);
		a->modified = true;
		return true;
	}

	return false;
}

/*
 * Alternatives Database Load/Store functions.
 */

enum altdb_flags {
	ALTDB_LAX_PARSER = 1 << 0,
	ALTDB_WARN_PARSER = 1 << 1,
};

struct altdb_context {
	FILE *fh;
	char *filename;
	enum altdb_flags flags;
	bool modified;
	void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(2)
	     (*bad_format)(struct altdb_context *, const char *format, ...);
	jmp_buf on_error;
};

static int
altdb_filter_namelist(const struct dirent *entry)
{
	if (strcmp(entry->d_name, ".") == 0 ||
	    strcmp(entry->d_name, "..") == 0 ||
	    (strlen(entry->d_name) > strlen(ALT_TMP_EXT) &&
	     strcmp(entry->d_name + strlen(entry->d_name) -
	            strlen(ALT_TMP_EXT), ALT_TMP_EXT) == 0))
		return 0;
	return 1;
}

static int
altdb_get_namelist(struct dirent ***table)
{
	int count;

	count = scandir(admdir, table, altdb_filter_namelist, alphasort);
	if (count < 0)
		syserr(_("cannot scan directory '%.255s'"), admdir);

	return count;
}

static void
altdb_free_namelist(struct dirent **table, int n)
{
	while (n--)
		free(table[n]);
	free(table);
}

static char *
altdb_get_line(struct altdb_context *ctx, const char *name)
{
	char *buf, *line;
	size_t len, bufsz, i;

	bufsz = 1024;
	buf = xmalloc(bufsz);

	for (i = 0; true; i += strlen(line)) {
		errno = 0;
		line = fgets(buf + i, bufsz - i, ctx->fh);
		if (line) {
			if (strlen(buf) < bufsz - 1 || buf[bufsz - 2] == '\n')
				break;
			/* Need more space */
			bufsz *= 2;
			buf = realloc(buf, bufsz);
			if (!buf)
				error(_("failed to allocate memory"));
			continue;
		}
		if (feof(ctx->fh))
			ctx->bad_format(ctx, _("unexpected end of file while trying "
			                       "to read %s"), name);
		ctx->bad_format(ctx, _("while reading %s: %s"),
		                name, strerror(errno));
	}

	len = strlen(buf);
	if (len == 0 || buf[len - 1] != '\n') {
		ctx->bad_format(ctx, _("line not terminated while trying "
		                       "to read %s"), name);
	}
	line[len - 1] = '\0';

	return buf;
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(2)
altdb_parse_error(struct altdb_context *ctx, const char *format, ...)
{
	char *msg;
	va_list args;

	va_start(args, format);
	msg = xvasprintf(format, args);
	va_end(args);

	error(_("%s corrupt: %s"), ctx->filename, msg);
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(2)
altdb_parse_stop(struct altdb_context *ctx, const char *format, ...)
{
	longjmp(ctx->on_error, 1);
}

static void
altdb_print_line(struct altdb_context *ctx, const char *line)
{
	if (strchr(line, '\n') != NULL)
		error(_("newlines prohibited in update-alternatives files (%s)"),
		      line);

	if (fprintf(ctx->fh, "%s\n", line) < (int) strlen(line) + 1)
		syserr(_("unable to write file '%s'"), ctx->filename);
}

static bool
alternative_parse_slave(struct alternative *a, struct altdb_context *ctx)
{
	char *name, *linkname;
	struct slave_link *sl;

	name = altdb_get_line(ctx, _("slave name"));
	if (!strlen(name)) { /* End of list */
		free(name);
		return false;
	}
	if (alternative_has_slave(a, name)) {
		sl = alternative_get_slave(a, name);
		free(name);
		ctx->bad_format(ctx, _("duplicate slave name %s"), sl->name);
	}

	linkname = altdb_get_line(ctx, _("slave link"));
	if (strcmp(linkname, a->master_link) == 0) {
		free(linkname);
		free(name);
		ctx->bad_format(ctx, _("slave link same as main link %s"),
		                a->master_link);
	}
	for (sl = a->slaves; sl; sl = sl->next) {
		if (strcmp(linkname, sl->link) == 0) {
			free(linkname);
			free(name);
			ctx->bad_format(ctx, _("duplicate slave link %s"),
			                sl->link);
		}
	}

	alternative_add_slave(a, name, linkname);

	return true;
}

static bool
alternative_parse_fileset(struct alternative *a, struct altdb_context *ctx)
{
	struct fileset *fs;
	struct slave_link *sl;
	struct stat st;
	char *master_file;

	master_file = altdb_get_line(ctx, _("master file"));
	if (!strlen(master_file)) { /* End of list */
		free(master_file);
		return false;
	}

	fs = alternative_get_fileset(a, master_file);
	if (fs)
		ctx->bad_format(ctx, _("duplicate path %s"), master_file);

	if (stat(master_file, &st)) {
		char *junk;

		if (errno != ENOENT)
			syserr(_("cannot stat file '%s'"), master_file);

		/* File not found - remove. */
		if (ctx->flags & ALTDB_WARN_PARSER)
			warning(_("alternative %s (part of link group %s) "
			          "doesn't exist; removing from list of "
			          "alternatives"), master_file, a->master_name);
		junk = altdb_get_line(ctx, _("priority"));
		free(junk);
		for (sl = a->slaves; sl; sl = sl->next) {
			junk = altdb_get_line(ctx, _("slave file"));
			free(junk);
		}
		ctx->modified = true;
	} else {
		char *prio_str, *prio_end;
		long prio;

		prio_str = altdb_get_line(ctx, _("priority"));
		errno = 0;
		prio = strtol(prio_str, &prio_end, 10);
		/* XXX: Leak master_file/prio_str on non-fatal error */
		if (prio_str == prio_end || *prio_end != '\0')
			ctx->bad_format(ctx, _("priority of %s: %s"),
			                master_file, prio_str);
		if (prio < INT_MIN || prio > INT_MAX || errno == ERANGE)
			ctx->bad_format(ctx,
			                _("priority of %s is out of range: %s"),
			                master_file, prio_str);
		free(prio_str);

		fs = fileset_new(master_file, prio);
		for (sl = a->slaves; sl; sl = sl->next) {
			fileset_add_slave(fs, xstrdup(sl->name),
			                  altdb_get_line(ctx, _("slave file")));
		}
		alternative_add_choice(a, fs);
	}
	free(master_file);

	return true;
}

static bool
alternative_load(struct alternative *a, enum altdb_flags flags)
{
	struct altdb_context ctx;
	struct stat st;
	char *status;

	/* Initialize parse context */
	if (setjmp(ctx.on_error)) {
		if (ctx.fh)
			fclose(ctx.fh);
		free(ctx.filename);
		alternative_reset(a);
		return false;
	}
	ctx.modified = false;
	ctx.flags = flags;
	if (flags & ALTDB_LAX_PARSER)
		ctx.bad_format = altdb_parse_stop;
	else
		ctx.bad_format = altdb_parse_error;
	ctx.filename = xasprintf("%s/%s", admdir, a->master_name);

	/* Open the alternative file. */
	ctx.fh = fopen(ctx.filename, "r");
	if (ctx.fh == NULL) {
		if (errno == ENOENT)
			return false;

		syserr(_("unable to open file '%s'"), ctx.filename);
	}

	/* Verify the alternative is not empty. */
	if (fstat(fileno(ctx.fh), &st) == -1)
		syserr(_("cannot stat file '%s'"), ctx.filename);
	if (st.st_size == 0)
		return false;

	/* Start parsing mandatory attributes (link+status) of the alternative */
	alternative_reset(a);
	status = altdb_get_line(&ctx, _("status"));
	if (strcmp(status, "auto") != 0 && strcmp(status, "manual") != 0)
		ctx.bad_format(&ctx, _("invalid status"));
	alternative_set_status(a, (strcmp(status, "auto") == 0) ?
	                       ALT_ST_AUTO : ALT_ST_MANUAL);
	free(status);

	alternative_set_link(a, altdb_get_line(&ctx, _("master link")));

	/* Parse the description of the slaves links of the alternative */
	while (alternative_parse_slave(a, &ctx));

	/* Parse the available choices in the alternative */
	while (alternative_parse_fileset(a, &ctx)) ;

	/* Close database file */
	if (fclose(ctx.fh))
		syserr(_("unable to close file '%s'"), ctx.filename);
	free(ctx.filename);

	/* Initialize the modified field which has been erroneously changed
	 * by the various alternative_(add|set)_* calls:
	 * false unless a choice has been auto-cleaned */
	a->modified = ctx.modified;

	return true;
}

static void
alternative_save(struct alternative *a)
{
	struct altdb_context ctx;
	struct slave_link *sl, *sl_prev;
	struct fileset *fs;
	char *filenew, *file;

	/* Cleanup unused slaves before writing admin file. */
	sl_prev = NULL;
	for (sl = a->slaves; sl; sl_prev = sl, sl = sl->next) {
		bool has_slave = false;

		for (fs = a->choices; fs; fs = fs->next) {
			if (fileset_has_slave(fs, sl->name)) {
				has_slave = true;
				break;
			}
		}

		if (!has_slave) {
			struct slave_link *sl_rm;

			verbose(_("discarding obsolete slave link %s (%s)"),
			        sl->name, sl->link);
			if (sl_prev)
				sl_prev->next = sl->next;
			else
				a->slaves = sl->next;
			sl_rm = sl;
			sl = sl_prev ? sl_prev : a->slaves;
			slave_link_free(sl_rm);
			if (!sl)
				break; /* No other slave left. */
		}
	}

	/* Sort entries */
	alternative_sort_slaves(a);
	alternative_sort_choices(a);

	/* Write admin file. */
	file = xasprintf("%s/%s", admdir, a->master_name);
	filenew = xasprintf("%s" ALT_TMP_EXT, file);

	ctx.filename = filenew;
	ctx.fh = fopen(ctx.filename, "w");
	if (ctx.fh == NULL)
		syserr(_("unable to create file '%s'"), ctx.filename);

	altdb_print_line(&ctx, alternative_status_string(a->status));
	altdb_print_line(&ctx, a->master_link);
	for (sl = a->slaves; sl; sl = sl->next) {
		altdb_print_line(&ctx, sl->name);
		altdb_print_line(&ctx, sl->link);
	}
	altdb_print_line(&ctx, "");

	for (fs = a->choices; fs; fs = fs->next) {
		char *prio;

		altdb_print_line(&ctx, fs->master_file);

		prio = xasprintf("%d", fs->priority);
		altdb_print_line(&ctx, prio);
		free(prio);

		for (sl = a->slaves; sl; sl = sl->next) {
			if (fileset_has_slave(fs, sl->name))
				altdb_print_line(&ctx,
				        fileset_get_slave(fs, sl->name));
			else
				altdb_print_line(&ctx, "");
		}
	}
	altdb_print_line(&ctx, "");

	/* Close database file */
	if (fflush(ctx.fh))
		syserr(_("unable to flush file '%s'"), ctx.filename);
	if (fsync(fileno(ctx.fh)))
		syserr(_("unable to sync file '%s'"), ctx.filename);
	if (fclose(ctx.fh))
		syserr(_("unable to close file '%s'"), ctx.filename);

	/* Put in place atomically. */
	checked_mv(filenew, file);

	free(filenew);
	free(file);
}

static const char *
alternative_set_current(struct alternative *a, char *new_choice)
{
	a->known_current = true;
	a->current = new_choice;

	return new_choice;
}

static const char *
alternative_get_current(struct alternative *a)
{
	struct stat st;
	char *curlink;
	char *file;

	if (a->known_current)
		return a->current;

	curlink = xasprintf("%s/%s", altdir, a->master_name);
	if (lstat(curlink, &st)) {
		if (errno == ENOENT) {
			free(curlink);
			return alternative_set_current(a, NULL);
		}
		syserr(_("cannot stat file '%s'"), curlink);
	}

	file = xreadlink(curlink);
	free(curlink);

	return alternative_set_current(a, file);
}

static struct fileset *
alternative_get_best(struct alternative *a)
{
	struct fileset *fs, *best;
	const char *current;

	current = alternative_get_current(a);
	if (current)
		best = alternative_get_fileset(a, current);
	else
		best = NULL;

	if (best == NULL)
		best = a->choices;

	for (fs = a->choices; fs; fs = fs->next)
		if (fs->priority > best->priority)
			best = fs;

	return best;
}

static void
alternative_display_query(struct alternative *a)
{
	struct fileset *best, *fs;
	struct slave_link *sl;
	const char *current;

	pr("Name: %s", a->master_name);
	pr("Link: %s", a->master_link);
	if (alternative_slaves_count(a) > 0) {
		pr("Slaves:");
		for (sl = a->slaves; sl; sl = sl->next)
			pr(" %s %s", sl->name, sl->link);
	}
	pr("Status: %s", alternative_status_string(a->status));
	best = alternative_get_best(a);
	if (best)
		pr("Best: %s", best->master_file);
	current = alternative_get_current(a);
	pr("Value: %s", current ? current : "none");

	for (fs = a->choices; fs; fs = fs->next) {
		printf("\n");
		pr("Alternative: %s", fs->master_file);
		pr("Priority: %d", fs->priority);
		if (alternative_slaves_count(a) == 0)
			continue;
		pr("Slaves:");
		for (sl = a->slaves; sl; sl = sl->next) {
			if (fileset_has_slave(fs, sl->name))
				pr(" %s %s", sl->name,
				   fileset_get_slave(fs, sl->name));
		}
	}
}

static void
alternative_display_user(struct alternative *a)
{
	const char *current;
	struct fileset *fs;
	struct slave_link *sl;

	pr("%s - %s", a->master_name, alternative_status_describe(a->status));
	fs = alternative_get_best(a);
	if (fs)
		pr(_("  link best version is %s"), fs->master_file);
	else
		pr(_("  link best version not available"));
	current = alternative_get_current(a);
	if (current) {
		pr(_("  link currently points to %s"), current);
	} else {
		pr(_("  link currently absent"));
	}
	pr(_("  link %s is %s"), a->master_name, a->master_link);
	for (sl = a->slaves; sl; sl = sl->next)
		pr(_("  slave %s is %s"), sl->name, sl->link);

	for (fs = a->choices; fs; fs = fs->next) {
		pr(_("%s - priority %d"), fs->master_file, fs->priority);
		for (sl = a->slaves; sl; sl = sl->next) {
			if (fileset_has_slave(fs, sl->name))
				pr(_("  slave %s: %s"), sl->name,
				   fileset_get_slave(fs, sl->name));
		}
	}
}

static void
alternative_display_list(struct alternative *a)
{
	struct fileset *fs;

	for (fs = a->choices; fs; fs = fs->next)
		pr("%s", fs->master_file);
}

static void
alternative_print_choice(struct alternative *a, enum alternative_status status,
                         struct fileset *fs, int idx, int len)
{
	const char *current = alternative_get_current(a);
	int mark;

	if (a->status == status &&
	    current && strcmp(current, fs->master_file) == 0)
		mark = '*';
	else
		mark = ' ';

	pr("%c %-12d %-*s % -10d %s", mark, idx, len,
	   fs->master_file, fs->priority, alternative_status_describe(status));
}

static char *
alternative_select_choice(struct alternative *a)
{
	const char *current;
	char *ret, selection[_POSIX_PATH_MAX];
	struct fileset *best, *fs;
	int n_choices;
	int len, idx;

	n_choices = alternative_choices_count(a);
	current = alternative_get_current(a);
	best = alternative_get_best(a);
	assert(best);

	len = 15;
	for (fs = a->choices; fs; fs = fs->next)
		len = max(len, (int)strlen(fs->master_file) + 1);

	for (;;) {
		pr(P_("There is %d choice for the alternative %s (providing %s).",
		      "There are %d choices for the alternative %s (providing %s).",
		      n_choices), n_choices, a->master_name, a->master_link);
		printf("\n");

		pr("  %-12.12s %-*.*s %-10.10s %s", _("Selection"), len, len,
		   _("Path"), _("Priority"), _("Status"));
		pr("------------------------------------------------------------");
		idx = 0;
		alternative_print_choice(a, ALT_ST_AUTO, best, idx++, len);
		for (fs = a->choices; fs; fs = fs->next, idx++)
			alternative_print_choice(a, ALT_ST_MANUAL, fs, idx, len);
		printf("\n");
		printf(_("Press <enter> to keep the current choice[*], "
		         "or type selection number: "));
		ret = fgets(selection, sizeof(selection), stdin);
		if (ret == NULL || strlen(selection) == 0) {
			return NULL;
		}
		selection[strlen(selection) - 1] = '\0';
		if (strlen(selection) == 0)
			return xstrdup(current);
		errno = 0;
		idx = strtol(selection, &ret, 10);
		if (idx < 0 || errno != 0)
			continue;
		if (*ret == '\0') {
			/* Look up by index */
			if (idx == 0) {
				alternative_set_status(a, ALT_ST_AUTO);
				return xstrdup(best->master_file);
			}
			idx--;
			for (fs = a->choices; idx && fs; idx--)
				fs = fs->next;
			if (fs) {
				alternative_set_status(a, ALT_ST_MANUAL);
				return xstrdup(fs->master_file);
			}
		} else {
			/* Look up by name */
			fs = alternative_get_fileset(a, selection);
			if (fs) {
				alternative_set_status(a, ALT_ST_MANUAL);
				return xstrdup(selection);
			}
		}
	}
}

static char *
alternative_config(struct alternative *a, const char *current_choice)
{
	char *new_choice = NULL;

	if (alternative_choices_count(a) == 0) {
		pr(_("There is no program which provides %s."),
		   a->master_name);
		pr(_("Nothing to configure."));
	} else if (opt_skip_auto && a->status == ALT_ST_AUTO) {
		alternative_display_user(a);
	} else if (alternative_choices_count(a) == 1 &&
	           a->status == ALT_ST_AUTO &&
	           current_choice != NULL) {
		pr(_("There is only one alternative in link group %s (providing %s): %s"),
		   a->master_name, a->master_link, current_choice);
		pr(_("Nothing to configure."));
	} else {
		new_choice = alternative_select_choice(a);
	}

	return new_choice;
}

static void
alternative_add_commit_op(struct alternative *a, enum opcode opcode,
                          const char *arg_a, const char *arg_b)
{
	struct commit_operation *op, *cur;

	op = xmalloc(sizeof(*op));
	op->opcode = opcode;
	op->arg_a = xstrdup(arg_a);
	op->arg_b = xstrdup(arg_b);
	op->next = NULL;

	/* Add at the end */
	cur = a->commit_ops;
	while (cur && cur->next)
		cur = cur->next;
	if (cur)
		cur->next = op;
	else
		a->commit_ops = op;
}

static void
alternative_commit(struct alternative *a)
{
	struct commit_operation *op;

	for (op = a->commit_ops; op; op = op->next) {
		switch (op->opcode) {
		case OPCODE_NOP:
			break;
		case OPCODE_RM:
			checked_rm(op->arg_a);
			break;
		case OPCODE_MV:
			checked_mv(op->arg_a, op->arg_b);
			break;
		}
	}

	alternative_commit_operations_free(a);
}

enum alternative_path_status {
	ALT_PATH_SYMLINK,
	ALT_PATH_MISSING,
	ALT_PATH_OTHER,
};

static enum alternative_path_status
alternative_path_classify(const char *linkname)
{
	struct stat st;

	errno = 0;
	if (lstat(linkname, &st) == -1) {
		if (errno != ENOENT)
			syserr(_("cannot stat file '%s'"), linkname);
		return ALT_PATH_MISSING;
	} else if (S_ISLNK(st.st_mode)) {
		return ALT_PATH_SYMLINK;
	} else {
		return ALT_PATH_OTHER;
	}
}

static bool
alternative_path_can_remove(const char *linkname)
{
	if (opt_force)
		return true;

	if (alternative_path_classify(linkname) == ALT_PATH_OTHER)
		return false;
	else
		return true;
}

static bool
alternative_path_needs_update(const char *linkname, const char *filename)
{
	char *linktarget;
	bool update;

	if (opt_force)
		return true;

	switch (alternative_path_classify(linkname)) {
	case ALT_PATH_SYMLINK:
		linktarget = xreadlink(linkname);
		if (strcmp(linktarget, filename) == 0)
			update = false;
		else
			update = true;
		free(linktarget);

		return update;
	case ALT_PATH_OTHER:
		warning(_("not replacing %s with a link"), linkname);
		return false;
	case ALT_PATH_MISSING:
	default:
		return true;
	}
}

static void
alternative_prepare_install_single(struct alternative *a, const char *name,
                                   const char *linkname, const char *file)
{
	char *fntmp, *fn;

	/* Create link in /etc/alternatives. */
	fntmp = xasprintf("%s/%s" ALT_TMP_EXT, altdir, name);
	fn = xasprintf("%s/%s", altdir, name);
	checked_rm(fntmp);
	checked_symlink(file, fntmp);
	alternative_add_commit_op(a, OPCODE_MV, fntmp, fn);
	free(fntmp);

	if (alternative_path_needs_update(linkname, fn)) {
		/* Create alternative link. */
		fntmp = xasprintf("%s" ALT_TMP_EXT, linkname);
		checked_rm(fntmp);
		checked_symlink(fn, fntmp);
		alternative_add_commit_op(a, OPCODE_MV, fntmp, linkname);
		free(fntmp);
	}
	free(fn);
}

static void
alternative_prepare_install(struct alternative *a, const char *choice)
{
	struct slave_link *sl;
	struct fileset *fs;

	fs = alternative_get_fileset(a, choice);
	if (fs == NULL)
		error(_("can't install unknown choice %s"), choice);

	/* Take care of master alternative */
	alternative_prepare_install_single(a, a->master_name, a->master_link,
	                                   choice);

	/* Take care of slaves alternatives */
	for (sl = a->slaves; sl; sl = sl->next) {
		char *fn;

		if (fileset_can_install_slave(fs, sl->name)) {
			alternative_prepare_install_single(a, sl->name,
			        sl->link, fileset_get_slave(fs, sl->name));
			continue;
		}

		/* Slave can't be installed */
		if (fileset_has_slave(fs, sl->name))
			warning(_("skip creation of %s because associated "
			          "file %s (of link group %s) doesn't exist"),
			        sl->link, fileset_get_slave(fs, sl->name),
			        a->master_name);

		/* Drop unused slave. */
		fn = xasprintf("%s/%s", altdir, sl->name);
		if (alternative_path_can_remove(sl->link))
			alternative_add_commit_op(a, OPCODE_RM, sl->link, NULL);
		else
			warning(_("not removing %s since it's not a symlink"),
			        sl->link);
		alternative_add_commit_op(a, OPCODE_RM, fn, NULL);
		free(fn);
	}
}

static void
alternative_remove_files(struct alternative *a)
{
	struct slave_link *sl;

	checked_rm_args("%s" ALT_TMP_EXT, a->master_link);
	if (alternative_path_can_remove(a->master_link))
		checked_rm(a->master_link);

	checked_rm_args("%s/%s" ALT_TMP_EXT, altdir, a->master_name);
	checked_rm_args("%s/%s", altdir, a->master_name);

	for (sl = a->slaves; sl; sl = sl->next) {
		checked_rm_args("%s" ALT_TMP_EXT, sl->link);
		if (alternative_path_can_remove(sl->link))
			checked_rm(sl->link);

		checked_rm_args("%s/%s" ALT_TMP_EXT, altdir, sl->name);
		checked_rm_args("%s/%s", altdir, sl->name);
	}
	/* Drop admin file */
	checked_rm_args("%s/%s", admdir, a->master_name);
}

static const char *
alternative_remove(struct alternative *a, const char *current_choice,
                   const char *path)
{
	const char *new_choice = NULL;

	if (alternative_has_choice(a, path))
		alternative_remove_choice(a, path);
	else
		verbose(_("alternative %s for %s not registered; not removing"),
		        path, a->master_name);

	if (current_choice && strcmp(current_choice, path) == 0) {
		struct fileset *best;

		/* Current choice is removed. */
		if (a->status == ALT_ST_MANUAL) {
			/* And it was manual, switch to auto. */
			info(_("removing manually selected alternative "
			       "- switching %s to auto mode"),
			     a->master_name);
			alternative_set_status(a, ALT_ST_AUTO);
		}
		best = alternative_get_best(a);
		if (best)
			new_choice = best->master_file;
	}

	return new_choice;
}

static bool
alternative_has_broken_slave(struct slave_link *sl, struct fileset *fs)
{
	if (fileset_can_install_slave(fs, sl->name)) {
		char *wanted;
		char *sl_altlnk, *sl_current;

		/* Verify link -> /etc/alternatives/foo */
		sl_altlnk = areadlink(sl->link);
		if (!sl_altlnk)
			return true;
		wanted = xasprintf("%s/%s", altdir, sl->name);
		if (strcmp(sl_altlnk, wanted) != 0) {
			free(wanted);
			free(sl_altlnk);
			return true;
		}
		free(sl_altlnk);
		/* Verify /etc/alternatives/foo -> file */
		sl_current = areadlink(wanted);
		free(wanted);
		if (!sl_current)
			return true;
		if (strcmp(sl_current, fileset_get_slave(fs, sl->name)) != 0) {
			free(sl_current);
			return true;
		}
		free(sl_current);
	} else {
		char *sl_altlnk;

		/* Slave link must not exist. */
		if (alternative_path_classify(sl->link) != ALT_PATH_MISSING)
			return true;
		sl_altlnk = xasprintf("%s/%s", altdir, sl->name);
		if (alternative_path_classify(sl_altlnk) != ALT_PATH_MISSING) {
			free(sl_altlnk);
			return true;
		}
		free(sl_altlnk);
	}

	return false;
}

static enum alternative_update_reason
alternative_needs_update(struct alternative *a)
{
	enum alternative_update_reason reason = ALT_UPDATE_NO;
	const char *current;
	char *altlnk, *wanted;
	struct fileset *fs;
	struct slave_link *sl;

	/* Check master link */
	altlnk = areadlink(a->master_link);
	if (!altlnk)
		return ALT_UPDATE_LINK_BROKEN;
	wanted = xasprintf("%s/%s", altdir, a->master_name);
	if (strcmp(altlnk, wanted) != 0) {
		free(wanted);
		free(altlnk);
		return ALT_UPDATE_LINK_BROKEN;
	}
	free(wanted);
	free(altlnk);

	/* Stop if we have an unmanaged alternative */
	current = alternative_get_current(a);
	if (current == NULL)
		return ALT_UPDATE_LINK_BROKEN;

	fs = alternative_get_fileset(a, current);

	/* Stop if we do not have the choice. */
	if (fs == NULL)
		return ALT_UPDATE_NO;

	/* Check slaves */
	for (sl = a->slaves; sl; sl = sl->next) {
		if (alternative_has_broken_slave(sl, fs)) {
			if (sl->updated)
				reason = ALT_UPDATE_SLAVE_CHANGED;
			else
				return ALT_UPDATE_LINK_BROKEN;
		}
	}

	return reason;
}

struct alternative_map {
	struct alternative_map *next;

	const char *key;
	struct alternative *item;
};

static struct alternative_map *
alternative_map_new(const char *key, struct alternative *a)
{
	struct alternative_map *am;

	am = xmalloc(sizeof(*am));
	am->next = NULL;
	am->key = key;
	am->item = a;

	return am;
}

static struct alternative *
alternative_map_find(struct alternative_map *am, const char *key)
{
	for (; am; am = am->next)
		if (am->key && strcmp(am->key, key) == 0)
			return am->item;

	return NULL;
}

static void
alternative_map_add(struct alternative_map *am, const char *key,
                    struct alternative *a)
{
	if (am->key == NULL) {
		am->key = key;
		am->item = a;
	} else {
		struct alternative_map *new = alternative_map_new(key, a);

		while (am->next)
			am = am->next;
		am->next = new;
	}
}

static void
alternative_map_load_names(struct alternative_map *alt_map_obj)
{
	struct dirent **table;
	int i, count;

	count = altdb_get_namelist(&table);
	for (i = 0; i < count; i++) {
		struct alternative *a_new = alternative_new(table[i]->d_name);

		if (!alternative_load(a_new, ALTDB_LAX_PARSER)) {
			alternative_free(a_new);
			continue;
		}
		alternative_map_add(alt_map_obj, a_new->master_name, a_new);
	}
	altdb_free_namelist(table, count);
}

static void
alternative_map_load_tree(struct alternative_map *alt_map_links,
                          struct alternative_map *alt_map_parent)
{
	struct dirent **table;
	int i, count;

	count = altdb_get_namelist(&table);
	for (i = 0; i < count; i++) {
		struct slave_link *sl;
		struct alternative *a_new = alternative_new(table[i]->d_name);

		if (!alternative_load(a_new, ALTDB_LAX_PARSER)) {
			alternative_free(a_new);
			continue;
		}
		alternative_map_add(alt_map_links, a_new->master_link, a_new);
		alternative_ref(a_new);
		alternative_map_add(alt_map_parent, a_new->master_name, a_new);
		for (sl = a_new->slaves; sl; sl = sl->next) {
			alternative_ref(a_new);
			alternative_map_add(alt_map_links, sl->link, a_new);
			alternative_ref(a_new);
			alternative_map_add(alt_map_parent, sl->name, a_new);
		}
	}
	altdb_free_namelist(table, count);
}

static void
alternative_map_free(struct alternative_map *am)
{
	struct alternative_map *am_next;

	while (am) {
		am_next = am->next;
		if (am->item)
			alternative_free(am->item);
		free(am);
		am = am_next;
	}
}

static const char *
alternative_set_manual(struct alternative *a, const char *path)
{
	const char *new_choice = NULL;

	if (alternative_has_choice(a, path))
		new_choice = path;
	else
		error(_("alternative %s for %s not registered; "
		        "not setting"), path, a->master_name);
	alternative_set_status(a, ALT_ST_MANUAL);

	return new_choice;
}

static const char *
alternative_set_auto(struct alternative *a)
{
	const char *new_choice = NULL;

	alternative_set_status(a, ALT_ST_AUTO);
	if (alternative_choices_count(a) == 0)
		pr(_("There is no program which provides %s."),
		   a->master_name);
	else
		new_choice = alternative_get_best(a)->master_file;

	return new_choice;
}

static const char *
get_argv_string(int argc, char **argv)
{
	static char string[2048];
	size_t cur_len;
	int i;

	string[0] = '\0';
	cur_len = 0;
	for (i = 1; i < argc; i++) {
		size_t arg_len = strlen(argv[i]);

		if (cur_len + arg_len + 2 > sizeof(string))
			break;
		if (cur_len) {
			strcpy(string + cur_len, " ");
			cur_len++;
		}
		strcpy(string + cur_len, argv[i]);
		cur_len += arg_len;
	}

	return string;
}

static void
alternative_select_mode(struct alternative *a, const char *current_choice)
{
	if (current_choice) {
		/* Detect manually modified alternative, switch to manual. */
		if (!alternative_has_choice(a, current_choice)) {
			struct stat st;

			errno = 0;
			if (stat(current_choice, &st) == -1 && errno != ENOENT)
				syserr(_("cannot stat file '%s'"), current_choice);

			if (errno == ENOENT) {
				warning(_("%s/%s is dangling; it will be updated "
				          "with best choice"), altdir, a->master_name);
				alternative_set_status(a, ALT_ST_AUTO);
			} else if (a->status != ALT_ST_MANUAL) {
				warning(_("%s/%s has been changed (manually or by "
				          "a script); switching to manual "
				          "updates only"), altdir, a->master_name);
				alternative_set_status(a, ALT_ST_MANUAL);
			}
		}
	} else {
		/* Lack of alternative link => automatic mode. */
		verbose(_("setting up automatic selection of %s"),
		        a->master_name);
		alternative_set_status(a, ALT_ST_AUTO);
	}
}

static void
alternative_evolve_slave(struct alternative *a, const char *cur_choice,
                         struct slave_link *sl, struct fileset *fs)
{
	struct stat st;
	char *new_file = NULL;
	const char *old, *new;

	old = alternative_get_slave(a, sl->name)->link;
	new = sl->link;

	if (cur_choice && strcmp(cur_choice, fs->master_file) == 0) {
		new_file = xstrdup(fileset_get_slave(fs, sl->name));
	} else {
		char *lnk;

		lnk = xasprintf("%s/%s", altdir, sl->name);
		new_file = areadlink(lnk);
		free(lnk);
	}
	if (strcmp(old, new) != 0 &&
	    alternative_path_classify(old) == ALT_PATH_SYMLINK) {
		bool rename_link = false;

		if (new_file) {
			errno = 0;
			if (stat(new_file, &st) == -1 && errno != ENOENT)
				syserr(_("cannot stat file '%s'"),
				       new_file);
			rename_link = (errno == 0);
		}

		if (rename_link) {
			info(_("renaming %s slave link from %s to %s"),
			     sl->name, old, new);
			checked_mv(old, new);
		} else {
			checked_rm(old);
		}

		sl->updated = true;
	}
	free(new_file);
}

static void
alternative_evolve(struct alternative *a, struct alternative *b,
                   const char *cur_choice, struct fileset *fs)
{
	struct slave_link *sl;
	bool is_link;

	is_link = alternative_path_classify(a->master_link) == ALT_PATH_SYMLINK;
	if (is_link && strcmp(a->master_link, b->master_link) != 0) {
		info(_("renaming %s link from %s to %s"), b->master_name,
		     a->master_link, b->master_link);
		checked_mv(a->master_link, b->master_link);
	}
	alternative_set_link(a, xstrdup(b->master_link));

	/* Check if new slaves have been added, or existing
	 * ones renamed. */
	for (sl = b->slaves; sl; sl = sl->next) {
		if (alternative_has_slave(a, sl->name))
			alternative_evolve_slave(a, cur_choice, sl, fs);
		else
			sl->updated = true;

		alternative_copy_slave(a, sl);
	}
}

static void
alternative_update(struct alternative *a,
                   const char *current_choice, const char *new_choice)
{
	enum alternative_update_reason reason;

	/* No choice left, remove everything. */
	if (!alternative_choices_count(a)) {
		log_msg("link group %s fully removed", a->master_name);
		alternative_remove_files(a);
		return;
	}

	/* New choice wanted. */
	if (new_choice &&
	    (!current_choice || strcmp(new_choice, current_choice) != 0)) {
		log_msg("link group %s updated to point to %s", a->master_name,
		        new_choice);
		if (a->status == ALT_ST_AUTO)
			info(_("using %s to provide %s (%s) in auto mode"),
			     new_choice, a->master_link, a->master_name);
		else
			info(_("using %s to provide %s (%s) in manual mode"),
			     new_choice, a->master_link, a->master_name);
		debug("prepare_install(%s)", new_choice);
		alternative_prepare_install(a, new_choice);
	} else if ((reason = alternative_needs_update(a))) {
		if (reason == ALT_UPDATE_SLAVE_CHANGED) {
			log_msg("link group %s updated with changed slaves",
			        a->master_name);
			info(_("updating alternative %s "
			       "because link group %s has changed slave links"),
			     current_choice, a->master_name);
		} else {
			log_msg("auto-repair link group %s", a->master_name);
			warning(_("forcing reinstallation of alternative %s "
			          "because link group %s is broken"),
			        current_choice, a->master_name);
		}

		if (current_choice && !alternative_has_choice(a, current_choice)) {
			struct fileset *best = alternative_get_best(a);

			warning(_("current alternative %s is unknown, "
			          "switching to %s for link group %s"),
			        current_choice, best->master_file,
			        a->master_name);
			current_choice = best->master_file;
			alternative_set_status(a, ALT_ST_AUTO);
		}

		if (current_choice)
			alternative_prepare_install(a, current_choice);
	}

	/* Save administrative file if needed. */
	if (a->modified) {
		debug("%s is modified and will be saved", a->master_name);
		alternative_save(a);
	}

	/* Replace all symlinks in one pass. */
	alternative_commit(a);
}

static void
alternative_config_all(void)
{
	struct alternative_map *alt_map_obj;
	struct alternative_map *am;

	alt_map_obj = alternative_map_new(NULL, NULL);
	alternative_map_load_names(alt_map_obj);

	for (am = alt_map_obj; am && am->item; am = am->next) {
		const char *current_choice;
		char *new_choice;

		current_choice = alternative_get_current(am->item);
		alternative_select_mode(am->item, current_choice);

		new_choice = alternative_config(am->item, current_choice);

		alternative_update(am->item, current_choice, new_choice);

		free(new_choice);
	}

	alternative_map_free(alt_map_obj);
}

static void
alternative_get_selections(void)
{
	struct alternative_map *alt_map_obj;
	struct alternative_map *am;

	alt_map_obj = alternative_map_new(NULL, NULL);
	alternative_map_load_names(alt_map_obj);

	for (am = alt_map_obj; am && am->item; am = am->next) {
		const char *current;

		current = alternative_get_current(am->item);
		printf("%-30s %-8s %s\n", am->key,
		       alternative_status_string(am->item->status),
		       current ? current : "");
	}

	alternative_map_free(alt_map_obj);
}

static void
alternative_set_selection(struct alternative_map *all, const char *name,
                          const char *status, const char *choice)
{
	struct alternative *a;

	debug("set_selection(%s, %s, %s)", name, status, choice);
	a = alternative_map_find(all, name);
	if (a) {
		const char *new_choice = NULL;

		if (strcmp(status, "auto") == 0) {
			new_choice = alternative_set_auto(a);
		} else if (alternative_has_choice(a, choice)) {
			new_choice = alternative_set_manual(a, choice);
		} else {
			pr(_("Alternative %s unchanged because choice "
			     "%s is not available."), name, choice);
		}

		if (new_choice) {
			const char *current_choice;

			current_choice = alternative_get_current(a);
			alternative_select_mode(a, current_choice);

			alternative_update(a, current_choice, new_choice);
		}
	} else {
		pr(_("Skip unknown alternative %s."), name);
	}
}

static void
alternative_set_selections(FILE *input, const char *desc)
{
	struct alternative_map *alt_map_obj;

	alt_map_obj = alternative_map_new(NULL, NULL);
	alternative_map_load_names(alt_map_obj);

	for (;;) {
		char line[1024], *res, *name, *status, *choice;
		size_t len, i;

		errno = 0;
		/* Can't use scanf("%s %s %s") because choice can
		 * contain a space */
		res = fgets(line, sizeof(line), input);
		if (res == NULL && errno) {
			syserr(_("read error in %.250s"), desc);
		} else if (res == NULL) {
			break;
		}
		len = strlen(line);
		if (len == 0 || line[len - 1] != '\n') {
			error(_("line too long or not terminated while "
			        "trying to read %s"), desc);
		}
		line[len - 1] = '\0';
		len--;

		/* Delimit name string in line */
		i = 0;
		name = line;
		while (i < len && !isblank(line[i]))
			i++;
		if (i >= len) {
			printf("[%s %s] ", PROGNAME, "--set-selections");
			pr(_("Skip invalid line: %s"), line);
			continue;
		}
		line[i++] = '\0';
		while (i < len && isblank(line[i]))
			i++;

		/* Delimit status string in line */
		status = line + i;
		while (i < len && !isblank(line[i]))
			i++;
		if (i >= len) {
			printf("[%s %s] ", PROGNAME, "--set-selections");
			pr(_("Skip invalid line: %s"), line);
			continue;
		}
		line[i++] = '\0';
		while (i < len && isblank(line[i]))
			i++;

		/* Delimit choice string in the line */
		if (i >= len) {
			printf("[%s %s] ", PROGNAME, "--set-selections");
			pr(_("Skip invalid line: %s"), line);
			continue;
		}
		choice = line + i;

		printf("[%s %s] ", PROGNAME, "--set-selections");
		alternative_set_selection(alt_map_obj, name, status, choice);
	}

	alternative_map_free(alt_map_obj);
}

static void
alternative_check_name(const char *name)
{
	if (strpbrk(name, "/ \t"))
		error(_("alternative name (%s) must not contain '/' "
		        "and spaces"), name);
}

static void
alternative_check_link(const char *linkname)
{
	if (linkname[0] != '/')
		error(_("alternative link is not absolute as it should be: %s"),
		      linkname);
}

static void
alternative_check_path(const char *file)
{
	if (!file || file[0] != '/')
		error(_("alternative path is not absolute as it should be: %s"),
		      file);
}

/**
 * Check the alternative installation arguments.
 *
 * That the caller doesn't mix links between alternatives, doesn't mix
 * alternatives between slave/master, and that the various parameters
 * are fine.
 */
static void
alternative_check_install_args(struct alternative *inst_alt,
                               struct fileset *fileset)
{
	struct alternative_map *alt_map_links, *alt_map_parent;
	struct alternative *found;
	struct slave_link *sl;
	struct stat st;

	alternative_check_name(inst_alt->master_name);
	alternative_check_link(inst_alt->master_link);
	alternative_check_path(fileset->master_file);

	/* Load information about all alternatives to check for mistakes. */
	alt_map_links = alternative_map_new(NULL, NULL);
	alt_map_parent = alternative_map_new(NULL, NULL);
	alternative_map_load_tree(alt_map_links, alt_map_parent);

	found = alternative_map_find(alt_map_parent, inst_alt->master_name);
	if (found && strcmp(found->master_name, inst_alt->master_name) != 0) {
		error(_("alternative %s can't be master: it is a slave of %s"),
		      inst_alt->master_name, found->master_name);
	}

	found = alternative_map_find(alt_map_links, inst_alt->master_link);
	if (found && strcmp(found->master_name, inst_alt->master_name) != 0) {
		found = alternative_map_find(alt_map_parent,
		                             found->master_name);
		error(_("alternative link %s is already managed by %s"),
		      inst_alt->master_link, found->master_name);
	}

	if (stat(fileset->master_file, &st) == -1) {
		if (errno == ENOENT)
			error(_("alternative path %s doesn't exist"),
			      fileset->master_file);
		else
			syserr(_("cannot stat file '%s'"), fileset->master_file);
	}

	for (sl = inst_alt->slaves; sl; sl = sl->next) {
		const char *file = fileset_get_slave(fileset, sl->name);

		alternative_check_name(sl->name);
		alternative_check_link(sl->link);
		alternative_check_path(file);

		found = alternative_map_find(alt_map_parent, sl->name);
		if (found &&
		    strcmp(found->master_name, inst_alt->master_name) != 0) {
			if (strcmp(found->master_name, sl->name) == 0)
				error(_("alternative %s can't be slave of %s: "
				        "it is a master alternative"),
				      sl->name, inst_alt->master_name);
			else
				error(_("alternative %s can't be slave of %s: "
				        "it is a slave of %s"),
				      sl->name, inst_alt->master_name,
				      found->master_name);
		}

		found = alternative_map_find(alt_map_links, sl->link);
		if (found &&
		    strcmp(found->master_name, inst_alt->master_name) != 0) {
			error(_("alternative link %s is already "
			        "managed by %s"), sl->link,
			      found->master_name);
		}
		if (found) {
			struct slave_link *sl2;

			for (sl2 = found->slaves; sl2; sl2 = sl2->next)
				if (strcmp(sl2->link, sl->link) == 0)
					break;
			if (sl2 && strcmp(sl2->name, sl->name) != 0)
				error(_("alternative link %s is already "
				        "managed by %s (slave of %s)"),
				      sl->link, sl2->name,
				      found->master_name);
		}
	}

	alternative_map_free(alt_map_links);
	alternative_map_free(alt_map_parent);
}

/*
 * Main program
 */

#define MISSING_ARGS(nb) (argc < i + nb + 1)

int
main(int argc, char **argv)
{
	/* Alternative worked on. */
	struct alternative *a = NULL;
	/* Alternative to install. */
	struct alternative *inst_alt = NULL;
	/* Set of files to install in the alternative. */
	struct fileset *fileset = NULL;
	/* Path of alternative we are offering. */
	char *path = NULL;
	const char *current_choice = NULL;
	const char *new_choice = NULL;
	bool modifies_alt = false;
	bool modifies_sys = false;
	int i = 0;

	setlocale(LC_ALL, "");
	bindtextdomain(PACKAGE, LOCALEDIR);
	textdomain(PACKAGE);

	admdir = admindir_init();

	if (setvbuf(stdout, NULL, _IONBF, 0))
		syserr("setvbuf failed");

	prog_path = argv[0];

	for (i = 1; i < argc; i++) {
		if (strstr(argv[i], "--") != argv[i]) {
			error(_("unknown argument '%s'"), argv[i]);
		} else if (strcmp("--help", argv[i]) == 0) {
			usage();
			exit(0);
		} else if (strcmp("--version", argv[i]) == 0) {
			version();
			exit(0);
		} else if (strcmp("--verbose", argv[i]) == 0) {
			opt_verbose++;
		} else if (strcmp("--quiet", argv[i]) == 0) {
			opt_verbose--;
		} else if (strcmp("--install", argv[i]) == 0) {
			char *prio_str, *prio_end;
			long prio;

			set_action("install");
			if (MISSING_ARGS(4))
				badusage(_("--install needs <link> <name> "
				           "<path> <priority>"));

			prio_str = argv[i + 4];

			if (strcmp(argv[i+1], argv[i+3]) == 0)
				badusage(_("<link> and <path> can't be the same"));
			errno = 0;
			prio = strtol(prio_str, &prio_end, 10);
			if (prio_str == prio_end || *prio_end != '\0')
				badusage(_("priority must be an integer"));
			if (prio < INT_MIN || prio > INT_MAX || errno == ERANGE)
				badusage(_("priority is out of range"));

			a = alternative_new(argv[i + 2]);
			inst_alt = alternative_new(argv[i + 2]);
			alternative_set_status(inst_alt, ALT_ST_AUTO);
			alternative_set_link(inst_alt, xstrdup(argv[i + 1]));
			fileset = fileset_new(argv[i + 3], prio);

			i += 4;
		} else if (strcmp("--remove", argv[i]) == 0 ||
			   strcmp("--set", argv[i]) == 0) {
			set_action(argv[i] + 2);
			if (MISSING_ARGS(2))
				badusage(_("--%s needs <name> <path>"), argv[i] + 2);

			a = alternative_new(argv[i + 1]);
			path = xstrdup(argv[i + 2]);

			alternative_check_name(a->master_name);
			alternative_check_path(path);

			i += 2;
		} else if (strcmp("--display", argv[i]) == 0 ||
			   strcmp("--query", argv[i]) == 0 ||
			   strcmp("--auto", argv[i]) == 0 ||
			   strcmp("--config", argv[i]) == 0 ||
			   strcmp("--list", argv[i]) == 0 ||
			   strcmp("--remove-all", argv[i]) == 0) {
			set_action(argv[i] + 2);
			if (MISSING_ARGS(1))
				badusage(_("--%s needs <name>"), argv[i] + 2);
			a = alternative_new(argv[i + 1]);

			alternative_check_name(a->master_name);

			i++;
		} else if (strcmp("--all", argv[i]) == 0 ||
			   strcmp("--get-selections", argv[i]) == 0 ||
			   strcmp("--set-selections", argv[i]) == 0) {
			set_action(argv[i] + 2);
		} else if (strcmp("--slave", argv[i]) == 0) {
			char *slink, *sname, *spath;
			struct slave_link *sl;

			if (action == NULL ||
			    (action && strcmp(action, "install") != 0))
				badusage(_("--slave only allowed with --install"));
			if (MISSING_ARGS(3))
				badusage(_("--slave needs <link> <name> <path>"));

			slink = xstrdup(argv[i + 1]);
			sname = xstrdup(argv[i + 2]);
			spath = xstrdup(argv[i + 3]);

			if (strcmp(slink, spath) == 0)
				badusage(_("<link> and <path> can't be the same"));
			if (strcmp(inst_alt->master_name, sname) == 0)
				badusage(_("name %s is both primary and slave"),
				         sname);
			if (strcmp(slink, inst_alt->master_link) == 0)
				badusage(_("link %s is both primary and slave"),
				         slink);
			if (alternative_has_slave(inst_alt, sname))
				badusage(_("duplicate slave name %s"), sname);

			for (sl = inst_alt->slaves; sl; sl = sl->next) {
				const char *linkname = sl->link;
				if (linkname == NULL)
					linkname = "";
				if (strcmp(linkname, slink) == 0)
					badusage(_("duplicate slave link %s"),
					          slink);
			}

			alternative_add_slave(inst_alt, sname, slink);
			fileset_add_slave(fileset, xstrdup(sname), spath);

			i+= 3;
		} else if (strcmp("--log", argv[i]) == 0) {
			if (MISSING_ARGS(1))
				badusage(_("--%s needs a <file> argument"), "log");
			log_file = argv[i + 1];
			i++;
		} else if (strcmp("--altdir", argv[i]) == 0) {
			if (MISSING_ARGS(1))
				badusage(_("--%s needs a <directory> argument"), "log");
			altdir = argv[i + 1];
			i++;
		} else if (strcmp("--admindir", argv[i]) == 0) {
			if (MISSING_ARGS(1))
				badusage(_("--%s needs a <directory> argument"), "log");
			admdir = argv[i + 1];
			i++;
		} else if (strcmp("--skip-auto", argv[i]) == 0) {
			opt_skip_auto = 1;
		} else if (strcmp("--force", argv[i]) == 0) {
			opt_force = 1;
		} else {
			badusage(_("unknown option '%s'"), argv[i]);
		}
	}

	if (!action)
		badusage(_("need --display, --query, --list, --get-selections, "
		           "--config, --set, --set-selections, --install, "
		           "--remove, --all, --remove-all or --auto"));

	/* The following actions might modify the current alternative. */
	if (strcmp(action, "set") == 0 ||
	    strcmp(action, "auto") == 0 ||
	    strcmp(action, "config") == 0 ||
	    strcmp(action, "remove") == 0 ||
	    strcmp(action, "remove-all") == 0 ||
	    strcmp(action, "install") == 0)
		modifies_alt = true;

	/* The following actions might modify the system somehow. */
	if (modifies_alt ||
	    strcmp(action, "all") == 0 ||
	    strcmp(action, "set-selections") == 0)
		modifies_sys = true;

	if (strcmp(action, "install") == 0)
		alternative_check_install_args(inst_alt, fileset);

	if (strcmp(action, "display") == 0 ||
	    strcmp(action, "query") == 0 ||
	    strcmp(action, "list") == 0 ||
	    strcmp(action, "set") == 0 ||
	    strcmp(action, "auto") == 0 ||
	    strcmp(action, "config") == 0 ||
	    strcmp(action, "remove-all") == 0) {
		/* Load the alternative info, stop on failure. */
		if (!alternative_load(a, ALTDB_WARN_PARSER))
			error(_("no alternatives for %s"), a->master_name);
	} else if (strcmp(action, "remove") == 0) {
		/* FIXME: Be consistent for now with the case when we
		 * try to remove a non-existing path from an existing
		 * link group file. */
		if (!alternative_load(a, ALTDB_WARN_PARSER)) {
			verbose(_("no alternatives for %s"), a->master_name);
			exit(0);
		}
	} else if (strcmp(action, "install") == 0) {
		/* Load the alternative info, ignore failures. */
		alternative_load(a, ALTDB_WARN_PARSER);
	}

	if (modifies_sys)
		log_msg("run with %s", get_argv_string(argc, argv));

	if (modifies_alt) {
		current_choice = alternative_get_current(a);
		alternative_select_mode(a, current_choice);
	}

	/* Handle actions. */
	if (strcmp(action, "all") == 0) {
		alternative_config_all();
	} else if (strcmp(action, "get-selections") == 0) {
		alternative_get_selections();
	} else if (strcmp(action, "set-selections") == 0) {
		alternative_set_selections(stdin, _("<standard input>"));
	} else if (strcmp(action, "display") == 0) {
		alternative_display_user(a);
	} else if (strcmp(action, "query") == 0) {
		alternative_display_query(a);
	} else if (strcmp(action, "list") == 0) {
		alternative_display_list(a);
	} else if (strcmp(action, "set") == 0) {
		new_choice = alternative_set_manual(a, path);
	} else if (strcmp(action, "auto") == 0) {
		new_choice = alternative_set_auto(a);
	} else if (strcmp(action, "config") == 0) {
		new_choice = alternative_config(a, current_choice);
	} else if (strcmp(action, "remove") == 0) {
		new_choice = alternative_remove(a, current_choice, path);
	} else if (strcmp(action, "remove-all") == 0) {
		alternative_choices_free(a);
	} else if (strcmp(action, "install") == 0) {
		if (a->master_link) {
			/* Alternative already exists, check if anything got
			 * updated. */
			alternative_evolve(a, inst_alt, current_choice, fileset);
		} else {
			/* Alternative doesn't exist, create from parameters. */
			alternative_free(a);
			a = inst_alt;
		}
		alternative_add_choice(a, fileset);
		if (a->status == ALT_ST_AUTO) {
			new_choice = alternative_get_best(a)->master_file;
		} else {
			verbose(_("automatic updates of %s/%s are disabled; "
			          "leaving it alone"), altdir, a->master_name);
			verbose(_("to return to automatic updates use "
			          "'%s --auto %s'"), PROGNAME, a->master_name);
		}
	}

	if (modifies_alt)
		alternative_update(a, current_choice, new_choice);

	return 0;
}
