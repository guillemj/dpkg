/*
 * libdpkg - Debian packaging suite library routines
 * fields.c - parsing of all the different fields, when reading in
 *
 * Copyright (C) 1995 Ian Jackson <iwj10@cus.cam.ac.uk>
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

#include <stdio.h>
#include <ctype.h>
#include <string.h>

#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
#include "parsedump.h"

static int convert_string(const char *filename, int lno, const char *what, int otherwise,
                          FILE *warnto, int *warncount, const struct pkginfo *pigp,
                          const char *startp, const struct namevalue *nvip,
                          const char **endpp) {
  const char *ep;
  int c, l;

  ep= startp;
  if (!*ep) parseerr(0,filename,lno, warnto,warncount,pigp,0, "%s is missing",what);
  while ((c= *ep) && !isspace(c)) ep++;
  l= (int)(ep-startp);
  while (nvip->name && (strncasecmp(nvip->name,startp,l) || nvip->name[l])) nvip++;
  if (!nvip->name) {
    if (otherwise != -1) return otherwise;
    parseerr(0,filename,lno, warnto,warncount,pigp,0, "`%.*s' is not allowed for %s",
             l > 50 ? 50 : l, startp, what);
  }
  while (isspace(c)) c= *++ep;
  if (c && !endpp)
    parseerr(0,filename,lno, warnto,warncount,pigp,0, "junk after %s",what);
  if (endpp) *endpp= ep;
  return nvip->value;
}

void f_name(struct pkginfo *pigp, struct pkginfoperfile *pifp, enum parsedbflags flags,
            const char *filename, int lno, FILE *warnto, int *warncount,
            const char *value, const struct fieldinfo *fip) {
  const char *e;
  if ((e= illegal_packagename(value,0)) != 0)
    parseerr(0,filename,lno, warnto,warncount,pigp,0, "invalid package name (%.250s)",e);
  pigp->name= nfstrsave(value);
  findpackage(value); /* We discard the value from findpackage, but calling it
                       * forces an entry in the hash table to be made if it isn't
                       * already.  This is so that we don't reorder the file
                       * unnecessarily (doing so is bad for debugging).
                       */
}

void f_filecharf(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                 enum parsedbflags flags,
                 const char *filename, int lno, FILE *warnto, int *warncount,
                 const char *value, const struct fieldinfo *fip) {
  struct filedetails *fdp, **fdpp;
  char *cpos, *space;
  int allowextend;

  if (!*value)
    parseerr(0,filename,lno, warnto,warncount,pigp,0,
             "empty file details field `%s'",fip->name);
  if (!(flags & pdb_recordavailable))
    parseerr(0,filename,lno, warnto,warncount,pigp,0,
             "file details field `%s' not allowed in status file",fip->name);
  allowextend= !pigp->files;
  fdpp= &pigp->files;
  cpos= nfstrsave(value);
  while (*cpos) {
    space= cpos; while (*space && !isspace(*space)) space++;
    if (*space) *space++= 0;
    fdp= *fdpp;
    if (!fdp) {
      if (!allowextend)
        parseerr(0,filename,lno, warnto,warncount,pigp,0, "too many values "
                 "in file details field `%s' (compared to others)",fip->name);
      fdp= nfmalloc(sizeof(struct filedetails));
      fdp->next= 0;
      fdp->name= fdp->msdosname= fdp->size= fdp->md5sum= 0;
      *fdpp= fdp;
    }
    FILEFFIELD(fdp,fip->integer,char*)= cpos;
    fdpp= &fdp->next;
    while (*space && isspace(*space)) space++;
    cpos= space;
  }
  if (*fdpp)
    parseerr(0,filename,lno, warnto,warncount,pigp,0, "too few values "
             "in file details field `%s' (compared to others)",fip->name);
}

void f_charfield(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                 enum parsedbflags flags,
                 const char *filename, int lno, FILE *warnto, int *warncount,
                 const char *value, const struct fieldinfo *fip) {
  if (*value) PKGPFIELD(pifp,fip->integer,char*)= nfstrsave(value);
}

void f_boolean(struct pkginfo *pigp, struct pkginfoperfile *pifp,
               enum parsedbflags flags,
               const char *filename, int lno, FILE *warnto, int *warncount,
               const char *value, const struct fieldinfo *fip) {
  pifp->essential=
    *value ? convert_string(filename,lno,"yes/no in `essential' field", -1,
                            warnto,warncount,pigp,
                            value,booleaninfos,0)
           : 0;
}

void f_section(struct pkginfo *pigp, struct pkginfoperfile *pifp,
               enum parsedbflags flags,
               const char *filename, int lno, FILE *warnto, int *warncount,
               const char *value, const struct fieldinfo *fip) {
  if (!*value) return;
  pigp->section= nfstrsave(value);
}

void f_priority(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                enum parsedbflags flags,
                const char *filename, int lno, FILE *warnto, int *warncount,
                const char *value, const struct fieldinfo *fip) {
  if (!*value) return;
  pigp->priority= convert_string(filename,lno,"word in `priority' field", pri_other,
                             warnto,warncount,pigp,
                             value,priorityinfos,0);
  if (pigp->priority == pri_other) pigp->otherpriority= nfstrsave(value);
}

void f_status(struct pkginfo *pigp, struct pkginfoperfile *pifp,
              enum parsedbflags flags,
              const char *filename, int lno, FILE *warnto, int *warncount,
              const char *value, const struct fieldinfo *fip) {
  const char *ep;

  if (flags & pdb_rejectstatus)
    parseerr(0,filename,lno, warnto,warncount,pigp,0,
             "value for `status' field not allowed in this context");
  if (flags & pdb_recordavailable) return;
  
  pigp->want= convert_string(filename,lno,"first (want) word in `status' field", -1,
                             warnto,warncount,pigp, value,wantinfos,&ep);
  pigp->eflag= convert_string(filename,lno,"second (error) word in `status' field", -1,
                              warnto,warncount,pigp, ep,eflaginfos,&ep);
  if (pigp->eflag & eflagf_obsoletehold) {
    pigp->want= want_hold;
    pigp->eflag &= ~eflagf_obsoletehold;
  }
  pigp->status= convert_string(filename,lno,"third (status) word in `status' field", -1,
                               warnto,warncount,pigp, ep,statusinfos,0);
}

void f_version(struct pkginfo *pigp, struct pkginfoperfile *pifp,
               enum parsedbflags flags,
               const char *filename, int lno, FILE *warnto, int *warncount,
               const char *value, const struct fieldinfo *fip) {
  const char *emsg;
  
  emsg= parseversion(&pifp->version,value);
  if (emsg) parseerr(0,filename,lno, warnto,warncount,pigp,0, "error "
                     "in Version string `%.250s': %.250s",value,emsg);
}  

void f_revision(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                enum parsedbflags flags,
                const char *filename, int lno, FILE *warnto, int *warncount,
                const char *value, const struct fieldinfo *fip) {
  char *newversion;

  parseerr(0,filename,lno, warnto,warncount,pigp,1,
           "obsolete `Revision' or `Package-Revision' field used");
  if (!*value) return;
  if (pifp->version.revision && *pifp->version.revision) {
    newversion= nfmalloc(strlen(pifp->version.version)+strlen(pifp->version.revision)+2);
    sprintf(newversion,"%s-%s",pifp->version.version,pifp->version.revision);
  }
  pifp->version.revision= nfstrsave(value);
}  

void f_configversion(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                     enum parsedbflags flags,
                     const char *filename, int lno, FILE *warnto, int *warncount,
                     const char *value, const struct fieldinfo *fip) {
  const char *emsg;
  
  if (flags & pdb_rejectstatus)
    parseerr(0,filename,lno, warnto,warncount,pigp,0,
             "value for `config-version' field not allowed in this context");
  if (flags & pdb_recordavailable) return;

  emsg= parseversion(&pigp->configversion,value);
  if (emsg) parseerr(0,filename,lno, warnto,warncount,pigp,0, "error "
                     "in Config-Version string `%.250s': %.250s",value,emsg);
}

void f_conffiles(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                 enum parsedbflags flags,
                 const char *filename, int lno, FILE *warnto, int *warncount,
                 const char *value, const struct fieldinfo *fip) {
  struct conffile **lastp, *newlink;
  const char *endent, *endfn;
  int c, namelen, hashlen;
  
  lastp= &pifp->conffiles;
  while (*value) {
    c= *value++;
    if (c == '\n') continue;
    if (c != ' ') parseerr(0,filename,lno, warnto,warncount,pigp,0, "value for"
                           " `conffiles' has line starting with non-space `%c'", c);
    for (endent= value; (c= *endent)!=0 && c != '\n'; endent++);
    for (endfn= endent; *endfn != ' '; endfn--);
    if (endfn <= value+1 || endfn >= endent-1)
      parseerr(0,filename,lno, warnto,warncount,pigp,0,
               "value for `conffiles' has malformatted line `%.*s'",
               (int)(endent-value > 250 ? 250 : endent-value), value);
    newlink= nfmalloc(sizeof(struct conffile));
    value= skip_slash_dotslash(value);
    namelen= (int)(endfn-value);
    if (namelen <= 0) parseerr(0,filename,lno, warnto,warncount,pigp,0,
                               "root or null directory is listed as a conffile");
    newlink->name= nfmalloc(namelen+2);
    newlink->name[0]= '/';
    memcpy(newlink->name+1,value,namelen);
    newlink->name[namelen+1]= 0;
    hashlen= (int)(endent-endfn)-1; newlink->hash= nfmalloc(hashlen+1);
    memcpy(newlink->hash,endfn+1,hashlen); newlink->hash[hashlen]= 0;
    newlink->next =0;
    *lastp= newlink;
    lastp= &newlink->next;
    value= endent;
  }
}

void f_dependency(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                  enum parsedbflags flags,
                  const char *filename, int lno, FILE *warnto, int *warncount,
                  const char *value, const struct fieldinfo *fip) {
  char c1, c2;
  const char *p, *emsg;
  struct varbuf depname, version;
  struct dependency *dyp, **ldypp;
  struct deppossi *dop, **ldopp;

  if (!*value) return; /* empty fields are ignored */
  varbufinit(&depname); varbufinit(&version);
  p= value;
  ldypp= &pifp->depends; while (*ldypp) ldypp= &(*ldypp)->next;
  for (;;) { /* loop creating new struct dependency's */
    dyp= nfmalloc(sizeof(struct dependency));
    dyp->up= 0; /* Set this to zero for now, as we don't know what our real
                 * struct pkginfo address (in the database) is going to be yet.
                 */
    dyp->next= 0; *ldypp= dyp; ldypp= &dyp->next;
    dyp->list= 0; ldopp= &dyp->list;
    dyp->type= fip->integer;
    for (;;) { /* loop creating new struct deppossi's */
      varbufreset(&depname);
      while (*p && !isspace(*p) && *p != '(' && *p != ',' && *p != '|') {
        varbufaddc(&depname,*p); p++;
      }
      varbufaddc(&depname,0);
      if (!*depname.buf)
        parseerr(0,filename,lno, warnto,warncount,pigp,0, "`%s' field, missing"
                 " package name, or garbage where package name expected", fip->name);
      emsg= illegal_packagename(depname.buf,0);
      if (emsg) parseerr(0,filename,lno, warnto,warncount,pigp,0, "`%s' field,"
                         " invalid package name `%.255s': %s",
                         fip->name,depname.buf,emsg);
      dop= nfmalloc(sizeof(struct deppossi));
      dop->up= dyp;
      dop->ed= findpackage(depname.buf);
      dop->next= 0; *ldopp= dop; ldopp= &dop->next;
      dop->nextrev= 0; /* Don't link this (which is after all only `newpig' from
      dop->backrev= 0;  * the main parsing loop in parsedb) into the depended on
                        * packages' lists yet.  This will be done later when we
                        * install this (in parse.c).  For the moment we do the
                        * `forward' links in deppossi (`ed') only, and the backward
                        * links from the depended on packages to dop are left undone.
                        */
      dop->cyclebreak= 0;
      while (isspace(*p)) p++;
      if (*p == '(') {
        varbufreset(&version);
        p++; while (isspace(*p)) p++;
        c1= *p;
        if (c1 == '<' || c1 == '>') {
          c2= *++p;
          dop->verrel= (c1 == '<') ? dvrf_earlier : dvrf_later;
          if (c2 == '=') {
            dop->verrel |= (dvrf_orequal | dvrf_builtup);
            p++;
          } else if (c2 == c1) {
            dop->verrel |= (dvrf_strict | dvrf_builtup);
            p++;
          } else if (c2 == '<' || c2 == '>') {
            parseerr(0,filename,lno, warnto,warncount,pigp,0,
                    "`%s' field, reference to `%.255s':\n"
                    " bad version relationship %c%c",
                    fip->name,depname.buf,c1,c2);
            dop->verrel= dvr_none;
          } else {
            parseerr(0,filename,lno, warnto,warncount,pigp,1,
                     "`%s' field, reference to `%.255s':\n"
                     " `%c' is obsolete, use `%c=' or `%c%c' instead",
                     fip->name,depname.buf,c1,c1,c1,c1);
            dop->verrel |= (dvrf_orequal | dvrf_builtup);
          }
        } else if (c1 == '=') {
          dop->verrel= dvr_exact;
          p++;
        } else {
          parseerr(0,filename,lno, warnto,warncount,pigp,1,
                   "`%s' field, reference to `%.255s':\n"
                   " implicit exact match on version number, suggest using `=' instead",
                   fip->name,depname.buf);
          dop->verrel= dvr_exact;
        }
        if (!isspace(*p) && !isalnum(*p)) {
          parseerr(0,filename,lno, warnto,warncount,pigp,1,
                   "`%s' field, reference to `%.255s':\n"
                   " version value starts with non-alphanumeric, suggest adding a space",
                   fip->name,depname.buf);
        }
        while (isspace(*p)) p++;
        while (*p && *p != ')' && *p != '(') {
          if (!isspace(*p)) varbufaddc(&version,*p);
          p++;
        }
        if (*p == '(') parseerr(0,filename,lno, warnto,warncount,pigp,0,
                                "`%s' field, reference to `%.255s': "
                                "version contains `('",fip->name,depname.buf);
        else if (*p == 0) parseerr(0,filename,lno, warnto,warncount,pigp,0,
                                   "`%s' field, reference to `%.255s': "
                                   "version unterminated",fip->name,depname.buf);
        varbufaddc(&version,0);
        emsg= parseversion(&dop->version,version.buf);
        if (emsg) parseerr(0,filename,lno, warnto,warncount,pigp,0,
                           "`%s' field, reference to `%.255s': "
                           "error in version: %.255s",fip->name,depname.buf,emsg);
        p++; while (isspace(*p)) p++;
      } else {
        dop->verrel= dvr_none;
        blankversion(&dop->version);
      }
      if (!*p || *p == ',') break;
      if (*p != '|')
        parseerr(0,filename,lno, warnto,warncount,pigp,0, "`%s' field, syntax"
                 " error after reference to package `%.255s'",
                 fip->name, dop->ed->name);
      if (fip->integer == dep_conflicts ||
          fip->integer == dep_provides ||
          fip->integer == dep_replaces)
        parseerr(0,filename,lno, warnto,warncount,pigp,0,
                 "alternatives (`|') not allowed in %s field",
                 fip->name);
      p++; while (isspace(*p)) p++;
    }
    if (!*p) break;
    p++; while (isspace(*p)) p++;
  }
}

