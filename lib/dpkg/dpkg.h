/*
 * libdpkg - Debian packaging suite library routines
 * dpkg.h - general header for Debian package handling
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000,2001 Wichert Akkerman <wichert@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2,
 * or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#ifndef DPKG_H
#define DPKG_H

#ifdef HAVE_SYS_CDEFS_H
#include <sys/cdefs.h>
#endif
#include <sys/types.h>

#include <setjmp.h>
#ifdef HAVE_STDDEF_H
#include <stddef.h>
#endif
#include <stdarg.h>
#include <stdio.h>

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

#define MAXCONFFILENAME     1000
#define MAXDIVERTFILENAME   1024
#define MAXCONTROLFILENAME  100
#define DEBEXT             ".deb"
#define OLDDBEXT           "-old"
#define NEWDBEXT           "-new"
#define REMOVECONFFEXTS    "~", ".bak", "%", \
                           DPKGTEMPEXT, DPKGNEWEXT, DPKGOLDEXT, DPKGDISTEXT

#define DPKG_VERSION_ARCH  PACKAGE_VERSION " (" ARCHITECTURE ")"

#define NEWCONFFILEFLAG    "newconffile"
#define NONEXISTENTFLAG    "nonexistent"

#define DPKGTEMPEXT        ".dpkg-tmp"
#define DPKGNEWEXT         ".dpkg-new"
#define DPKGOLDEXT         ".dpkg-old"
#define DPKGDISTEXT        ".dpkg-dist"

#define CONTROLFILE        "control"
#define CONFFILESFILE      "conffiles"
#define PREINSTFILE        "preinst"
#define POSTINSTFILE       "postinst"
#define PRERMFILE          "prerm"
#define POSTRMFILE         "postrm"
#define TRIGGERSCIFILE     "triggers"

#define STATUSFILE        "status"
#define AVAILFILE         "available"
#define LOCKFILE          "lock"
#define DIVERSIONSFILE    "diversions"
#define STATOVERRIDEFILE  "statoverride"
#define UPDATESDIR        "updates/"
#define INFODIR           "info/"
#define TRIGGERSDIR       "triggers/"
#define TRIGGERSFILEFILE  "File"
#define TRIGGERSDEFERREDFILE "Unincorp"
#define TRIGGERSLOCKFILE  "Lock"
#define CONTROLDIRTMP     "tmp.ci/"
#define IMPORTANTTMP      "tmp.i"
#define REASSEMBLETMP     "reassemble" DEBEXT
#define IMPORTANTMAXLEN    10
#define IMPORTANTFMT      "%04d"
#define MAXUPDATES         250

#define MAINTSCRIPTPKGENVVAR "DPKG_MAINTSCRIPT_PACKAGE"
#define MAINTSCRIPTARCHENVVAR "DPKG_MAINTSCRIPT_ARCH"
#define MAINTSCRIPTDPKGENVVAR "DPKG_RUNNING_VERSION"

#define NOJOBCTRLSTOPENV    "DPKG_NO_TSTP"
#define SHELLENV            "SHELL"
#define DEFAULTSHELL        "sh"
#define PAGERENV            "PAGER"
#define DEFAULTPAGER        "pager"

#define PKGSCRIPTMAXARGS     10
#define MD5HASHLEN           32
#define MAXTRIGDIRECTIVE     256

#define ARCHIVE_FILENAME_PATTERN "*.deb"

#define BACKEND		"dpkg-deb"
#define DPKGQUERY	"dpkg-query"
#define SPLITTER	"dpkg-split"
#define DPKG		"dpkg"
#define DEBSIGVERIFY	"/usr/bin/debsig-verify"

#define TAR		"tar"
#define GZIP		"gzip"
#define BZIP2		"bzip2"
#define LZMA		"lzma"
#define RM		"rm"
#define FIND		"find"
#define DIFF		"diff"

#define FIND_EXPRSTARTCHARS "-(),!"

#define TARBLKSZ	512

extern const char thisname[]; /* defined separately in each program */

/*** from startup.c ***/

#define standard_startup(ejbuf) do {\
  if (setjmp(*ejbuf)) { /* expect warning about possible clobbering of argv */\
    error_unwind(ehflag_bombout); exit(2);\
  }\
  push_error_handler(ejbuf, print_error_fatal, NULL); \
  umask(022); /* Make sure all our status databases are readable. */\
} while (0)

#define standard_shutdown() do { \
  set_error_display(NULL, NULL); \
  error_unwind(ehflag_normaltidy);\
} while (0)

/*** from ehandle.c ***/

extern volatile int onerr_abort;

typedef void error_printer(const char *emsg, const char *contextstring);

void push_error_handler(jmp_buf *jbufp, error_printer *printerror,
                        const char *contextstring);
void set_error_display(error_printer *printerror, const char *contextstring);
void print_error_fatal(const char *emsg, const char *contextstring);
void error_unwind(int flagset);
void push_cleanup(void (*f1)(int argc, void **argv), int flagmask1,
                  void (*f2)(int argc, void **argv), int flagmask2,
                  unsigned int nargs, ...);
void push_checkpoint(int mask, int value);
void pop_cleanup(int flagset);
enum { ehflag_normaltidy=01, ehflag_bombout=02, ehflag_recursiveerror=04 };

void do_internerr(const char *file, int line, const char *fmt, ...) DPKG_ATTR_NORET;
#if HAVE_C99
#define internerr(...) do_internerr(__FILE__, __LINE__, __VA_ARGS__)
#else
#define internerr(args...) do_internerr(__FILE__, __LINE__, args)
#endif

void ohshit(const char *fmt, ...) DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1);
void ohshitv(const char *fmt, va_list al) DPKG_ATTR_NORET;
void ohshite(const char *fmt, ...) DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1);
void werr(const char *what) DPKG_ATTR_NORET;
void warning(const char *fmt, ...) DPKG_ATTR_PRINTF(1);

/*** log.c ***/

extern const char *log_file;
void log_message(const char *fmt, ...) DPKG_ATTR_PRINTF(1);

/* FIXME: pipef and status_pipes should not be publicly exposed. */
struct pipef {
  int fd;
  struct pipef *next;
};
extern struct pipef *status_pipes;

void statusfd_send(const char *fmt, ...);

/*** cleanup.c ***/

void cu_closefile(int argc, void **argv);
void cu_closepipe(int argc, void **argv);
void cu_closedir(int argc, void **argv);
void cu_closefd(int argc, void **argv);

/*** lock.c ***/

void lock_file(int *lockfd, const char *filename,
               const char *emsg, const char *emsg_eagain);
void unlock_file(void);

/*** from mlib.c ***/

void setcloexec(int fd, const char* fn);
void *m_malloc(size_t);
void *m_realloc(void*, size_t);
char *m_strdup(const char *str);
int m_fork(void);
void m_dup2(int oldfd, int newfd);
void m_pipe(int fds[2]);
void m_output(FILE *f, const char *name);

/*** from utils.c ***/

int cisdigit(int c);
int cisalpha(int c);
int cisspace(int c);

int fgets_checked(char *buf, size_t bufsz, FILE *f, const char *fn);
int fgets_must(char *buf, size_t bufsz, FILE *f, const char *fn);

/*** from compression.c ***/

enum compress_type {
  compress_type_cat,
  compress_type_gzip,
  compress_type_bzip2,
  compress_type_lzma,
};

void decompress_cat(enum compress_type type, int fd_in, int fd_out,
                    char *desc, ...) DPKG_ATTR_NORET DPKG_ATTR_PRINTF(4);
void compress_cat(enum compress_type type, int fd_in, int fd_out,
                  const char *compression, char *desc, ...)
                  DPKG_ATTR_NORET DPKG_ATTR_PRINTF(5);

DPKG_END_DECLS

#endif /* DPKG_H */
