/*
 * libdpkg - Debian packaging suite library routines
 * fields.c - parsing of all the different fields, when reading in
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright 2001 Wichert Akkerman
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
#include <config.h>

#include <stdio.h>
#include <ctype.h>
#include <string.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include "parsedump.h"

static int convert_string
(const char *filename, int lno, const char *what, int otherwise,
 FILE *warnto, int *warncount, const struct pkginfo *pigp,
 const char *startp, const struct namevalue *ivip,
 const char **endpp) 
{
  const char *ep;
  int c, l = 0;
  struct namevalue *nvip= NULL;
  memcpy(&nvip,&ivip,sizeof(struct namevalue *));

  ep= startp;
  if (!*ep) parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("%s is missing"),what);
  while (nvip->name) {
    if ((l= nvip->length) == 0) {
      l= strlen(nvip->name);
      nvip->length= (const int)l;
    }
    if (strncasecmp(nvip->name,startp,l) || nvip->name[l])
      nvip++;
    else
      break;
  }
  if (!nvip->name) {
    if (otherwise != -1) return otherwise;
    parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("`%.*s' is not allowed for %s"),
             l > 50 ? 50 : l, startp, what);
  }
  ep = startp + l;
  c = *ep;
  while (isspace(c)) c= *++ep;
  if (c && !endpp)
    parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("junk after %s"),what);
  if (endpp) *endpp= ep;
  return nvip->value;
}

void f_name(struct pkginfo *pigp, struct pkginfoperfile *pifp, enum parsedbflags flags,
            const char *filename, int lno, FILE *warnto, int *warncount,
            const char *value, const struct fieldinfo *fip) {
  const char *e;
  if ((e= illegal_packagename(value,NULL)) != NULL)
    parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("invalid package name (%.250s)"),e);
  pigp->name= findpackage(value)->name;
  /* We use the new name, as findpackage() may have
     done a tolower for us.
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
    parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
             _("empty file details field `%s'"),fip->name);
  if (!(flags & pdb_recordavailable))
    parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
             _("file details field `%s' not allowed in status file"),fip->name);
  allowextend= !pigp->files;
  fdpp= &pigp->files;
  cpos= nfstrsave(value);
  while (*cpos) {
    space= cpos; while (*space && !isspace(*space)) space++;
    if (*space) *space++= 0;
    fdp= *fdpp;
    if (!fdp) {
      if (!allowextend)
        parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("too many values "
                 "in file details field `%s' (compared to others)"),fip->name);
      fdp= nfmalloc(sizeof(struct filedetails));
      fdp->next= NULL;
      fdp->name= fdp->msdosname= fdp->size= fdp->md5sum= NULL;
      *fdpp= fdp;
    }
    FILEFFIELD(fdp,fip->integer,const char*)= cpos;
    fdpp= &fdp->next;
    while (*space && isspace(*space)) space++;
    cpos= space;
  }
  if (*fdpp)
    parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("too few values "
             "in file details field `%s' (compared to others)"),fip->name);
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
    *value ? convert_string(filename,lno,_("yes/no in boolean field"), -1,
                            warnto,warncount,pigp,
                            value,booleaninfos,NULL)
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
                             value,priorityinfos,NULL);
  if (pigp->priority == pri_other) pigp->otherpriority= nfstrsave(value);
}

void f_status(struct pkginfo *pigp, struct pkginfoperfile *pifp,
              enum parsedbflags flags,
              const char *filename, int lno, FILE *warnto, int *warncount,
              const char *value, const struct fieldinfo *fip) {
  const char *ep;

  if (flags & pdb_rejectstatus)
    parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
             _("value for `status' field not allowed in this context"));
  if (flags & pdb_recordavailable) return;
  
  pigp->want= convert_string(filename,lno,"first (want) word in `status' field", -1,
                             warnto,warncount,pigp, value,wantinfos,&ep);
  pigp->eflag= convert_string(filename,lno,"second (error) word in `status' field", -1,
                              warnto,warncount,pigp, ep,eflaginfos,&ep);
  if (pigp->eflag & eflagf_obsoletehold) {
    pigp->want= want_hold;
    pigp->eflag &= ~eflagf_obsoletehold;
  }
  pigp->status= convert_string(filename,lno,_("third (status) word in `status' field"), -1,
                               warnto,warncount,pigp, ep,statusinfos,NULL);
}

void f_version(struct pkginfo *pigp, struct pkginfoperfile *pifp,
               enum parsedbflags flags,
               const char *filename, int lno, FILE *warnto, int *warncount,
               const char *value, const struct fieldinfo *fip) {
  const char *emsg;
  
  emsg= parseversion(&pifp->version,value);
  if (emsg) parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("error "
                     "in Version string `%.250s': %.250s"),value,emsg);
}  

void f_revision(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                enum parsedbflags flags,
                const char *filename, int lno, FILE *warnto, int *warncount,
                const char *value, const struct fieldinfo *fip) {
  char *newversion;

  parseerr(NULL,filename,lno, warnto,warncount,pigp,1,
           _("obsolete `Revision' or `Package-Revision' field used"));
  if (!*value) return;
  if (pifp->version.revision && *pifp->version.revision) {
    newversion= nfmalloc(strlen(pifp->version.version)+strlen(pifp->version.revision)+2);
    sprintf(newversion,"%s-%s",pifp->version.version,pifp->version.revision);
    pifp->version.version= newversion;
  }
  pifp->version.revision= nfstrsave(value);
}  

void f_configversion(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                     enum parsedbflags flags,
                     const char *filename, int lno, FILE *warnto, int *warncount,
                     const char *value, const struct fieldinfo *fip) {
  const char *emsg;
  
  if (flags & pdb_rejectstatus)
    parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
             _("value for `config-version' field not allowed in this context"));
  if (flags & pdb_recordavailable) return;

  emsg= parseversion(&pigp->configversion,value);
  if (emsg) parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("error "
                     "in Config-Version string `%.250s': %.250s"),value,emsg);
}

void f_conffiles(struct pkginfo *pigp, struct pkginfoperfile *pifp,
                 enum parsedbflags flags,
                 const char *filename, int lno, FILE *warnto, int *warncount,
                 const char *value, const struct fieldinfo *fip) {
  struct conffile **lastp, *newlink;
  const char *endent, *endfn;
  int c, namelen, hashlen;
  char *newptr;
  
  lastp= &pifp->conffiles;
  while (*value) {
    c= *value++;
    if (c == '\n') continue;
    if (c != ' ') parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("value for"
                           " `conffiles' has line starting with non-space `%c'"), c);
    for (endent= value; (c= *endent)!=0 && c != '\n'; endent++);
    for (endfn= endent; *endfn != ' '; endfn--);
    if (endfn <= value+1 || endfn >= endent-1)
      parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
               _("value for `conffiles' has malformatted line `%.*s'"),
               (int)(endent-value > 250 ? 250 : endent-value), value);
    newlink= nfmalloc(sizeof(struct conffile));
    value= skip_slash_dotslash(value);
    namelen= (int)(endfn-value);
    if (namelen <= 0) parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
                               _("root or null directory is listed as a conffile"));
    newptr = nfmalloc(namelen+2);
    newptr[0]= '/';
    memcpy(newptr+1,value,namelen);
    newptr[namelen+1]= 0;
    newlink->name= newptr;
    hashlen= (int)(endent-endfn)-1; newptr= nfmalloc(hashlen+1);
    memcpy(newptr,endfn+1,hashlen); newptr[hashlen]= 0;
    newlink->hash= newptr;
    newlink->next =NULL;
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
  const char *depnamestart, *versionstart;
  int depnamelength, versionlength;
  static int depnameused= 0, versionused= 0;
  static char *depname= NULL, *version= NULL;

  struct dependency *dyp, **ldypp;
  struct deppossi *dop, **ldopp;

  if (!*value) return; /* empty fields are ignored */
  p= value;
  ldypp= &pifp->depends; while (*ldypp) ldypp= &(*ldypp)->next;
  for (;;) { /* loop creating new struct dependency's */
    dyp= nfmalloc(sizeof(struct dependency));
    dyp->up= NULL; /* Set this to zero for now, as we don't know what our real
                 * struct pkginfo address (in the database) is going to be yet.
                 */
    dyp->next= NULL; *ldypp= dyp; ldypp= &dyp->next;
    dyp->list= NULL; ldopp= &dyp->list;
    dyp->type= fip->integer;
    for (;;) { /* loop creating new struct deppossi's */
      depnamestart= p;
/* skip over package name characters */
      while (*p && !isspace(*p) && *p != '(' && *p != ',' && *p != '|') {
	p++;
      }
      depnamelength= p - depnamestart ;
      if (depnamelength >= depnameused) {
	depnameused= depnamelength;
	depname= realloc(depname,depnamelength+1);
      }
      strncpy(depname, depnamestart, depnamelength);
      *(depname + depnamelength)= 0;
      if (!*depname)
        parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("`%s' field, missing"
                 " package name, or garbage where package name expected"), fip->name);
      emsg= illegal_packagename(depname,NULL);
      if (emsg) parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("`%s' field,"
                         " invalid package name `%.255s': %s"),
                         fip->name,depname,emsg);
      dop= nfmalloc(sizeof(struct deppossi));
      dop->up= dyp;
      dop->ed= findpackage(depname);
      dop->next= NULL; *ldopp= dop; ldopp= &dop->next;
      dop->nextrev= NULL; /* Don't link this (which is after all only `newpig' from */
      dop->backrev= NULL; /* the main parsing loop in parsedb) into the depended on
                        * packages' lists yet.  This will be done later when we
                        * install this (in parse.c).  For the moment we do the
                        * `forward' links in deppossi (`ed') only, and the backward
                        * links from the depended on packages to dop are left undone.
                        */
      dop->cyclebreak= 0;
/* skip whitespace after packagename */
      while (isspace(*p)) p++;
      if (*p == '(') {			/* if we have a versioned relation */
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
            parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
                    _("`%s' field, reference to `%.255s':\n"
                    " bad version relationship %c%c"),
                    fip->name,depname,c1,c2);
            dop->verrel= dvr_none;
          } else {
            parseerr(NULL,filename,lno, warnto,warncount,pigp,1,
                     _("`%s' field, reference to `%.255s':\n"
                     " `%c' is obsolete, use `%c=' or `%c%c' instead"),
                     fip->name,depname,c1,c1,c1,c1);
            dop->verrel |= (dvrf_orequal | dvrf_builtup);
          }
        } else if (c1 == '=') {
          dop->verrel= dvr_exact;
          p++;
        } else {
          parseerr(NULL,filename,lno, warnto,warncount,pigp,1,
                   _("`%s' field, reference to `%.255s':\n"
                   " implicit exact match on version number, suggest using `=' instead"),
                   fip->name,depname);
          dop->verrel= dvr_exact;
        }
	if ((dop->verrel!=dvr_exact) && (fip->integer==dep_provides))
	  parseerr(NULL,filename,lno,warnto,warncount,pigp,1,
		  _("Only exact versions may be used for Provides"));

        if (!isspace(*p) && !isalnum(*p)) {
          parseerr(NULL,filename,lno, warnto,warncount,pigp,1,
                   _("`%s' field, reference to `%.255s':\n"
                   " version value starts with non-alphanumeric, suggest adding a space"),
                   fip->name,depname);
        }
/* skip spaces between the relation and the version */
        while (isspace(*p)) p++;

	versionstart= p;
        while (*p && *p != ')' && *p != '(') {
          if (isspace(*p)) break;
          p++;
        }
	versionlength= p - versionstart;
        while (isspace(*p)) p++;
        if (*p == '(') parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
                                _("`%s' field, reference to `%.255s': "
                                "version contains `('"),fip->name,depname);
	else if (*p != ')') parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
                                _("`%s' field, reference to `%.255s': "
                                "version contains ` '"),fip->name,depname);
        else if (*p == 0) parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
                                   _("`%s' field, reference to `%.255s': "
                                   "version unterminated"),fip->name,depname);
	if (versionlength >=  versionused) {
	  versionused= versionlength;
	  version= realloc(version,versionlength+1);
	}
	strncpy(version,  versionstart, versionlength);
	*(version + versionlength)= 0;
        emsg= parseversion(&dop->version,version);
        if (emsg) parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
                           _("`%s' field, reference to `%.255s': "
                           "error in version: %.255s"),fip->name,depname,emsg);
        p++; while (isspace(*p)) p++;
      } else {
        dop->verrel= dvr_none;
        blankversion(&dop->version);
      }
      if (!*p || *p == ',') break;
      if (*p != '|')
        parseerr(NULL,filename,lno, warnto,warncount,pigp,0, _("`%s' field, syntax"
                 " error after reference to package `%.255s'"),
                 fip->name, dop->ed->name);
      if (fip->integer == dep_conflicts ||
          fip->integer == dep_provides ||
          fip->integer == dep_replaces)
        parseerr(NULL,filename,lno, warnto,warncount,pigp,0,
                 _("alternatives (`|') not allowed in %s field"),
                 fip->name);
      p++; while (isspace(*p)) p++;
    }
    if (!*p) break;
    p++; while (isspace(*p)) p++;
  }
}

