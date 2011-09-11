/*
 * dpkg-split - splitting and joining of multipart *.deb archives
 * queue.c - queue management
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <config.h>
#include <compat.h>

#include <sys/stat.h>

#include <assert.h>
#include <limits.h>
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/dir.h>
#include <dpkg/buffer.h>
#include <dpkg/options.h>

#include "dpkg-split.h"

/*
 * The queue, by default located in /var/lib/dpkg/parts/, is a plain
 * directory with one file per part.
 *
 * Each part is named “<md5sum>.<maxpartlen>.<thispartn>.<maxpartn>”,
 * with all numbers in hex.
 */


static bool
decompose_filename(const char *filename, struct partqueue *pq)
{
  const char *p;
  char *q;

  if (strspn(filename, "0123456789abcdef") != MD5HASHLEN ||
      filename[MD5HASHLEN] != '.')
    return false;
  q = nfmalloc(MD5HASHLEN + 1);
  memcpy(q, filename, MD5HASHLEN);
  q[MD5HASHLEN] = '\0';
  pq->info.md5sum= q;
  p = filename + MD5HASHLEN + 1;
  pq->info.maxpartlen = strtoimax(p, &q, 16);
  if (q == p || *q++ != '.')
    return false;
  p = q;
  pq->info.thispartn = (int)strtol(p, &q, 16);
  if (q == p || *q++ != '.')
    return false;
  p = q;
  pq->info.maxpartn = (int)strtol(p, &q, 16);
  if (q == p || *q)
    return false;
  return true;
}

void scandepot(void) {
  DIR *depot;
  struct dirent *de;

  assert(!queue);
  depot = opendir(opt_depotdir);
  if (!depot)
    ohshite(_("unable to read depot directory `%.250s'"), opt_depotdir);
  while ((de= readdir(depot))) {
    struct partqueue *pq;
    char *p;

    if (de->d_name[0] == '.') continue;
    pq= nfmalloc(sizeof(struct partqueue));
    pq->info.fmtversion= pq->info.package= pq->info.version= NULL;
    pq->info.arch = NULL;
    pq->info.orglength= pq->info.thispartoffset= pq->info.thispartlen= 0;
    pq->info.headerlen= 0;
    p = nfmalloc(strlen(opt_depotdir) + 1 + strlen(de->d_name) + 1);
    sprintf(p, "%s/%s", opt_depotdir, de->d_name);
    pq->info.filename= p;
    if (!decompose_filename(de->d_name,pq)) {
      pq->info.md5sum= NULL;
      pq->info.maxpartlen= pq->info.thispartn= pq->info.maxpartn= 0;
    }
    pq->nextinqueue= queue;
    queue= pq;
  }
  closedir(depot);
}

static bool
partmatches(struct partinfo *pi, struct partinfo *refi)
{
  return (pi->md5sum &&
          !strcmp(pi->md5sum,refi->md5sum) &&
          pi->maxpartn == refi->maxpartn &&
          pi->maxpartlen == refi->maxpartlen);
}

int
do_auto(const char *const *argv)
{
  const char *partfile;
  struct partinfo *refi, **partlist, *otherthispart;
  struct partqueue *pq;
  unsigned int i;
  int j;
  FILE *part;

  if (!opt_outputfile)
    badusage(_("--auto requires the use of the --output option"));
  if (!(partfile= *argv++) || *argv)
    badusage(_("--auto requires exactly one part file argument"));

  refi= nfmalloc(sizeof(struct partqueue));
  part= fopen(partfile,"r");
  if (!part) ohshite(_("unable to read part file `%.250s'"),partfile);
  if (!read_info(part,partfile,refi)) {
    if (!opt_npquiet)
      printf(_("File `%.250s' is not part of a multipart archive.\n"),partfile);
    m_output(stdout, _("<standard output>"));
    return 1;
  }
  fclose(part);
  scandepot();
  partlist= nfmalloc(sizeof(struct partinfo*)*refi->maxpartn);
  for (i = 0; i < refi->maxpartn; i++)
    partlist[i] = NULL;
  for (pq= queue; pq; pq= pq->nextinqueue) {
    struct partinfo *npi, *pi = &pq->info;

    if (!partmatches(pi,refi)) continue;
    npi= nfmalloc(sizeof(struct partinfo));
    mustgetpartinfo(pi->filename,npi);
    addtopartlist(partlist,npi,refi);
  }
  /* If we already have a copy of this version we ignore it and prefer the
   * new one, but we still want to delete the one in the depot, so we
   * save its partinfo (with the filename) for later. This also prevents
   * us from accidentally deleting the source file. */
  otherthispart= partlist[refi->thispartn-1];
  partlist[refi->thispartn-1]= refi;
  for (j=refi->maxpartn-1; j>=0 && partlist[j]; j--);

  if (j>=0) {
    int fd_src, fd_dst;
    int ap;
    char *p, *q;

    m_asprintf(&p, "%s/t.%lx", opt_depotdir, (long)getpid());
    m_asprintf(&q, "%s/%s.%jx.%x.%x", opt_depotdir, refi->md5sum,
               (intmax_t)refi->maxpartlen, refi->thispartn, refi->maxpartn);

    fd_src = open(partfile, O_RDONLY);
    if (fd_src < 0)
      ohshite(_("unable to reopen part file `%.250s'"), partfile);
    fd_dst = creat(p, 0644);
    if (fd_dst < 0)
      ohshite(_("unable to open new depot file `%.250s'"), p);

    fd_fd_copy(fd_src, fd_dst, refi->filesize, _("extracting split part"));

    if (fsync(fd_dst))
      ohshite(_("unable to sync file '%s'"), p);
    if (close(fd_dst))
      ohshite(_("unable to close file '%s'"), p);
    close(fd_src);

    if (rename(p,q)) ohshite(_("unable to rename new depot file `%.250s' to `%.250s'"),p,q);
    free(q);
    free(p);

    printf(_("Part %d of package %s filed (still want "),refi->thispartn,refi->package);
    /* There are still some parts missing. */
    for (i=0, ap=0; i<refi->maxpartn; i++)
      if (!partlist[i])
        printf("%s%d", !ap++ ? "" : i == (unsigned int)j ? _(" and ") : ", ", i + 1);
    printf(").\n");

    dir_sync_path(opt_depotdir);
  } else {

    /* We have all the parts. */
    reassemble(partlist, opt_outputfile);

    /* OK, delete all the parts (except the new one, which we never copied). */
    partlist[refi->thispartn-1]= otherthispart;
    for (i=0; i<refi->maxpartn; i++)
      if (partlist[i])
        if (unlink(partlist[i]->filename))
          ohshite(_("unable to delete used-up depot file `%.250s'"),partlist[i]->filename);

  }

  m_output(stderr, _("<standard error>"));

  return 0;
}

int
do_queue(const char *const *argv)
{
  struct partqueue *pq;
  const char *head;
  struct stat stab;
  off_t bytes;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);
  scandepot();

  head= N_("Junk files left around in the depot directory:\n");
  for (pq= queue; pq; pq= pq->nextinqueue) {
    if (pq->info.md5sum) continue;
    fputs(gettext(head),stdout); head= "";
    if (lstat(pq->info.filename,&stab))
      ohshit(_("unable to stat `%.250s'"),pq->info.filename);
    if (S_ISREG(stab.st_mode)) {
      bytes= stab.st_size;
      printf(_(" %s (%jd bytes)\n"), pq->info.filename, (intmax_t)bytes);
    } else {
      printf(_(" %s (not a plain file)\n"),pq->info.filename);
    }
  }
  if (!*head) putchar('\n');

  head= N_("Packages not yet reassembled:\n");
  for (pq= queue; pq; pq= pq->nextinqueue) {
    struct partinfo ti;
    unsigned int i;

    if (!pq->info.md5sum) continue;
    mustgetpartinfo(pq->info.filename,&ti);
    fputs(gettext(head),stdout); head= "";
    printf(_(" Package %s: part(s) "), ti.package);
    bytes= 0;
    for (i=0; i<ti.maxpartn; i++) {
      struct partqueue *qq;

      for (qq= pq;
           qq && !(partmatches(&qq->info,&ti) && qq->info.thispartn == i+1);
           qq= qq->nextinqueue);
      if (qq) {
        printf("%d ",i+1);
        if (lstat(qq->info.filename,&stab))
          ohshite(_("unable to stat `%.250s'"),qq->info.filename);
        if (!S_ISREG(stab.st_mode))
          ohshit(_("part file `%.250s' is not a plain file"),qq->info.filename);
        bytes+= stab.st_size;

        /* Don't find this package again. */
        qq->info.md5sum = NULL;
      }
    }
    printf(_("(total %jd bytes)\n"), (intmax_t)bytes);
  }
  m_output(stdout, _("<standard output>"));

  return 0;
}

enum discardwhich { ds_junk, ds_package, ds_all };

static void discardsome(enum discardwhich which, const char *package) {
  struct partqueue *pq;

  for (pq= queue; pq; pq= pq->nextinqueue) {
    switch (which) {
    case ds_junk:
      if (pq->info.md5sum) continue;
      break;
    case ds_package:
      if (!pq->info.md5sum || strcasecmp(pq->info.package,package)) continue;
      break;
    case ds_all:
      break;
    default:
      internerr("unknown discardwhich '%d'", which);
    }
    if (unlink(pq->info.filename))
      ohshite(_("unable to discard `%.250s'"),pq->info.filename);
    printf(_("Deleted %s.\n"),pq->info.filename);
  }
}

int
do_discard(const char *const *argv)
{
  const char *thisarg;
  struct partqueue *pq;

  scandepot();
  if (*argv) {
    for (pq= queue; pq; pq= pq->nextinqueue)
      if (pq->info.md5sum)
        mustgetpartinfo(pq->info.filename,&pq->info);
    discardsome(ds_junk,NULL);
    while ((thisarg= *argv++)) discardsome(ds_package,thisarg);
  } else {
    discardsome(ds_all,NULL);
  }

  return 0;
}
