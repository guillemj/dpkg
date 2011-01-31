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
#include <dpkg/fdio.h>

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
  { "Architecture",     f_charfield,       w_charfield,      PKGIFPOFF(arch)          },
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

struct field_state {
  const char *fieldstart;
  const char *valuestart;
  struct varbuf value;
  int fieldlen;
  int valuelen;
  int fieldencountered[array_count(fieldinfos)];
};

/**
 * Parse the field and value into the package being constructed.
 */
static void
pkg_parse_field(struct parsedb_state *ps, struct field_state *fs,
                struct pkginfo *pkg, struct pkgbin *pkgbin)
{
  const struct nickname *nick;
  const struct fieldinfo *fip;
  int *ip;

  for (nick = nicknames; nick->nick; nick++)
    if (strncasecmp(nick->nick, fs->fieldstart, fs->fieldlen) == 0 &&
        nick->nick[fs->fieldlen] == '\0')
      break;
  if (nick->nick) {
    fs->fieldstart = nick->canon;
    fs->fieldlen = strlen(fs->fieldstart);
  }

  for (fip = fieldinfos, ip = fs->fieldencountered; fip->name; fip++, ip++)
    if (strncasecmp(fip->name, fs->fieldstart, fs->fieldlen) == 0)
      break;
  if (fip->name) {
    if ((*ip)++)
      parse_error(ps, pkg,
                  _("duplicate value for `%s' field"), fip->name);

    varbuf_reset(&fs->value);
    varbuf_add_buf(&fs->value, fs->valuestart, fs->valuelen);
    varbuf_add_char(&fs->value, '\0');

    fip->rcall(pkg, pkgbin, ps, fs->value.buf, fip);
  } else {
    struct arbitraryfield *arp, **larpp;

    if (fs->fieldlen < 2)
      parse_error(ps, pkg,
                  _("user-defined field name `%.*s' too short"),
                  fs->fieldlen, fs->fieldstart);
    larpp = &pkgbin->arbs;
    while ((arp = *larpp) != NULL) {
      if (!strncasecmp(arp->name, fs->fieldstart, fs->fieldlen))
        parse_error(ps, pkg,
                   _("duplicate value for user-defined field `%.*s'"),
                   fs->fieldlen, fs->fieldstart);
      larpp = &arp->next;
    }
    arp = nfmalloc(sizeof(struct arbitraryfield));
    arp->name = nfstrnsave(fs->fieldstart, fs->fieldlen);
    arp->value = nfstrnsave(fs->valuestart, fs->valuelen);
    arp->next = NULL;
    *larpp = arp;
  }
}

/**
 * Verify and fixup the package structure being constructed.
 */
static void
pkg_parse_verify(struct parsedb_state *ps,
                 struct pkginfo *pkg, struct pkgbin *pkgbin)
{
  parse_must_have_field(ps, pkg, pkg->name, "package name");

  /* XXX: We need to check for status != stat_halfinstalled as while
   * unpacking a deselected package, it will not have yet all data in
   * place. But we cannot check for > stat_halfinstalled as stat_configfiles
   * always should have those fields. */
  if ((ps->flags & pdb_recordavailable) ||
      (pkg->status != stat_notinstalled &&
       pkg->status != stat_halfinstalled)) {
    parse_ensure_have_field(ps, pkg, &pkgbin->description, "description");
    parse_ensure_have_field(ps, pkg, &pkgbin->maintainer, "maintainer");
    parse_must_have_field(ps, pkg, pkgbin->version.version, "version");
  }

  /* We always want usable architecture information, so that it can be used
   * safely on string comparisons and the like. */
  parse_ensure_have_field(ps, pkg, &pkgbin->arch, "architecture");

  /* Check the Config-Version information:
   * If there is a Config-Version it is definitely to be used, but
   * there shouldn't be one if the package is ‘installed’ (in which case
   * the Version and/or Revision will be copied) or if the package is
   * ‘not-installed’ (in which case there is no Config-Version). */
  if (!(ps->flags & pdb_recordavailable)) {
    if (pkg->configversion.version) {
      if (pkg->status == stat_installed || pkg->status == stat_notinstalled)
        parse_error(ps, pkg,
                    _("Configured-Version for package with inappropriate Status"));
    } else {
      if (pkg->status == stat_installed)
        pkg->configversion = pkgbin->version;
    }
  }

  if (pkg->trigaw.head &&
      (pkg->status <= stat_configfiles ||
       pkg->status >= stat_triggerspending))
    parse_error(ps, pkg,
                _("package has status %s but triggers are awaited"),
                statusinfos[pkg->status].name);
  else if (pkg->status == stat_triggersawaited && !pkg->trigaw.head)
    parse_error(ps, pkg,
                _("package has status triggers-awaited but no triggers awaited"));

  if (pkg->trigpend_head &&
      !(pkg->status == stat_triggerspending ||
        pkg->status == stat_triggersawaited))
    parse_error(ps, pkg,
                _("package has status %s but triggers are pending"),
                statusinfos[pkg->status].name);
  else if (pkg->status == stat_triggerspending && !pkg->trigpend_head)
    parse_error(ps, pkg,
                _("package has status triggers-pending but no triggers "
                  "pending"));

  /* FIXME: There was a bug that could make a not-installed package have
   * conffiles, so we check for them here and remove them (rather than
   * calling it an error, which will do at some point). */
  if (!(ps->flags & pdb_recordavailable) &&
      pkg->status == stat_notinstalled &&
      pkgbin->conffiles) {
    parse_warn(ps, pkg,
               _("Package which in state not-installed has conffiles, "
                 "forgetting them"));
    pkgbin->conffiles = NULL;
  }

  /* XXX: Mark not-installed leftover packages for automatic removal on
   * next database dump. This code can be removed after dpkg 1.16.x, when
   * there's guarantee that no leftover is found on the status file on
   * major distributions. */
  if (!(ps->flags & pdb_recordavailable) &&
      pkg->status == stat_notinstalled &&
      pkg->eflag == eflag_ok &&
      (pkg->want == want_purge ||
       pkg->want == want_deinstall ||
       pkg->want == want_hold)) {
    pkg->want = want_unknown;
  }
}

/**
 * Copy into the in-core database the package being constructed.
 */
static void
pkg_parse_copy(struct parsedb_state *ps,
               struct pkginfo *dst_pkg, struct pkgbin *dst_pkgbin,
               struct pkginfo *src_pkg, struct pkgbin *src_pkgbin)
{
  /* Copy the priority and section across, but don't overwrite existing
   * values if the pdb_weakclassification flag is set. */
  if (src_pkg->section && *src_pkg->section &&
      !((ps->flags & pdb_weakclassification) &&
        dst_pkg->section && *dst_pkg->section))
    dst_pkg->section = src_pkg->section;
  if (src_pkg->priority != pri_unknown &&
      !((ps->flags & pdb_weakclassification) &&
        dst_pkg->priority != pri_unknown)) {
    dst_pkg->priority = src_pkg->priority;
    if (src_pkg->priority == pri_other)
      dst_pkg->otherpriority = src_pkg->otherpriority;
  }

  /* Sort out the dependency mess. */
  copy_dependency_links(dst_pkg, &dst_pkgbin->depends, src_pkgbin->depends,
                        (ps->flags & pdb_recordavailable) ? true : false);
  /* Leave the ‘depended’ pointer alone, we've just gone to such
   * trouble to get it right :-). The ‘depends’ pointer in
   * pifp was indeed also updated by copy_dependency_links,
   * but since the value was that from newpifp anyway there's
   * no need to copy it back. */
  dst_pkgbin->depended = src_pkgbin->depended;

  /* Copy across data. */
  memcpy(dst_pkgbin, src_pkgbin, sizeof(struct pkgbin));
  if (!(ps->flags & pdb_recordavailable)) {
    struct trigaw *ta;

    dst_pkg->want = src_pkg->want;
    dst_pkg->eflag = src_pkg->eflag;
    dst_pkg->status = src_pkg->status;
    dst_pkg->configversion = src_pkg->configversion;
    dst_pkg->files = NULL;

    dst_pkg->trigpend_head = src_pkg->trigpend_head;
    dst_pkg->trigaw = src_pkg->trigaw;
    for (ta = dst_pkg->trigaw.head; ta; ta = ta->sameaw.next) {
      assert(ta->aw == src_pkg);
      ta->aw = dst_pkg;
      /* ->othertrigaw_head is updated by trig_note_aw in *(pkg_db_find())
       * rather than in dst_pkg. */
    }
  } else if (!(ps->flags & pdb_ignorefiles)) {
    dst_pkg->files = src_pkg->files;
  }
}

/**
 * Parse an RFC-822 style file.
 *
 * warnto, warncount and donep may be NULL.
 * If donep is not NULL only one package's information is expected.
 */
int parsedb(const char *filename, enum parsedbflags flags,
            struct pkginfo **donep)
{
  static int fd;
  struct pkginfo tmp_pkg;
  struct pkginfo *new_pkg, *db_pkg;
  struct pkgbin *new_pkgbin, *db_pkgbin;
  int pdone;
  char *data, *dataptr, *endptr;
  struct stat st;
  struct parsedb_state ps;
  struct field_state fs;

  ps.filename = filename;
  ps.flags = flags;
  ps.lno = 0;

  memset(&fs, 0, sizeof(fs));

  new_pkg = &tmp_pkg;
  if (flags & pdb_recordavailable)
    new_pkgbin = &new_pkg->available;
  else
    new_pkgbin = &new_pkg->installed;

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

    if (fd_read(fd, dataptr, st.st_size) < 0)
      ohshite(_("reading package info file '%.255s'"), filename);
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
    int c;

    memset(fs.fieldencountered, 0, sizeof(fs.fieldencountered));
    pkg_blank(new_pkg);

    /* Skip adjacent new lines. */
    while(!EOF_mmap(dataptr, endptr)) {
      c= getc_mmap(dataptr); if (c!='\n' && c!=MSDOS_EOF_CHAR ) break;
      ps.lno++;
    }
    if (EOF_mmap(dataptr, endptr)) break;

    /* Loop per field. */
    for (;;) {
      fs.fieldstart = dataptr - 1;
      while (!EOF_mmap(dataptr, endptr) && !isspace(c) && c!=':' && c!=MSDOS_EOF_CHAR)
        c= getc_mmap(dataptr);
      fs.fieldlen = dataptr - fs.fieldstart - 1;
      while (!EOF_mmap(dataptr, endptr) && c != '\n' && isspace(c)) c= getc_mmap(dataptr);
      if (EOF_mmap(dataptr, endptr))
        parse_error(&ps, new_pkg,
                    _("EOF after field name `%.*s'"), fs.fieldlen, fs.fieldstart);
      if (c == '\n')
        parse_error(&ps, new_pkg,
                    _("newline in field name `%.*s'"), fs.fieldlen, fs.fieldstart);
      if (c == MSDOS_EOF_CHAR)
        parse_error(&ps, new_pkg,
                    _("MSDOS EOF (^Z) in field name `%.*s'"),
                    fs.fieldlen, fs.fieldstart);
      if (c != ':')
        parse_error(&ps, new_pkg,
                    _("field name `%.*s' must be followed by colon"),
                    fs.fieldlen, fs.fieldstart);
      /* Skip space after ‘:’ but before value and EOL. */
      while(!EOF_mmap(dataptr, endptr)) {
        c= getc_mmap(dataptr);
        if (c == '\n' || !isspace(c)) break;
      }
      if (EOF_mmap(dataptr, endptr))
        parse_error(&ps, new_pkg,
                    _("EOF before value of field `%.*s' (missing final newline)"),
                    fs.fieldlen, fs.fieldstart);
      if (c == MSDOS_EOF_CHAR)
        parse_error(&ps, new_pkg,
                    _("MSDOS EOF char in value of field `%.*s' (missing newline?)"),
                    fs.fieldlen, fs.fieldstart);
      fs.valuestart = dataptr - 1;
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
          parse_error(&ps, new_pkg,
                      _("EOF during value of field `%.*s' (missing final newline)"),
                      fs.fieldlen, fs.fieldstart);
        }
        c= getc_mmap(dataptr);
      }
      fs.valuelen = dataptr - fs.valuestart - 1;
      /* Trim ending space on value. */
      while (fs.valuelen && isspace(*(fs.valuestart + fs.valuelen - 1)))
        fs.valuelen--;

      pkg_parse_field(&ps, &fs, new_pkg, new_pkgbin);

      if (EOF_mmap(dataptr, endptr) || c == '\n' || c == MSDOS_EOF_CHAR) break;
    } /* Loop per field. */

    if (pdone && donep)
      parse_error(&ps, new_pkg,
                  _("several package info entries found, only one allowed"));

    pkg_parse_verify(&ps, new_pkg, new_pkgbin);

    db_pkg = pkg_db_find(new_pkg->name);
    if (flags & pdb_recordavailable)
      db_pkgbin = &db_pkg->available;
    else
      db_pkgbin = &db_pkg->installed;

    if ((flags & pdb_ignoreolder) &&
        versioncompare(&new_pkgbin->version, &db_pkgbin->version) < 0)
      continue;

    pkg_parse_copy(&ps, db_pkg, db_pkgbin, new_pkg, new_pkgbin);

    if (donep)
      *donep = db_pkg;
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
  varbuf_destroy(&fs.value);
  pop_cleanup(ehflag_normaltidy);
  if (close(fd)) ohshite(_("failed to close after read: `%.255s'"),filename);
  if (donep && !pdone) ohshit(_("no package information in `%.255s'"),filename);

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
 * @param available The pkgbin to modify, available or installed.
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
  struct pkgbin *addtopifp;

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
