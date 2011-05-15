/*
 * libdpkg - Debian packaging suite library routines
 * dpkg.h - general header for Debian package handling
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000,2001 Wichert Akkerman <wichert@debian.org>
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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef LIBDPKG_DPKG_H
#define LIBDPKG_DPKG_H

#include <sys/types.h>

#include <stddef.h>
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

#define DEFAULTSHELL        "sh"
#define DEFAULTPAGER        "pager"

#define MD5HASHLEN           32
#define MAXTRIGDIRECTIVE     256

#define BACKEND		"dpkg-deb"
#define DPKGQUERY	"dpkg-query"
#define SPLITTER	"dpkg-split"
#define DPKG		"dpkg"
#define DEBSIGVERIFY	"/usr/bin/debsig-verify"

#define TAR		"tar"
#define RM		"rm"
#define FIND		"find"
#define DIFF		"diff"

#define FIND_EXPRSTARTCHARS "-(),!"

#include <dpkg/ehandle.h>

/*** from startup.c ***/

#define standard_startup() do { \
  push_error_context(); \
  /* Make sure all our status databases are readable. */ \
  umask(022); \
} while (0)

#define standard_shutdown() do { \
  pop_error_context(ehflag_normaltidy); \
} while (0)

/*** log.c ***/

extern const char *log_file;
void log_message(const char *fmt, ...) DPKG_ATTR_PRINTF(1);

void statusfd_add(int fd);
void statusfd_send(const char *fmt, ...) DPKG_ATTR_PRINTF(1);

/*** cleanup.c ***/

void cu_closestream(int argc, void **argv);
void cu_closepipe(int argc, void **argv);
void cu_closedir(int argc, void **argv);
void cu_closefd(int argc, void **argv);

/*** from mlib.c ***/

void setcloexec(int fd, const char* fn);
void *m_malloc(size_t);
void *m_realloc(void*, size_t);
char *m_strdup(const char *str);
int m_asprintf(char **strp, const char *fmt, ...) DPKG_ATTR_PRINTF(2);
void m_dup2(int oldfd, int newfd);
void m_pipe(int fds[2]);
void m_output(FILE *f, const char *name);

/*** from utils.c ***/

int cisdigit(int c);
int cisalpha(int c);
int cisspace(int c);

int fgets_checked(char *buf, size_t bufsz, FILE *f, const char *fn);
int fgets_must(char *buf, size_t bufsz, FILE *f, const char *fn);

DPKG_END_DECLS

#endif /* LIBDPKG_DPKG_H */
