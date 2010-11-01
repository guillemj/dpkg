/*
 * libdpkg - Debian packaging suite library routines
 * parse.c - database file parsing, main package/field loop
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

#include <sys/types.h>
#include <sys/stat.h>
#ifdef USE_MMAP
#include <sys/mman.h>
#endif

#include <assert.h>
#include <fcntl.h>
#include <ctype.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/parsedump.h>
#include <dpkg/buffer.h>

/**
 * Fields information.
 */
const struct fieldinfo fieldinfos[]= {
  /* Note: Capitalization of field name strings is important. */
  { "Package",          f_name,            w_name                                     },
  { "Essential",        f_boolean,         w_booleandefno,   PKGIFPOFF(essential)     },
  { "Status",           f_status,          w_status                                   },
  { "Priority",         f_priority,        w_priority                                 },
  { "Section",          f_section,         w_section                                  },
  { "Installed-Size",   f_charfield,       w_charfield,      PKGIFPOFF(installedsize) },
  { "Origin",           f_charfield,       w_charfield,      PKGIFPOFF(origin)        },
  { "Maintainer",       f_charfield,       w_charfield,      PKGIFPOFF(maintainer)    },
  { "Bugs",             f_charfield,       w_charfield,      PKGIFPOFF(bugs)          },
  { "Architecture",     f_charfield,       w_charfield,      PKGIFPOFF(architecture)  },
  { "Source",           f_charfield,       w_charfield,      PKGIFPOFF(source)        },
  { "Version",          f_version,         w_version,        PKGIFPOFF(version)       },
  { "Revision",         f_revision,        w_null                                     },
  { "Config-Version",   f_configversion,   w_configversion                            },
  { "Replaces",         f_dependency,      w_dependency,     dep_replaces             },
  { "Provides",         f_dependency,      w_dependency,     dep_provides             },
  { "Depends",          f_dependency,      w_dependency,     dep_depends              },
  { "Pre-Depends",      f_dependency,      w_dependency,     dep_predepends           },
  { "Recommends",       f_dependency,      w_dependency,     dep_recommends           },
  { "Suggests",         f_dependency,      w_dependency,     dep_suggests             },
  { "Breaks",           f_dependency,      w_dependency,     dep_breaks               },
  { "Conflicts",        f_dependency,      w_dependency,     dep_conflicts            },
  { "Enhances",         f_dependency,      w_dependency,     dep_enhances             },
  { "Conffiles",        f_conffiles,       w_conffiles                                },
  { "Filename",         f_filecharf,       w_filecharf,      FILEFOFF(name)           },
  { "Size",             f_filecharf,       w_filecharf,      FILEFOFF(size)           },
  { "MD5sum",           f_filecharf,       w_filecharf,      FILEFOFF(md5sum)         },
  { "MSDOS-Filename",   f_filecharf,       w_filecharf,      FILEFOFF(msdosname)      },
  { "Description",      f_charfield,       w_charfield,      PKGIFPOFF(description)   },
  { "Triggers-Pending", f_trigpend,        w_trigpend                                 },
  { "Triggers-Awaited", f_trigaw,          w_trigaw                                   },
  /* Note that aliases are added to the nicknames table in parsehelp.c. */
  {  NULL                                                                             }
};

/**
 * Parse an RFC-822 style file.
 *
 * warnto, warncount and donep may be NULL.
 * If donep is not NULL only one package's information is expected.
 */
int parsedb(const char *filename, enum parsedbflags flags,
            struct pkginfo **donep, int *warncount)
{
  static int fd;
  struct pkginfo newpig, *pigp;
  struct pkginfoperfile *newpifp, *pifp;
  struct arbitraryfield *arp, **larpp;
  struct trigaw *ta;
  int pdone;
  int fieldencountered[array_count(fieldinfos)];
  const struct fieldinfo *fip;
  const struct nickname *nick;
  char *data, *dataptr, *endptr;
  const char *fieldstart, *valuestart;
  char *value= NULL;
  int fieldlen= 0, valuelen= 0;
  int *ip, c;
  struct stat st;
  struct parsedb_state ps;

  ps.filename = filename;
  ps.flags = flags;
  ps.lno = 0;
  ps.warncount = 0;

  newpifp= (flags & pdb_recordavailable) ? &newpig.available : &newpig.installed;
  fd= open(filename, O_RDONLY);
  if (fd == -1) ohshite(_("failed to open package info file `%.255s' for reading"),filename);

  push_cleanup(cu_closefd, ~ehflag_normaltidy, NULL, 0, 1, &fd);

  if (fstat(fd, &st) == -1)
    ohshite(_("can't stat package info file `%.255s'"),filename);

  if (st.st_size > 0) {
#ifdef USE_MMAP
    dataptr = mmap(NULL, st.st_size, PROT_READ, MAP_SHARED, fd, 0);
    if (dataptr == MAP_FAILED)
      ohshite(_("can't mmap package info file `%.255s'"),filename);
#else
    dataptr = m_malloc(st.st_size);

    fd_buf_copy(fd, dataptr, st.st_size, _("copy info file `%.255s'"), filename);
#endif
    data= dataptr;
    endptr = dataptr + st.st_size;
  } else {
    data= dataptr= endptr= NULL;
  }

  pdone= 0;
#define EOF_mmap(dataptr, endptr)	(dataptr >= endptr)
#define getc_mmap(dataptr)		*dataptr++;
#define ungetc_mmap(c, dataptr, data)	dataptr--;

  /* Loop per package. */
  for (;;) {
    memset(fieldencountered, 0, sizeof(fieldencountered));
    pkg_blank(&newpig);

    /* Skip adjacent new lines. */
    while(!EOF_mmap(dataptr, endptr)) {
      c= getc_mmap(dataptr); if (c!='\n' && c!=MSDOS_EOF_CHAR ) break;
      ps.lno++;
    }
    if (EOF_mmap(dataptr, endptr)) break;

    /* Loop per field. */
    for (;;) {
      fieldstart= dataptr - 1;
      while (!EOF_mmap(dataptr, endptr) && !isspace(c) && c!=':' && c!=MSDOS_EOF_CHAR)
        c= getc_mmap(dataptr);
      fieldlen= dataptr - fieldstart - 1;
      while (!EOF_mmap(dataptr, endptr) && c != '\n' && isspace(c)) c= getc_mmap(dataptr);
      if (EOF_mmap(dataptr, endptr))
        parse_error(&ps, &newpig,
                    _("EOF after field name `%.*s'"), fieldlen, fieldstart);
      if (c == '\n')
        parse_error(&ps, &newpig,
                    _("newline in field name `%.*s'"), fieldlen, fieldstart);
      if (c == MSDOS_EOF_CHAR)
        parse_error(&ps, &newpig,
                    _("MSDOS EOF (^Z) in field name `%.*s'"),
                    fieldlen, fieldstart);
      if (c != ':')
        parse_error(&ps, &newpig,
                    _("field name `%.*s' must be followed by colon"),
                    fieldlen, fieldstart);
      /* Skip space after ‘:’ but before value and EOL. */
      while(!EOF_mmap(dataptr, endptr)) {
        c= getc_mmap(dataptr);
        if (c == '\n' || !isspace(c)) break;
      }
      if (EOF_mmap(dataptr, endptr))
        parse_error(&ps, &newpig,
                    _("EOF before value of field `%.*s' (missing final newline)"),
                 fieldlen,fieldstart);
      if (c == MSDOS_EOF_CHAR)
        parse_error(&ps, &newpig,
                    _("MSDOS EOF char in value of field `%.*s' (missing newline?)"),
                    fieldlen,fieldstart);
      valuestart= dataptr - 1;
      for (;;) {
        if (c == '\n' || c == MSDOS_EOF_CHAR) {
          ps.lno++;
	  if (EOF_mmap(dataptr, endptr)) break;
          c= getc_mmap(dataptr);
          /* Found double EOL, or start of new field. */
          if (EOF_mmap(dataptr, endptr) || c == '\n' || !isspace(c)) break;
          ungetc_mmap(c,dataptr, data);
          c= '\n';
        } else if (EOF_mmap(dataptr, endptr)) {
          parse_error(&ps, &newpig,
                      _("EOF during value of field `%.*s' (missing final newline)"),
                      fieldlen,fieldstart);
        }
        c= getc_mmap(dataptr);
      }
      valuelen= dataptr - valuestart - 1;
      /* Trim ending space on value. */
      while (valuelen && isspace(*(valuestart+valuelen-1)))
 valuelen--;
      for (nick = nicknames;
           nick->nick && (strncasecmp(nick->nick, fieldstart, fieldlen) ||
                          nick->nick[fieldlen] != '\0'); nick++) ;
      if (nick->nick) {
	fieldstart= nick->canon;
	fieldlen= strlen(fieldstart);
      }
      for (fip= fieldinfos, ip= fieldencountered;
           fip->name && strncasecmp(fieldstart,fip->name, fieldlen);
           fip++, ip++);
      if (fip->name) {
        value = m_realloc(value, valuelen + 1);
	memcpy(value,valuestart,valuelen);
        *(value + valuelen) = '\0';
        if ((*ip)++)
          parse_error(&ps, &newpig,
                      _("duplicate value for `%s' field"), fip->name);
        fip->rcall(&newpig, newpifp, &ps, value, fip);
      } else {
        if (fieldlen<2)
          parse_error(&ps, &newpig,
                      _("user-defined field name `%.*s' too short"),
                      fieldlen, fieldstart);
        larpp= &newpifp->arbs;
        while ((arp= *larpp) != NULL) {
          if (!strncasecmp(arp->name,fieldstart,fieldlen))
            parse_error(&ps, &newpig,
                       _("duplicate value for user-defined field `%.*s'"),
                       fieldlen, fieldstart);
          larpp= &arp->next;
        }
        arp= nfmalloc(sizeof(struct arbitraryfield));
        arp->name= nfstrnsave(fieldstart,fieldlen);
        arp->value= nfstrnsave(valuestart,valuelen);
        arp->next= NULL;
        *larpp= arp;
      }
      if (EOF_mmap(dataptr, endptr) || c == '\n' || c == MSDOS_EOF_CHAR) break;
    } /* Loop per field. */
    if (pdone && donep)
      parse_error(&ps, &newpig,
                  _("several package info entries found, only one allowed"));
    parse_must_have_field(&ps, &newpig, newpig.name, "package name");
    /* XXX: We need to check for status != stat_halfinstalled as while
     * unpacking a deselected package, it will not have yet all data in
     * place. But we cannot check for > stat_halfinstalled as stat_configfiles
     * always should have those fields. */
    if ((flags & pdb_recordavailable) ||
        (newpig.status != stat_notinstalled &&
         newpig.status != stat_halfinstalled)) {
      parse_ensure_have_field(&ps, &newpig,
                              &newpifp->description, "description");
      parse_ensure_have_field(&ps, &newpig,
                              &newpifp->maintainer, "maintainer");
      parse_must_have_field(&ps, &newpig,
                            newpifp->version.version, "version");
    }
    if (flags & pdb_recordavailable)
      parse_ensure_have_field(&ps, &newpig,
                              &newpifp->architecture, "architecture");

    /* Check the Config-Version information:
     * If there is a Config-Version it is definitely to be used, but
     * there shouldn't be one if the package is ‘installed’ (in which case
     * the Version and/or Revision will be copied) or if the package is
     * ‘not-installed’ (in which case there is no Config-Version). */
    if (!(flags & pdb_recordavailable)) {
      if (newpig.configversion.version) {
        if (newpig.status == stat_installed || newpig.status == stat_notinstalled)
          parse_error(&ps, &newpig,
                      _("Configured-Version for package with inappropriate Status"));
      } else {
        if (newpig.status == stat_installed) newpig.configversion= newpifp->version;
      }
    }

    if (newpig.trigaw.head &&
        (newpig.status <= stat_configfiles ||
         newpig.status >= stat_triggerspending))
      parse_error(&ps, &newpig,
                  _("package has status %s but triggers are awaited"),
                  statusinfos[newpig.status].name);
    else if (newpig.status == stat_triggersawaited && !newpig.trigaw.head)
      parse_error(&ps, &newpig,
                  _("package has status triggers-awaited but no triggers "
                    "awaited"));

    if (!(newpig.status == stat_triggerspending ||
          newpig.status == stat_triggersawaited) &&
        newpig.trigpend_head)
      parse_error(&ps, &newpig,
                  _("package has status %s but triggers are pending"),
                  statusinfos[newpig.status].name);
    else if (newpig.status == stat_triggerspending && !newpig.trigpend_head)
      parse_error(&ps, &newpig,
                  _("package has status triggers-pending but no triggers "
                    "pending"));

    /* FIXME: There was a bug that could make a not-installed package have
     * conffiles, so we check for them here and remove them (rather than
     * calling it an error, which will do at some point). */
    if (!(flags & pdb_recordavailable) &&
        newpig.status == stat_notinstalled &&
        newpifp->conffiles) {
      parse_warn(&ps, &newpig,
                 _("Package which in state not-installed has conffiles, "
                   "forgetting them"));
      newpifp->conffiles= NULL;
    }

    /* XXX: Mark not-installed leftover packages for automatic removal on
     * next database dump. This code can be removed after dpkg 1.16.x, when
     * there's guarantee that no leftover is found on the status file on
     * major distributions. */
    if (!(flags & pdb_recordavailable) &&
        newpig.status == stat_notinstalled &&
        newpig.eflag == eflag_ok &&
        (newpig.want == want_purge ||
         newpig.want == want_deinstall ||
         newpig.want == want_hold)) {
      newpig.want = want_unknown;
    }

    pigp = pkg_db_find(newpig.name);
    pifp= (flags & pdb_recordavailable) ? &pigp->available : &pigp->installed;

    if ((flags & pdb_ignoreolder) &&
	versioncompare(&newpifp->version, &pifp->version) < 0)
      continue;

    /* Copy the priority and section across, but don't overwrite existing
     * values if the pdb_weakclassification flag is set. */
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
    /* Leave the ‘depended’ pointer alone, we've just gone to such
     * trouble to get it right :-). The ‘depends’ pointer in
     * pifp was indeed also updated by copy_dependency_links,
     * but since the value was that from newpifp anyway there's
     * no need to copy it back. */
    newpifp->depended= pifp->depended;

    /* Copy across data. */
    memcpy(pifp,newpifp,sizeof(struct pkginfoperfile));
    if (!(flags & pdb_recordavailable)) {
      pigp->want= newpig.want;
      pigp->eflag= newpig.eflag;
      pigp->status= newpig.status;
      pigp->configversion= newpig.configversion;
      pigp->files= NULL;

      pigp->trigpend_head = newpig.trigpend_head;
      pigp->trigaw = newpig.trigaw;
      for (ta = pigp->trigaw.head; ta; ta = ta->sameaw.next) {
        assert(ta->aw == &newpig);
        ta->aw = pigp;
        /* ->othertrigaw_head is updated by trig_note_aw in *(pkg_db_find())
         * rather than in newpig. */
      }

    } else if (!(flags & pdb_ignorefiles)) {
      pigp->files= newpig.files;
    }

    if (donep) *donep= pigp;
    pdone++;
    if (EOF_mmap(dataptr, endptr)) break;
    if (c == '\n')
      ps.lno++;
  }
  if (data != NULL) {
#ifdef USE_MMAP
    munmap(data, st.st_size);
#else
    free(data);
#endif
  }
  free(value);
  pop_cleanup(ehflag_normaltidy);
  if (close(fd)) ohshite(_("failed to close after read: `%.255s'"),filename);
  if (donep && !pdone) ohshit(_("no package information in `%.255s'"),filename);

  if (warncount)
    *warncount = ps.warncount;

  return pdone;
}

/**
 * Copy dependency links structures.
 *
 * This routine is used to update the ‘reverse’ dependency pointers when
 * new ‘forwards’ information has been constructed. It first removes all
 * the links based on the old information. The old information starts in
 * *updateme; after much brou-ha-ha the reverse structures are created
 * and *updateme is set to the value from newdepends.
 *
 * @param pkg The package we're doing this for. This is used to construct
 *        correct uplinks.
 * @param updateme The forwards dependency pointer that we are to update.
 *        This starts out containing the old forwards info, which we use to
 *        unthread the old reverse links. After we're done it is updated.
 * @param newdepends The value that we ultimately want to have in updateme.
 * @param available The pkginfoperfile to modify, available or installed.
 *
 * It is likely that the backward pointer for the package in question
 * (‘depended’) will be updated by this routine, but this will happen by
 * the routine traversing the dependency data structures. It doesn't need
 * to be told where to update that; I just mention it as something that
 * one should be cautious about.
 */
void copy_dependency_links(struct pkginfo *pkg,
                           struct dependency **updateme,
                           struct dependency *newdepends,
                           bool available)
{
  struct dependency *dyp;
  struct deppossi *dop;
  struct pkginfoperfile *addtopifp;
  
  /* Delete ‘backward’ (‘depended’) links from other packages to
   * dependencies listed in old version of this one. We do this by
   * going through all the dependencies in the old version of this
   * one and following them down to find which deppossi nodes to
   * remove. */
  for (dyp= *updateme; dyp; dyp= dyp->next) {
    for (dop= dyp->list; dop; dop= dop->next) {
      if (dop->rev_prev)
        dop->rev_prev->rev_next = dop->rev_next;
      else
        if (available)
          dop->ed->available.depended = dop->rev_next;
        else
          dop->ed->installed.depended = dop->rev_next;
      if (dop->rev_next)
        dop->rev_next->rev_prev = dop->rev_prev;
    }
  }
  /* Now fill in new ‘ed’ links from other packages to dependencies
   * listed in new version of this one, and set our uplinks correctly. */
  for (dyp= newdepends; dyp; dyp= dyp->next) {
    dyp->up= pkg;
    for (dop= dyp->list; dop; dop= dop->next) {
      addtopifp= available ? &dop->ed->available : &dop->ed->installed;
      dop->rev_next = addtopifp->depended;
      dop->rev_prev = NULL;
      if (addtopifp->depended)
        addtopifp->depended->rev_prev = dop;
      addtopifp->depended= dop;
    }
  }
  /* Finally, we fill in the new value. */
  *updateme= newdepends;
}
