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

#include <dpkg-def.h>

DPKG_BEGIN_DECLS

#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/types.h>

#ifdef HAVE_SYS_CDEFS_H
#include <sys/cdefs.h>
#endif

#ifdef HAVE_STDDEF_H
#include <stddef.h>
#endif

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
#define LISTFILE           "list"
#define TRIGGERSCIFILE     "triggers"

#define STATUSFILE        "status"
#define AVAILFILE         "available"
#define LOCKFILE          "lock"
#define DIVERSIONSFILE    "diversions"
#define STATOVERRIDEFILE  "statoverride"
#define UPDATESDIR        "updates/"
#define INFODIR           "info/"
#define PARTSDIR          "parts/"
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
#define MAINTSCRIPTDPKGENVVAR "DPKG_RUNNING_VERSION"

#define NOJOBCTRLSTOPENV    "DPKG_NO_TSTP"
#define SHELLENV            "SHELL"
#define DEFAULTSHELL        "sh"
#define PAGERENV            "PAGER"
#define DEFAULTPAGER        "pager"

#define PKGSCRIPTMAXARGS     10
#define MD5HASHLEN           32
#define MAXTRIGDIRECTIVE     256

#define CONFFOPTCELLS  /* int conffoptcells[2] {* 1= user edited *}              \
                                           [2] {* 1= distributor edited *} = */  \
                                  /* dist not */     /* dist edited */           \
   /* user did not edit */    {     cfo_keep,           cfo_install    },        \
   /* user did edit     */    {     cfo_keep,         cfo_prompt_keep  }

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

void do_internerr(const char *file, int line, const char *fmt, ...) NONRETURNING;
#if HAVE_C99
#define internerr(...) do_internerr(__FILE__, __LINE__, __VA_ARGS__)
#else
#define internerr(args...) do_internerr(__FILE__, __LINE__, args)
#endif

struct varbuf;
void ohshit(const char *fmt, ...) NONRETURNING PRINTFFORMAT(1, 2);
void ohshitv(const char *fmt, va_list al) NONRETURNING;
void ohshite(const char *fmt, ...) NONRETURNING PRINTFFORMAT(1, 2);
void werr(const char *what) NONRETURNING;
void warning(const char *fmt, ...) PRINTFFORMAT(1, 2);

/*** log.c ***/

extern const char *log_file;
void log_message(const char *fmt, ...) PRINTFFORMAT(1, 2);

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
	                             NULL, BUFFER_WRITE_NULL, NULL, \
				     limit, __VA_ARGS__);\
	}
# define stream_null_copy(file, limit, ...) \
	if (fseek(file, limit, SEEK_CUR) == -1) { \
	    if(errno != EBADF) ohshite(__VA_ARGS__); \
	    buffer_copy_setup_PtrPtr(file, BUFFER_READ_STREAM, NULL, \
	                             NULL, BUFFER_WRITE_NULL, NULL, \
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
	                             NULL, BUFFER_WRITE_NULL, NULL, \
				     limit, desc);\
	}
# define stream_null_copy(file, limit, desc...) \
	if (fseek(file, limit, SEEK_CUR) == -1) { \
	    if(errno != EBADF) ohshite(desc); \
	    buffer_copy_setup_PtrPtr(file, BUFFER_READ_STREAM, NULL, \
	                             NULL, BUFFER_WRITE_NULL, NULL, \
				     limit, desc);\
	}
# define stream_fd_copy(file, fd, limit, desc...)\
	buffer_copy_setup_PtrInt(file, BUFFER_READ_STREAM, NULL, \
				 fd, BUFFER_WRITE_FD, NULL, \
				 limit, desc)
#endif /* HAVE_C99 */

off_t buffer_copy_setup_PtrInt(void *p, int typeIn, void *procIn,
					int i, int typeOut, void *procOut,
					off_t limit, const char *desc, ...) PRINTFFORMAT(8, 9);
off_t buffer_copy_setup_PtrPtr(void *p1, int typeIn, void *procIn,
					void *p2, int typeOut, void *procOut,
					off_t limit, const char *desc, ...) PRINTFFORMAT(8, 9);
off_t buffer_copy_setup_IntPtr(int i, int typeIn, void *procIn,
					void *p, int typeOut, void *procOut,
					off_t limit, const char *desc, ...) PRINTFFORMAT(8, 9);
off_t buffer_copy_setup_IntInt(int i1, int typeIn, void *procIn,
					int i2, int typeOut, void *procOut,
					off_t limit, const char *desc, ...) PRINTFFORMAT(8, 9);
off_t buffer_copy_setup(buffer_arg argIn, int typeIn, void *procIn,
		       buffer_arg argOut, int typeOut, void *procOut,
		       off_t limit, const char *desc);
off_t buffer_write(buffer_data_t data, void *buf, off_t length, const char *desc);
off_t buffer_read(buffer_data_t data, void *buf, off_t length, const char *desc);
off_t buffer_copy(buffer_data_t read_data, buffer_data_t write_data, off_t limit, const char *desc);

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
                    char *desc, ...) NONRETURNING PRINTFFORMAT(4, 5);
void compress_cat(enum compress_type type, int fd_in, int fd_out,
                  const char *compression, char *desc, ...)
                  NONRETURNING PRINTFFORMAT(5, 6);

DPKG_END_DECLS

#endif /* DPKG_H */
