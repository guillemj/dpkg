/*
 * libdpkg - Debian packaging suite library routines
 * parse.c - database file parsing, main package/field loop
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
#include <string.h>
#include <ctype.h>
#include <stdarg.h>

#include <config.h>
#include <dpkg.h>
#include <dpkg-db.h>
#include "parsedump.h"

const struct fieldinfo fieldinfos[]= {
  /* NB: capitalisation of these strings is important. */
  { "Package",          f_name,            w_name                                     },
  { "Essential",        f_boolean,         w_booleandefno,   PKGIFPOFF(essential)     },
  { "Status",           f_status,          w_status                                   },
  { "Priority",         f_priority,        w_priority                                 },
  { "Section",          f_section,         w_section                                  },
  { "Installed-Size",   f_charfield,       w_charfield,      PKGIFPOFF(installedsize) },
  { "Maintainer",       f_charfield,       w_charfield,      PKGIFPOFF(maintainer)    },
  { "Architecture",     f_charfield,       w_charfield,      PKGIFPOFF(architecture)  },
  { "Source",           f_charfield,       w_charfield,      PKGIFPOFF(source)        },
  { "Version",          f_version,         w_version                                  },
  { "Revision",         f_revision,        w_null                                     },
  { "Config-Version",   f_configversion,   w_configversion                            },
  { "Replaces",         f_dependency,      w_dependency,     dep_replaces             },
  { "Provides",         f_dependency,      w_dependency,     dep_provides             },
  { "Depends",          f_dependency,      w_dependency,     dep_depends              },
  { "Pre-Depends",      f_dependency,      w_dependency,     dep_predepends           },
  { "Recommends",       f_dependency,      w_dependency,     dep_recommends           },
  { "Suggests",         f_dependency,      w_dependency,     dep_suggests             },
  { "Conflicts",        f_dependency,      w_dependency,     dep_conflicts            },
  { "Conffiles",        f_conffiles,       w_conffiles                                },
  { "Filename",         f_filecharf,       w_filecharf,      FILEFOFF(name)           },
  { "Size",             f_filecharf,       w_filecharf,      FILEFOFF(size)           },
  { "MD5sum",           f_filecharf,       w_filecharf,      FILEFOFF(md5sum)         },
  { "MSDOS-Filename",   f_filecharf,       w_filecharf,      FILEFOFF(msdosname)      },
  { "Description",      f_charfield,       w_charfield,      PKGIFPOFF(description)   },
  /* Note that aliases are added to the nicknames table in parsehelp.c. */
  {  0   /* sentinel - tells code that list is ended */                               }
};
#define NFIELDS (sizeof(fieldinfos)/sizeof(struct fieldinfo))
const int nfields= NFIELDS;

static void cu_parsedb(int argc, void **argv) { fclose((FILE*)*argv); }

int parsedb(const char *filename, enum parsedbflags flags,
            struct pkginfo **donep, FILE *warnto, int *warncount) {
  /* warnto, warncount and donep may be null.
   * If donep is not null only one package's information is expected.
   */
  static char readbuf[16384];
  
  FILE *file;
  struct pkginfo newpig, *pigp;
  struct pkginfoperfile *newpifp, *pifp;
  struct arbitraryfield *arp, **larpp;
  struct varbuf field, value;
  int lno;
  int pdone;
  int fieldencountered[NFIELDS];
  const struct fieldinfo *fip;
  const struct nickname *nick;
  const char *fieldname;
  int *ip, i, c;

  if (warncount) *warncount= 0;
  newpifp= (flags & pdb_recordavailable) ? &newpig.available : &newpig.installed;
  file= fopen(filename,"r");
  if (!file) ohshite(_("failed to open package info file `%.255s' for reading"),filename);

  if (!donep) /* Reading many packages, use a nice big buffer. */
    if (setvbuf(file,readbuf,_IOFBF,sizeof(readbuf)))
      ohshite(_("unable to set buffering on status file"));

  push_cleanup(cu_parsedb,~0, 0,0, 1,(void*)file);
  varbufinit(&field); varbufinit(&value);

  lno= 1;
  pdone= 0;
  for (;;) { /* loop per package */
    i= sizeof(fieldencountered)/sizeof(int); ip= fieldencountered;
    while (i--) *ip++= 0;
    blankpackage(&newpig);
    blankpackageperfile(newpifp);
    for (;;) {
      c= getc(file); if (c!='\n' && c!=MSDOS_EOF_CHAR) break;
      lno++;
    }
    if (c == EOF) break;
    for (;;) { /* loop per field */
      varbufreset(&field);
      while (c!=EOF && !isspace(c) && c!=':' && c!=MSDOS_EOF_CHAR) {
        varbufaddc(&field,c);
        c= getc(file);
      }
      varbufaddc(&field,0);
      while (c != EOF && c != '\n' && isspace(c)) c= getc(file);
      if (c == EOF)
        parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                 _("EOF after field name `%.50s'"),field.buf);
      if (c == '\n')
        parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                 _("newline in field name `%.50s'"),field.buf);
      if (c == MSDOS_EOF_CHAR)
        parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                 _("MSDOS EOF (^Z) in field name `%.50s'"), field.buf);
      if (c != ':')
        parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                 _("field name `%.50s' must be followed by colon"), field.buf);
      varbufreset(&value);
      for (;;) {
        c= getc(file);
        if (c == EOF || c == '\n' || !isspace(c)) break;
      }
      if (c == EOF)
        parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                 _("EOF before value of field `%.50s' (missing final newline)"),
                 field.buf);
      if (c == MSDOS_EOF_CHAR)
        parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                 _("MSDOS EOF char in value of field `%.50s' (missing newline?)"),
                 field.buf);
      for (;;) {
        if (c == '\n' || c == MSDOS_EOF_CHAR) {
          lno++;
          c= getc(file);
          if (c == EOF || c == '\n' || !isspace(c)) break;
          ungetc(c,file);
          c= '\n';
        } else if (c == EOF) {
          parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                   _("EOF during value of field `%.50s' (missing final newline)"),
                   field.buf);
        }
        varbufaddc(&value,c);
        c= getc(file);
      }
      while (value.used && isspace(value.buf[value.used-1])) value.used--;
      varbufaddc(&value,0);
      fieldname= field.buf;
      for (nick= nicknames; nick->nick && strcasecmp(nick->nick,fieldname); nick++);
      if (nick->nick) fieldname= nick->canon;
      for (fip= fieldinfos, ip= fieldencountered;
           fip->name && strcasecmp(fieldname,fip->name);
           fip++, ip++);
      if (fip->name) {
        if (*ip++)
          parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                   _("duplicate value for `%s' field"), fip->name);
        fip->rcall(&newpig,newpifp,flags,filename,lno-1,warnto,warncount,value.buf,fip);
      } else {
        if (strlen(fieldname)<2)
          parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                   _("user-defined field name `%s' too short"), fieldname);
        larpp= &newpifp->arbs;
        while ((arp= *larpp) != 0) {
          if (!strcasecmp(arp->name,fieldname))
            parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                     _("duplicate value for user-defined field `%.50s'"), fieldname);
          larpp= &arp->next;
        }
        arp= nfmalloc(sizeof(struct arbitraryfield));
        arp->name= nfstrsave(fieldname);
        arp->value= nfstrsave(value.buf);
        arp->next= 0;
        *larpp= arp;
      }
      if (c == EOF || c == '\n' || c == MSDOS_EOF_CHAR) break;
    } /* loop per field */
    if (pdone && donep)
      parseerr(file,filename,lno, warnto,warncount,&newpig,0,
               _("several package info entries found, only one allowed"));
    parsemustfield(file,filename,lno, warnto,warncount,&newpig,0,
                   &newpig.name, "package name");
    if ((flags & pdb_recordavailable) || newpig.status != stat_notinstalled) {
      parsemustfield(file,filename,lno, warnto,warncount,&newpig,1,
                     &newpifp->description, "description");
      parsemustfield(file,filename,lno, warnto,warncount,&newpig,1,
                     &newpifp->maintainer, "maintainer");
      if (newpig.status != stat_halfinstalled)
        parsemustfield(file,filename,lno, warnto,warncount,&newpig,0,
                       &newpifp->version.version, "version");
    }
    if (flags & pdb_recordavailable)
      parsemustfield(file,filename,lno, warnto,warncount,&newpig,1,
                     &newpifp->architecture, "architecture");
    else if (newpifp->architecture && *newpifp->architecture)
      newpifp->architecture= 0;

    /* Check the Config-Version information:
     * If there is a Config-Version it is definitely to be used, but
     * there shouldn't be one if the package is `installed' (in which case
     * the Version and/or Revision will be copied) or if the package is
     * `not-installed' (in which case there is no Config-Version).
     */
    if (!(flags & pdb_recordavailable)) {
      if (newpig.configversion.version) {
        if (newpig.status == stat_installed || newpig.status == stat_notinstalled)
          parseerr(file,filename,lno, warnto,warncount,&newpig,0,
                   _("Configured-Version for package with inappropriate Status"));
      } else {
        if (newpig.status == stat_installed) newpig.configversion= newpifp->version;
      }
    }

    /* There was a bug that could make a not-installed package have
     * conffiles, so we check for them here and remove them (rather than
     * calling it an error, which will do at some point -- fixme).
     */
    if (!(flags & pdb_recordavailable) &&
        newpig.status == stat_notinstalled &&
        newpifp->conffiles) {
      parseerr(file,filename,lno, warnto,warncount,&newpig,1,
               _("Package which in state not-installed has conffiles, forgetting them"));
      newpifp->conffiles= 0;
    }

    pigp= findpackage(newpig.name);
    pifp= (flags & pdb_recordavailable) ? &pigp->available : &pigp->installed;
    if (!pifp->valid) blankpackageperfile(pifp);

    /* Copy the priority and section across, but don't overwrite existing
     * values if the pdb_weakclassification flag is set.
     */
    if (newpig.section && *newpig.section &&
        !((flags & pdb_weakclassification) && pigp->section && *pigp->section))
      pigp->section= newpig.section;
    if (newpig.priority != pri_unknown &&
        !((flags & pdb_weakclassification) && pigp->priority != pri_unknown)) {
      pigp->priority= newpig.priority;
      if (newpig.priority == pri_other) pigp->otherpriority= newpig.otherpriority;
    }

    /* Sort out the dependency mess. */
    copy_dependency_links(pigp,&pifp->depends,newpifp->depends,
                          (flags & pdb_recordavailable) ? 1 : 0);
    /* Leave the `depended' pointer alone, we've just gone to such
     * trouble to get it right :-).  The `depends' pointer in
     * pifp was indeed also updated by copy_dependency_links,
     * but since the value was that from newpifp anyway there's
     * no need to copy it back.
     */
    newpifp->depended= pifp->depended;

    /* Copy across data */
    memcpy(pifp,newpifp,sizeof(struct pkginfoperfile));
    if (!(flags & pdb_recordavailable)) {
      pigp->want= newpig.want;
      pigp->eflag= newpig.eflag;
      pigp->status= newpig.status;
      pigp->configversion= newpig.configversion;
      pigp->files= 0;
    } else {
      pigp->files= newpig.files;
    }

    if (donep) *donep= pigp;
    pdone++;
    if (c == EOF) break;
    if (c == '\n') lno++;
  }
  if (ferror(file)) ohshite(_("failed to read from `%.255s'"),filename);
  pop_cleanup(0);
  if (fclose(file)) ohshite(_("failed to close after read: `%.255s'"),filename);
  if (donep && !pdone) ohshit(_("no package information in `%.255s'"),filename);

  varbuffree(&field); varbuffree(&value);
  return pdone;
}

void copy_dependency_links(struct pkginfo *pkg,
                           struct dependency **updateme,
                           struct dependency *newdepends,
                           int available) {
  /* This routine is used to update the `reverse' dependency pointers
   * when new `forwards' information has been constructed.  It first
   * removes all the links based on the old information.  The old
   * information starts in *updateme; after much brou-ha-ha
   * the reverse structures are created and *updateme is set
   * to the value from newdepends.
   *
   * Parameters are:
   * pkg - the package we're doing this for.  This is used to
   *       construct correct uplinks.
   * updateme - the forwards dependency pointer that we are to
   *            update.  This starts out containing the old forwards
   *            info, which we use to unthread the old reverse
   *            links.  After we're done it is updated.
   * newdepends - the value that we ultimately want to have in
   *              updateme.
   * It is likely that the backward pointer for the package in
   * question (`depended') will be updated by this routine,
   * but this will happen by the routine traversing the dependency
   * data structures.  It doesn't need to be told where to update
   * that; I just mention it as something that one should be
   * cautious about.
   */
  struct dependency *dyp;
  struct deppossi *dop;
  struct pkginfoperfile *addtopifp;
  
  /* Delete `backward' (`depended') links from other packages to
   * dependencies listed in old version of this one.  We do this by
   * going through all the dependencies in the old version of this
   * one and following them down to find which deppossi nodes to
   * remove.
   */
  for (dyp= *updateme; dyp; dyp= dyp->next) {
    for (dop= dyp->list; dop; dop= dop->next) {
      if (dop->backrev)
        dop->backrev->nextrev= dop->nextrev;
      else
        if (available)
          dop->ed->available.depended= dop->nextrev;
        else
          dop->ed->installed.depended= dop->nextrev;
      if (dop->nextrev)
        dop->nextrev->backrev= dop->backrev;
    }
  }
  /* Now fill in new `ed' links from other packages to dependencies listed
   * in new version of this one, and set our uplinks correctly.
   */
  for (dyp= newdepends; dyp; dyp= dyp->next) {
    dyp->up= pkg;
    for (dop= dyp->list; dop; dop= dop->next) {
      addtopifp= available ? &dop->ed->available : &dop->ed->installed;
      if (!addtopifp->valid) blankpackageperfile(addtopifp);
      dop->nextrev= addtopifp->depended;
      dop->backrev= 0;
      if (addtopifp->depended)
        addtopifp->depended->backrev= dop;
      addtopifp->depended= dop;
    }
  }
  /* Finally, we fill in the new value. */
  *updateme= newdepends;
}
