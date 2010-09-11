/*
 * dpkg-split - splitting and joining of multipart *.deb archives
 * info.c - information about split archives
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
#include <ctype.h>
#include <string.h>
#include <unistd.h>
#include <ar.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/ar.h>
#include <dpkg/myopt.h>

#include "dpkg-split.h"

static unsigned long unsignedlong(const char *value, const char *fn, const char *what) {
  unsigned long r;
  char *endp;

  r= strtoul(value,&endp,10);
  if (value == endp || *endp)
    ohshit(_("file `%.250s' is corrupt - bad digit (code %d) in %s"),fn,*endp,what);
  return r;
}

static unsigned long parseheaderlength(const char *inh, size_t len,
                                       const char *fn, const char *what) {
  char lintbuf[15];

  if (memchr(inh,0,len))
    ohshit(_("file `%.250s' is corrupt - %.250s length contains nulls"),fn,what);
  assert(sizeof(lintbuf) > len);
  memcpy(lintbuf,inh,len);
  lintbuf[len]= ' ';
  *strchr(lintbuf, ' ') = '\0';
  return unsignedlong(lintbuf,fn,what);
}

static char *nextline(char **ripp, const char *fn, const char *what) {
  char *newline, *rip;

  rip= *ripp;
  if (!rip) ohshit(_("file `%.250s' is corrupt - %.250s missing"),fn,what);
  newline= strchr(rip,'\n');
  if (!newline)
    ohshit(_("file `%.250s' is corrupt - missing newline after %.250s"),fn,what);
  *ripp= newline+1;
  while (newline > rip && isspace(newline[-1])) newline--;
  *newline = '\0';
  return rip;
}

struct partinfo *read_info(FILE *partfile, const char *fn, struct partinfo *ir) {
  /* returns info (nfmalloc'd) if was an archive part and we read it, 0 if it wasn't */
  static char *readinfobuf= NULL;
  static size_t readinfobuflen= 0;

  size_t thisilen;
  unsigned int templong;
  char magicbuf[strlen(DPKG_AR_MAGIC)], *rip, *partnums, *slash;
  struct ar_hdr arh;
  int c;
  struct stat stab;
  
  if (fread(magicbuf, 1, sizeof(magicbuf), partfile) != sizeof(magicbuf)) {
    if (ferror(partfile)) rerr(fn); else return NULL;
  }
  if (memcmp(magicbuf, DPKG_AR_MAGIC, sizeof(magicbuf)))
    return NULL;
  
  if (fread(&arh,1,sizeof(arh),partfile) != sizeof(arh)) rerreof(partfile,fn);

  dpkg_ar_normalize_name(&arh);

  if (strncmp(arh.ar_name, PARTMAGIC, sizeof(arh.ar_name)) != 0)
    return NULL;
  if (memcmp(arh.ar_fmag,ARFMAG,sizeof(arh.ar_fmag)))
    ohshit(_("file `%.250s' is corrupt - bad magic at end of first header"),fn);
  thisilen = parseheaderlength(arh.ar_size, sizeof(arh.ar_size), fn,
                               _("archive information member size"));
  if (thisilen >= readinfobuflen) {
    readinfobuflen= thisilen+1;
    readinfobuf= m_realloc(readinfobuf,readinfobuflen);
  }
  if (fread(readinfobuf,1,thisilen,partfile) != thisilen) rerreof(partfile,fn);
  if (thisilen & 1) {
    c= getc(partfile);  if (c==EOF) rerreof(partfile,fn);
    if (c != '\n')
      ohshit(_("file `%.250s' is corrupt - bad padding character (code %d)"),fn,c);
  }
  readinfobuf[thisilen] = '\0';
  if (memchr(readinfobuf,0,thisilen))
    ohshit(_("file `%.250s' is corrupt - nulls in info section"),fn);

  ir->filename= fn;

  rip= readinfobuf;
  ir->fmtversion = nfstrsave(nextline(&rip, fn, _("format version number")));
  if (strcmp(ir->fmtversion,SPLITVERSION))
    ohshit(_("file `%.250s' is format version `%.250s' - you need a newer dpkg-split"),
           fn,ir->fmtversion);

  ir->package = nfstrsave(nextline(&rip, fn, _("package name")));
  ir->version = nfstrsave(nextline(&rip, fn, _("package version number")));
  ir->md5sum = nfstrsave(nextline(&rip, fn, _("package file MD5 checksum")));
  if (strlen(ir->md5sum) != MD5HASHLEN ||
      strspn(ir->md5sum, "0123456789abcdef") != MD5HASHLEN)
    ohshit(_("file `%.250s' is corrupt - bad MD5 checksum `%.250s'"),fn,ir->md5sum);

  ir->orglength = unsignedlong(nextline(&rip, fn, _("archive total size")),
                               fn, _("archive total size"));
  ir->maxpartlen = unsignedlong(nextline(&rip, fn, _("archive part offset")),
                                fn, _("archive part offset"));
  
  partnums = nextline(&rip, fn, _("archive part numbers"));
  slash= strchr(partnums,'/');
  if (!slash)
    ohshit(_("file '%.250s' is corrupt - no slash between archive part numbers"), fn);
  *slash++ = '\0';

  templong = unsignedlong(slash, fn, _("number of archive parts"));
  if (templong <= 0 || templong > INT_MAX)
    ohshit(_("file '%.250s' is corrupt - bad number of archive parts"), fn);
  ir->maxpartn= templong;
  templong = unsignedlong(partnums, fn, _("archive parts number"));
  if (templong <= 0 || templong > ir->maxpartn)
    ohshit(_("file '%.250s' is corrupt - bad archive part number"),fn);
  ir->thispartn= templong;

  if (fread(&arh,1,sizeof(arh),partfile) != sizeof(arh)) rerreof(partfile,fn);

  dpkg_ar_normalize_name(&arh);

  if (memcmp(arh.ar_fmag,ARFMAG,sizeof(arh.ar_fmag)))
    ohshit(_("file `%.250s' is corrupt - bad magic at end of second header"),fn);
  if (strncmp(arh.ar_name,"data",4))
    ohshit(_("file `%.250s' is corrupt - second member is not data member"),fn);

  ir->thispartlen = parseheaderlength(arh.ar_size, sizeof(arh.ar_size), fn,
                                      _("archive data member size"));
  ir->thispartoffset= (ir->thispartn-1)*ir->maxpartlen;

  if (ir->maxpartn != (ir->orglength+ir->maxpartlen-1)/ir->maxpartlen)
    ohshit(_("file `%.250s' is corrupt - wrong number of parts for quoted sizes"),fn);
  if (ir->thispartlen !=
      (ir->thispartn == ir->maxpartn
       ? ir->orglength - ir->thispartoffset : ir->maxpartlen))
    ohshit(_("file `%.250s' is corrupt - size is wrong for quoted part number"),fn);

  ir->filesize = (strlen(DPKG_AR_MAGIC) +
                  sizeof(arh) + thisilen + (thisilen & 1) +
                  sizeof(arh) + ir->thispartlen + (ir->thispartlen & 1));

  if (fstat(fileno(partfile),&stab)) ohshite(_("unable to fstat part file `%.250s'"),fn);
  if (S_ISREG(stab.st_mode)) {
    /* Don't do this check if it's coming from a pipe or something.  It's
     * only an extra sanity check anyway.
     */
    if (stab.st_size < ir->filesize)
      ohshit(_("file `%.250s' is corrupt - too short"),fn);
  }

  ir->headerlen = strlen(DPKG_AR_MAGIC) +
                  sizeof(arh) + thisilen + (thisilen & 1) + sizeof(arh);
    
  return ir;
}  

void mustgetpartinfo(const char *filename, struct partinfo *ri) {
  FILE *part;
  
  part= fopen(filename,"r");
  if (!part) ohshite(_("cannot open archive part file `%.250s'"),filename);
  if (!read_info(part,filename,ri))
    ohshite(_("file `%.250s' is not an archive part"),filename);
  fclose(part);
}

void print_info(const struct partinfo *pi) {
  printf(_("%s:\n"
         "    Part format version:            %s\n"
         "    Part of package:                %s\n"
         "        ... version:                %s\n"
         "        ... MD5 checksum:           %s\n"
         "        ... length:                 %lu bytes\n"
         "        ... split every:            %lu bytes\n"
         "    Part number:                    %d/%d\n"
         "    Part length:                    %zi bytes\n"
         "    Part offset:                    %lu bytes\n"
         "    Part file size (used portion):  %lu bytes\n\n"),
         pi->filename,
         pi->fmtversion,
         pi->package,
         pi->version,
         pi->md5sum,
         pi->orglength,
         pi->maxpartlen,
         pi->thispartn,
         pi->maxpartn,
         pi->thispartlen,
         pi->thispartoffset,
         (unsigned long)pi->filesize);
}

void do_info(const char *const *argv) {
  const char *thisarg;
  struct partinfo *pi, ps;
  FILE *part;

  if (!*argv)
    badusage(_("--%s requires one or more part file arguments"),
             cipaction->olong);
  
  while ((thisarg= *argv++)) {
    part= fopen(thisarg,"r");
    if (!part) ohshite(_("cannot open archive part file `%.250s'"),thisarg);
    pi= read_info(part,thisarg,&ps);
    fclose(part);
    if (pi) {
      print_info(pi);
    } else {
      printf(_("file `%s' is not an archive part\n"),thisarg);
    }
    m_output(stdout, _("<standard output>"));
  }
}
