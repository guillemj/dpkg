/*
 * libdpkg - Debian packaging suite library routines
 * dpkg.h - general header for Debian package handling
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2000,2001 Wichert Akkerman <wichert@debian.org>
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

#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/types.h>

#include <myopt.h>

#ifdef HAVE_SYS_CDEFS_H
#include <sys/cdefs.h>
#endif

#ifdef HAVE_STDDEF_H
#include <stddef.h>
#endif

#ifdef PATH_MAX
# define INTERPRETER_MAX PATH_MAX
#else
# define INTERPRETER_MAX 1024
#endif

#define ARCHIVEVERSION     "2.0"
#define SPLITVERSION       "2.1"
#define OLDARCHIVEVERSION  "0.939000"
#define SPLITPARTDEFMAX    (450*1024)
#define MAXFIELDNAME        200
#define MAXCONFFILENAME     1000
#define MAXDIVERTFILENAME   1024
#define MAXCONTROLFILENAME  100
#define BUILDCONTROLDIR    "DEBIAN"
#define EXTRACTCONTROLDIR   BUILDCONTROLDIR
#define DEBEXT             ".deb"
#define OLDDBEXT           "-old"
#define NEWDBEXT           "-new"
#define OLDOLDDEBDIR       ".DEBIAN"
#define OLDDEBDIR          "DEBIAN"
#define REMOVECONFFEXTS    "~", ".bak", "%", \
                           DPKGTEMPEXT, DPKGNEWEXT, DPKGOLDEXT, DPKGDISTEXT

#ifndef ARCHBINFMT
#define ARCHBINFMT
#endif
#define DPKG_VERSION_ARCH  PACKAGE_VERSION " (" ARCHITECTURE ARCHBINFMT ")"

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
#define LISTFILE           "list"

#define STATUSFILE        "status"
#define AVAILFILE         "available"
#define LOCKFILE          "lock"
#define CMETHOPTFILE      "cmethopt"
#define METHLOCKFILE      "methlock"
#define DIVERSIONSFILE    "diversions"
#define STATOVERRIDEFILE  "statoverride"
#define UPDATESDIR        "updates/"
#define INFODIR           "info/"
#define PARTSDIR          "parts/"
#define CONTROLDIRTMP     "tmp.ci/"
#define IMPORTANTTMP      "tmp.i"
#define REASSEMBLETMP     "reassemble" DEBEXT
#define IMPORTANTMAXLEN    10
#define IMPORTANTFMT      "%04d" /* change => also change lib/database.c:cleanup_updates */
#define MAXUPDATES         50

#define LOCALLIBDIR         "/usr/local/lib/dpkg"
#define METHODSDIR          "methods"

#define NOJOBCTRLSTOPENV    "DPKG_NO_TSTP"
#define SHELLENV            "SHELL"
#define DEFAULTSHELL        "sh"
#define PAGERENV            "PAGER"
#define DEFAULTPAGER        "pager"

#define IMETHODMAXLEN        50
#define IOPTIONMAXLEN        IMETHODMAXLEN
#define METHODOPTIONSFILE   "names"
#define METHODSETUPSCRIPT   "setup"
#define METHODUPDATESCRIPT  "update"
#define METHODINSTALLSCRIPT "install"
#define OPTIONSDESCPFX      "desc."
#define OPTIONINDEXMAXLEN    5

#define PKGSCRIPTMAXARGS     10
#define MD5HASHLEN           32

#define CONFFOPTCELLS  /* int conffoptcells[2] {* 1= user edited *}              \
                                           [2] {* 1= distributor edited *} = */  \
                                  /* dist not */     /* dist edited */           \
   /* user did not edit */    {     cfo_keep,           cfo_install    },        \
   /* user did edit     */    {     cfo_keep,         cfo_prompt_keep  }

#define ARCHIVE_FILENAME_PATTERN "*.deb"

#define BACKEND		"dpkg-deb"
#define DPKGQUERY	"dpkg-query"
#define SPLITTER	"dpkg-split"
#define DSELECT		"dselect"
#define DPKG		"dpkg"
#define DEBSIGVERIFY	"/usr/bin/debsig-verify"

#define TAR		"tar"
#define GZIP		"gzip"
#define BZIP2		"bzip2"
#define RM		"rm"
#define FIND		"find"
#define SHELL		"sh"
#define DIFF		"diff"

#define SHELLENVIR	"SHELL"

#define FIND_EXPRSTARTCHARS "-(),!"

#define TARBLKSZ	512

extern const char thisname[]; /* defined separately in each program */
extern const char printforhelp[];

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

/*** from startup.c ***/

#define standard_startup(ejbuf, argc, argv, prog, loadcfg, cmdinfos) do {\
  setlocale(LC_ALL, "");\
  bindtextdomain(PACKAGE, LOCALEDIR);\
  textdomain(PACKAGE);\
  if (setjmp(*ejbuf)) { /* expect warning about possible clobbering of argv */\
    error_unwind(ehflag_bombout); exit(2);\
  }\
  push_error_handler(ejbuf,print_error_fatal,0);\
  umask(022); /* Make sure all our status databases are readable. */\
  if (loadcfg)\
    loadcfgfile(prog, cmdinfos);\
  myopt(argv,cmdinfos);\
} while (0)

#define standard_shutdown(freemem) do {\
  set_error_display(0,0);\
  error_unwind(ehflag_normaltidy);\
  if (freemem)\
    nffreeall();\
} while (0)

/*** from ehandle.c ***/

void push_error_handler(jmp_buf *jbufp,
                        void (*printerror)(const char *, const char *),
                        const char *contextstring);
void set_error_display(void (*printerror)(const char *, const char *),
                       const char *contextstring);
void print_error_fatal(const char *emsg, const char *contextstring);
void error_unwind(int flagset);
void push_cleanup(void (*f1)(int argc, void **argv), int flagmask1,
                  void (*f2)(int argc, void **argv), int flagmask2,
                  unsigned int nargs, ...);
void push_checkpoint(int mask, int value);
void pop_cleanup(int flagset);
enum { ehflag_normaltidy=01, ehflag_bombout=02, ehflag_recursiveerror=04 };

void do_internerr(const char *string, int line, const char *file) NONRETURNING;
#define internerr(s) do_internerr(s,__LINE__,__FILE__)

struct varbuf;
void ohshit(const char *fmt, ...) NONRETURNPRINTFFORMAT(1,2);
void ohshitv(const char *fmt, va_list al) NONRETURNING;
void ohshite(const char *fmt, ...) NONRETURNPRINTFFORMAT(1,2);
void ohshitvb(struct varbuf*) NONRETURNING;
void badusage(const char *fmt, ...) NONRETURNPRINTFFORMAT(1,2);
void werr(const char *what) NONRETURNING;
void warningf(const char *fmt, ...);

/*** from mlib.c ***/

void setcloexec(int fd, const char* fn);
void *m_malloc(size_t);
void *m_realloc(void*, size_t);
int m_fork(void);
void m_dup2(int oldfd, int newfd);
void m_pipe(int fds[2]);

#define PROCPIPE 1
#define PROCWARN 2
#define PROCNOERR 4
int checksubprocerr(int status, const char *description, int flags);
int waitsubproc(pid_t pid, const char *description, int flags);

#define BUFFER_WRITE_BUF 0
#define BUFFER_WRITE_VBUF 1
#define BUFFER_WRITE_FD 2
#define BUFFER_WRITE_NULL 3
#define BUFFER_WRITE_STREAM 4
#define BUFFER_WRITE_MD5 5
#define BUFFER_READ_FD 0
#define BUFFER_READ_STREAM 1

#define BUFFER_WRITE_SETUP 1 << 16
#define BUFFER_READ_SETUP 1 << 17
#define BUFFER_WRITE_SHUTDOWN 1 << 18
#define BUFFER_READ_SHUTDOWN 1 << 19

typedef struct buffer_data *buffer_data_t;
typedef off_t (*buffer_proc_t)(buffer_data_t data, void *buf, off_t size, const char *desc);
typedef union buffer_arg {
  void *ptr;
  int i;
} buffer_arg;

struct buffer_data {
  buffer_proc_t proc;
  buffer_arg data;
  int type;
};

#if HAVE_C99
# define fd_md5(fd, hash, limit, ...)\
	buffer_copy_setup_IntPtr(fd, BUFFER_READ_FD, NULL, \
			 	 hash, BUFFER_WRITE_MD5, NULL, \
				 limit, __VA_ARGS__)
# define stream_md5(file, hash, limit, ...)\
	buffer_copy_setup_PtrPtr(file, BUFFER_READ_STREAM, NULL, \
				 hash, BUFFER_WRITE_MD5, NULL, \
				 limit, __VA_ARGS__)
# define fd_fd_copy(fd1, fd2, limit, ...)\
	buffer_copy_setup_IntInt(fd1, BUFFER_READ_FD, NULL, \
				 fd2, BUFFER_WRITE_FD, NULL, \
				 limit, __VA_ARGS__)
# define fd_buf_copy(fd, buf, limit, ...)\
	buffer_copy_setup_IntPtr(fd, BUFFER_READ_FD, NULL, \
				 buf, BUFFER_WRITE_BUF, NULL, \
				 limit, __VA_ARGS__)
# define fd_vbuf_copy(fd, buf, limit, ...)\
	buffer_copy_setup_IntPtr(fd, BUFFER_READ_FD, NULL, \
				 buf, BUFFER_WRITE_VBUF, NULL, \
				 limit, __VA_ARGS__)
# define fd_null_copy(fd, limit, ...) \
	if (lseek(fd, limit, SEEK_CUR) == -1) { \
	    if(errno != ESPIPE) ohshite(__VA_ARGS__); \
	    buffer_copy_setup_IntPtr(fd, BUFFER_READ_FD, NULL, \
				     0, BUFFER_WRITE_NULL, NULL, \
				     limit, __VA_ARGS__);\
	}
# define stream_null_copy(file, limit, ...) \
	if (fseek(file, limit, SEEK_CUR) == -1) { \
	    if(errno != EBADF) ohshite(__VA_ARGS__); \
	    buffer_copy_setup_PtrPtr(file, BUFFER_READ_STREAM, NULL, \
				     0, BUFFER_WRITE_NULL, NULL, \
				     limit, __VA_ARGS__);\
	}
# define stream_fd_copy(file, fd, limit, ...)\
	buffer_copy_setup_PtrInt(file, BUFFER_READ_STREAM, NULL, \
				 fd, BUFFER_WRITE_FD, NULL, \
				 limit, __VA_ARGS__)
#else /* HAVE_C99 */
# define fd_md5(fd, hash, limit, desc...)\
	buffer_copy_setup_IntPtr(fd, BUFFER_READ_FD, NULL, \
			 	 hash, BUFFER_WRITE_MD5, NULL, \
				 limit, desc)
# define stream_md5(file, hash, limit, desc...)\
	buffer_copy_setup_PtrPtr(file, BUFFER_READ_STREAM, NULL, \
				 hash, BUFFER_WRITE_MD5, NULL, \
				 limit, desc)
# define fd_fd_copy(fd1, fd2, limit, desc...)\
	buffer_copy_setup_IntInt(fd1, BUFFER_READ_FD, NULL, \
				 fd2, BUFFER_WRITE_FD, NULL, \
				 limit, desc)
# define fd_buf_copy(fd, buf, limit, desc...)\
	buffer_copy_setup_IntPtr(fd, BUFFER_READ_FD, NULL, \
				 buf, BUFFER_WRITE_BUF, NULL, \
				 limit, desc)
# define fd_vbuf_copy(fd, buf, limit, desc...)\
	buffer_copy_setup_IntPtr(fd, BUFFER_READ_FD, NULL, \
				 buf, BUFFER_WRITE_VBUF, NULL, \
				 limit, desc)
# define fd_null_copy(fd, limit, desc...) \
	if (lseek(fd, limit, SEEK_CUR) == -1) { \
	    if(errno != ESPIPE) ohshite(desc); \
	    buffer_copy_setup_IntPtr(fd, BUFFER_READ_FD, NULL, \
				     0, BUFFER_WRITE_NULL, NULL, \
				     limit, desc);\
	}
# define stream_null_copy(file, limit, desc...) \
	if (fseek(file, limit, SEEK_CUR) == -1) { \
	    if(errno != EBADF) ohshite(desc); \
	    buffer_copy_setup_PtrPtr(file, BUFFER_READ_STREAM, NULL, \
				     0, BUFFER_WRITE_NULL, NULL, \
				     limit, desc);\
	}
# define stream_fd_copy(file, fd, limit, desc...)\
	buffer_copy_setup_PtrInt(file, BUFFER_READ_STREAM, NULL, \
				 fd, BUFFER_WRITE_FD, NULL, \
				 limit, desc)
#endif /* HAVE_C99 */

off_t buffer_copy_setup_PtrInt(void *p, int typeIn, void *procIn,
					int i, int typeOut, void *procOut,
					off_t limit, const char *desc, ...);
off_t buffer_copy_setup_PtrPtr(void *p1, int typeIn, void *procIn,
					void *p2, int typeOut, void *procOut,
					off_t limit, const char *desc, ...);
off_t buffer_copy_setup_IntPtr(int i, int typeIn, void *procIn,
					void *p, int typeOut, void *procOut,
					off_t limit, const char *desc, ...);
off_t buffer_copy_setup_IntInt(int i1, int typeIn, void *procIn,
					int i2, int typeOut, void *procOut,
					off_t limit, const char *desc, ...);
off_t buffer_copy_setup(buffer_arg argIn, int typeIn, void *procIn,
		       buffer_arg argOut, int typeOut, void *procOut,
		       off_t limit, const char *desc);
off_t buffer_write(buffer_data_t data, void *buf, off_t length, const char *desc);
off_t buffer_read(buffer_data_t data, void *buf, off_t length, const char *desc);
off_t buffer_copy(buffer_data_t read_data, buffer_data_t write_data, off_t limit, const char *desc);

extern volatile int onerr_abort;

/*** from showcright.c ***/

struct cmdinfo;
void showcopyright(const struct cmdinfo*, const char*);

/*** from utils.c ***/

int cisdigit(int c);
int cisalpha(int c);

/*** from compression.c ***/

enum compression_type { CAT, GZ, BZ2 };

void decompress_cat(enum compression_type type, int fd_in, int fd_out, char *desc, ...) NONRETURNING;
void compress_cat(enum compression_type type, int fd_in, int fd_out, const char *compression, char *desc, ...) NONRETURNING;

/*** from compat.c ***/

#ifndef HAVE_STRERROR
const char *strerror(int);
#endif

#ifndef HAVE_STRSIGNAL
const char *strsignal(int);
#endif

#ifndef HAVE_SCANDIR
struct dirent;
int scandir(const char *dir, struct dirent ***namelist,
	    int (*select)(const struct dirent *),
	    int (*compar)(const void*, const void*));
#endif

#ifndef HAVE_ALPHASORT
struct dirent;
int alphasort(const struct dirent *a, const struct dirent *b);
#endif

#ifndef HAVE_UNSETENV
void unsetenv(const char *x);
#endif

/*** other compatibility functions ***/

#ifndef HAVE_STRTOUL
#define strtoul strtol
#endif

#ifndef HAVE_VA_COPY
#define va_copy(dest, src) (dest) = (src)
#endif

/* Define WCOREDUMP if we don't have it already - coredumps won't be
 * detected, though.
 */
#ifndef WCOREDUMP
#define WCOREDUMP(x) 0
#endif

/* Set BUILDOLDPKGFORMAT to 1 to build old-format archives by default.
 *  */
#ifndef BUILDOLDPKGFORMAT
#define BUILDOLDPKGFORMAT 0
#endif

/* Take care of NLS matters.  */

#include <gettext.h>
#if HAVE_LOCALE_H
# include <locale.h>
#endif

/* Make gettext a little friendlier */
#define _(String) gettext (String)
#define N_(String) gettext_noop (String)

#endif /* DPKG_H */
