/*
 * libdpkg - Debian packaging suite library routines
 * dpkg-db.h - Low level package database routines (hash tables, etc.)
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <ctype.h>
#include <string.h>

#include <config.h>
#include <dpkg.h>
#include <dpkg-db.h>

#define BINS (1 << 7)
 /* This must always be a power of two.  If you change it
  * consider changing the per-character hashing factor (currently 5) too.
  */

static struct pkginfo *bins[BINS];
static int npackages;

static int hash(const char *name) {
  int v= 0;
  while (*name) { v *= 5; v += tolower(*name); name++; }
  return v;
/* These results were achieved with 128 bins, and the list of packages
 * shown at the bottom of this file.
 */
/*  while (*name) { v *= 17; v += tolower(*name); name++; }
 *  size       5 occurs     1 times
 *  size       4 occurs     0 times
 *  size       3 occurs     7 times
 *  size       2 occurs    32 times
 *  size       1 occurs    51 times
 *  size       0 occurs    37 times
 */
/*  while (*name) { v *= 5; v += tolower(*name); name++; }
 *  size       4 occurs     1 times
 *  size       3 occurs    14 times
 *  size       2 occurs    20 times
 *  size       1 occurs    55 times
 *  size       0 occurs    38 times
 */
/*  while (*name) { v *= 11; v += tolower(*name); name++; }
 *  size       5 occurs     1 times
 *  size       4 occurs     4 times
 *  size       3 occurs     9 times
 *  size       2 occurs    25 times
 *  size       1 occurs    43 times
 *  size       0 occurs    46 times
 */
/*  while (*name) { v *= 31; v += tolower(*name); name++; }
 *  size       6 occurs     1 times
 *  size       5 occurs     0 times
 *  size       4 occurs     1 times
 *  size       3 occurs    11 times
 *  size       2 occurs    27 times
 *  size       1 occurs    44 times
 *  size       0 occurs    44 times
 */
/*  while (*name) { v *= 111; v += tolower(*name); name++; }
 *  size       5 occurs     1 times
 *  size       4 occurs     1 times
 *  size       3 occurs    14 times
 *  size       2 occurs    23 times
 *  size       1 occurs    44 times
 *  size       0 occurs    45 times
 */
/*  while (*name) { v += (v<<3); v += tolower(*name); name++; }
 *  size       4 occurs     5 times
 *  size       3 occurs    12 times
 *  size       2 occurs    22 times
 *  size       1 occurs    41 times
 *  size       0 occurs    48 times
 */
/*  while (*name) { v *= 29; v += tolower(*name); name++; }
 *  size       5 occurs     1 times
 *  size       4 occurs     2 times
 *  size       3 occurs    10 times
 *  size       2 occurs    26 times
 *  size       1 occurs    46 times
 *  size       0 occurs    43 times
 */
/*  while (*name) { v *= 13; v += tolower(*name); name++; }
 *  size       5 occurs     1 times
 *  size       4 occurs     2 times
 *  size       3 occurs     5 times
 *  size       2 occurs    30 times
 *  size       1 occurs    53 times
 *  size       0 occurs    37 times
 */
}

void blankversion(struct versionrevision *version) {
  version->epoch= 0;
  version->version= version->revision= NULL;
}

void blankpackage(struct pkginfo *pigp) {
  pigp->name= NULL;
  pigp->status= stat_notinstalled;
  pigp->eflag= eflagv_ok;
  pigp->want= want_unknown;
  pigp->priority= pri_unknown;
  pigp->otherpriority = NULL;
  pigp->section= NULL;
  blankversion(&pigp->configversion);
  pigp->files= NULL;
  pigp->installed.valid= 0;
  pigp->available.valid= 0;
  pigp->clientdata= NULL;
  blankpackageperfile(&pigp->installed);
  blankpackageperfile(&pigp->available);
}

void blankpackageperfile(struct pkginfoperfile *pifp) {
  pifp->essential= 0;
  pifp->depends= NULL;
  pifp->depended= NULL;
  pifp->description= pifp->maintainer= pifp->source= pifp->installedsize= pifp->bugs= pifp->origin= NULL;
  pifp->architecture= NULL;
  blankversion(&pifp->version);
  pifp->conffiles= NULL;
  pifp->arbs= NULL;
  pifp->valid= 1;
}

static int nes(const char *s) { return s && *s; }

int informative(struct pkginfo *pkg, struct pkginfoperfile *info) {
  /* Used by dselect and dpkg query options as an aid to decide
   * whether to display things, and by dump to decide whether to write them
   * out.
   */
  if (info == &pkg->installed &&
      (pkg->want != want_unknown ||
       pkg->eflag != eflagv_ok ||
       pkg->status != stat_notinstalled ||
       informativeversion(&pkg->configversion)))
    /* We ignore Section and Priority, as these tend to hang around. */
    return 1;
  if (!info->valid) return 0;
  if (info->depends ||
      nes(info->description) ||
      nes(info->maintainer) ||
      nes(info->origin) ||
      nes(info->bugs) ||
      nes(info->installedsize) ||
      nes(info->source) ||
      nes(info->architecture) ||
      informativeversion(&info->version) ||
      info->conffiles ||
      info->arbs) return 1;
  return 0;
}

struct pkginfo *findpackage(const char *inname) {
  struct pkginfo **pointerp, *newpkg;
  char *name = strdup(inname), *p;

  if (name == NULL)
    ohshite(_("couldn't allocate memory for strdup in findpackage(%s)"),inname);
  p= name;
  while(*p) { *p= tolower(*p); p++; }
  
  pointerp= bins + (hash(name) & (BINS-1));
  while (*pointerp && strcasecmp((*pointerp)->name,name))
    pointerp= &(*pointerp)->next;
  if (*pointerp) return *pointerp;

  newpkg= nfmalloc(sizeof(struct pkginfo));
  blankpackage(newpkg);
  newpkg->name= nfstrsave(name);
  newpkg->next= NULL;
  *pointerp= newpkg;
  npackages++;

  free(name);
  return newpkg;
}

int countpackages(void) {
  return npackages;
}

struct pkgiterator {
  struct pkginfo *pigp;
  int nbinn;
};

struct pkgiterator *iterpkgstart(void) {
  struct pkgiterator *i;
  i= m_malloc(sizeof(struct pkgiterator));
  i->pigp= NULL;
  i->nbinn= 0;
  return i;
}

struct pkginfo *iterpkgnext(struct pkgiterator *i) {
  struct pkginfo *r;
  while (!i->pigp) {
    if (i->nbinn >= BINS) return NULL;
    i->pigp= bins[i->nbinn++];
  }
  r= i->pigp; i->pigp= r->next; return r;
}

void iterpkgend(struct pkgiterator *i) {
  free(i);
}

void resetpackages(void) {
  int i;
  nffreeall();
  npackages= 0;
  for (i=0; i<BINS; i++) bins[i]= NULL;
}

void hashreport(FILE *file) {
  int i, c;
  struct pkginfo *pkg;
  int *freq;

  freq= m_malloc(sizeof(int)*npackages+1);
  for (i=0; i<=npackages; i++) freq[i]= 0;
  for (i=0; i<BINS; i++) {
    for (c=0, pkg= bins[i]; pkg; c++, pkg= pkg->next);
    fprintf(file,"bin %5d has %7d\n",i,c);
    freq[c]++;
  }
  for (i=npackages; i>0 && freq[i]==0; i--);
  while (i>=0) { fprintf(file,_("size %7d occurs %5d times\n"),i,freq[i]); i--; }
  if (ferror(file)) ohshite(_("failed write during hashreport"));
  free(freq);
}

/*
 * Test dataset package names were:
 *
 * agetty bash bc bdflush biff bin86 binutil binutils bison bsdutils
 * byacc chfn cron dc dictionaries diff dlltools dpkg e2fsprogs ed
 * elisp19 elm emacs emacs-nox emacs-x emacs19 file fileutils find
 * flex fsprogs gas gawk gcc gcc1 gcc2 gdb ghostview ghstview glibcdoc
 * gnuplot grep groff gs gs_both gs_svga gs_x gsfonts gxditviw gzip
 * hello hostname idanish ifrench igerman indent inewsinn info inn
 * ispell kbd kern1148 language ldso less libc libgr libgrdev librl
 * lilo linuxsrc login lout lpr m4 mailx make man manpages more mount
 * mtools ncurses netbase netpbm netstd patch perl4 perl5 procps
 * psutils rcs rdev sed sendmail seyon shar shellutils smail svgalib
 * syslogd sysvinit tar tcpdump tcsh tex texidoc texinfo textutils
 * time timezone trn unzip uuencode wenglish wu-ftpd x8514 xaxe xbase
 * xbdm2 xcomp xcoral xdevel xfig xfnt100 xfnt75 xfntbig xfntscl
 * xgames xherc xmach32 xmach8 xmono xnet xs3 xsvga xtexstuff xv
 * xvga16 xxgdb zip
 */
