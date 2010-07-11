/*
 * dpkg-split - splitting and joining of multipart *.deb archives
 * dpkg-split.h - external definitions for this program
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

#ifndef DPKG_SPLIT_H
#define DPKG_SPLIT_H

typedef void dofunction(const char *const *argv);
dofunction do_split DPKG_ATTR_NORET;
dofunction do_join, do_info, do_auto, do_queue, do_discard;

struct partinfo {
  const char *filename;
  const char *fmtversion;
  const char *package;
  const char *version;
  const char *md5sum;
  unsigned long orglength;
  unsigned int thispartn, maxpartn;
  unsigned long maxpartlen;
  unsigned long thispartoffset;
  size_t thispartlen;
  size_t headerlen; /* size of header in part file */
  off_t filesize;
};

struct partqueue {
  struct partqueue *nextinqueue;
  struct partinfo info;
  /* only fields filename, md5sum, maxpartlen, thispartn, maxpartn
   * are valid; the rest are null.  If the file is not named correctly
   * to be a part file md5sum is null too and the numbers are zero.
   */
};

extern dofunction *action;
extern const struct cmdinfo *cipaction;
extern struct partqueue *queue;

extern long opt_maxpartsize;
extern const char *opt_depotdir;
extern const char *opt_outputfile;
extern int opt_npquiet;
extern int opt_msdos;

void rerr(const char *fn) DPKG_ATTR_NORET;
void rerreof(FILE *f, const char *fn) DPKG_ATTR_NORET;
void print_info(const struct partinfo *pi);
struct partinfo *read_info(FILE *partfile, const char *fn, struct partinfo *ir);

void scandepot(void);
void reassemble(struct partinfo **partlist, const char *outputfile);
void mustgetpartinfo(const char *filename, struct partinfo *ri);
void addtopartlist(struct partinfo**, struct partinfo*, struct partinfo *refi);

#define SPLITVERSION       "2.1"

#define PARTSDIR          "parts/"

#define PARTMAGIC         "debian-split"
#define HEADERALLOWANCE    1024

#define SPLITPARTDEFMAX    (450 * 1024)

#endif /* DPKG_SPLIT_H */
