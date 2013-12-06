/*
 * libdpkg - Debian packaging suite library routines
 * dump.c - code to write in-core database to a file
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2001 Wichert Akkerman
 * Copyright © 2006,2008-2012 Guillem Jover <guillem@debian.org>
 * Copyright © 2011 Linaro Limited
 * Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/* FIXME: Don't write uninteresting packages. */

#include <config.h>
#include <compat.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <assert.h>
#include <errno.h>
#include <ctype.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/string.h>
#include <dpkg/dir.h>
#include <dpkg/parsedump.h>

static inline void
varbuf_add_fieldname(struct varbuf *vb, const struct fieldinfo *fip)
{
  varbuf_add_str(vb, fip->name);
  varbuf_add_str(vb, ": ");
}

void
w_name(struct varbuf *vb,
       const struct pkginfo *pkg, const struct pkgbin *pkgbin,
       enum fwriteflags flags, const struct fieldinfo *fip)
{
  assert(pkg->set->name);
  if (flags&fw_printheader)
    varbuf_add_str(vb, "Package: ");
  varbuf_add_str(vb, pkg->set->name);
  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_version(struct varbuf *vb,
          const struct pkginfo *pkg, const struct pkgbin *pkgbin,
          enum fwriteflags flags, const struct fieldinfo *fip)
{
  if (!dpkg_version_is_informative(&pkgbin->version))
    return;
  if (flags&fw_printheader)
    varbuf_add_str(vb, "Version: ");
  varbufversion(vb, &pkgbin->version, vdew_nonambig);
  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_configversion(struct varbuf *vb,
                const struct pkginfo *pkg, const struct pkgbin *pkgbin,
                enum fwriteflags flags, const struct fieldinfo *fip)
{
  if (pkgbin != &pkg->installed)
    return;
  if (!dpkg_version_is_informative(&pkg->configversion))
    return;
  if (pkg->status == stat_installed ||
      pkg->status == stat_notinstalled ||
      pkg->status == stat_triggerspending)
    return;
  if (flags&fw_printheader)
    varbuf_add_str(vb, "Config-Version: ");
  varbufversion(vb, &pkg->configversion, vdew_nonambig);
  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_null(struct varbuf *vb,
       const struct pkginfo *pkg, const struct pkgbin *pkgbin,
       enum fwriteflags flags, const struct fieldinfo *fip)
{
}

void
w_section(struct varbuf *vb,
          const struct pkginfo *pkg, const struct pkgbin *pkgbin,
          enum fwriteflags flags, const struct fieldinfo *fip)
{
  const char *value = pkg->section;

  if (str_is_unset(value))
    return;
  if (flags&fw_printheader)
    varbuf_add_str(vb, "Section: ");
  varbuf_add_str(vb, value);
  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_charfield(struct varbuf *vb,
            const struct pkginfo *pkg, const struct pkgbin *pkgbin,
            enum fwriteflags flags, const struct fieldinfo *fip)
{
  const char *value = STRUCTFIELD(pkgbin, fip->integer, const char *);

  if (str_is_unset(value))
    return;
  if (flags & fw_printheader)
    varbuf_add_fieldname(vb, fip);
  varbuf_add_str(vb, value);
  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_filecharf(struct varbuf *vb,
            const struct pkginfo *pkg, const struct pkgbin *pkgbin,
            enum fwriteflags flags, const struct fieldinfo *fip)
{
  struct filedetails *fdp;

  if (pkgbin != &pkg->available)
    return;
  fdp = pkg->files;
  if (!fdp || !STRUCTFIELD(fdp, fip->integer, const char *))
    return;

  if (flags&fw_printheader) {
    varbuf_add_str(vb, fip->name);
    varbuf_add_char(vb, ':');
  }

  while (fdp) {
    varbuf_add_char(vb, ' ');
    varbuf_add_str(vb, STRUCTFIELD(fdp, fip->integer, const char *));
    fdp= fdp->next;
  }

  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_booleandefno(struct varbuf *vb,
               const struct pkginfo *pkg, const struct pkgbin *pkgbin,
               enum fwriteflags flags, const struct fieldinfo *fip)
{
  bool value = STRUCTFIELD(pkgbin, fip->integer, bool);

  if ((flags & fw_printheader) && !value)
    return;

  if (flags & fw_printheader)
    varbuf_add_fieldname(vb, fip);

  varbuf_add_str(vb, value ? "yes" : "no");

  if (flags & fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_multiarch(struct varbuf *vb,
            const struct pkginfo *pkg, const struct pkgbin *pkgbin,
            enum fwriteflags flags, const struct fieldinfo *fip)
{
  int value = STRUCTFIELD(pkgbin, fip->integer, int);

  if ((flags & fw_printheader) && !value)
    return;

  if (flags & fw_printheader)
    varbuf_add_fieldname(vb, fip);

  varbuf_add_str(vb, multiarchinfos[value].name);

  if (flags & fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_architecture(struct varbuf *vb,
               const struct pkginfo *pkg, const struct pkgbin *pkgbin,
               enum fwriteflags flags, const struct fieldinfo *fip)
{
  if (!pkgbin->arch)
    return;
  if (pkgbin->arch->type == arch_none)
    return;
  if (pkgbin->arch->type == arch_empty)
    return;

  if (flags & fw_printheader)
    varbuf_add_fieldname(vb, fip);
  varbuf_add_str(vb, pkgbin->arch->name);
  if (flags & fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_priority(struct varbuf *vb,
           const struct pkginfo *pkg, const struct pkgbin *pkgbin,
           enum fwriteflags flags, const struct fieldinfo *fip)
{
  if (pkg->priority == pri_unknown)
    return;
  assert(pkg->priority <= pri_unknown);
  if (flags&fw_printheader)
    varbuf_add_str(vb, "Priority: ");
  varbuf_add_str(vb, pkg->priority == pri_other ?
                     pkg->otherpriority :
                     priorityinfos[pkg->priority].name);
  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_status(struct varbuf *vb,
         const struct pkginfo *pkg, const struct pkgbin *pkgbin,
         enum fwriteflags flags, const struct fieldinfo *fip)
{
  if (pkgbin != &pkg->installed)
    return;
  assert(pkg->want <= want_purge);
  assert(pkg->eflag <= eflag_reinstreq);

#define PEND pkg->trigpend_head
#define AW pkg->trigaw.head
  switch (pkg->status) {
  case stat_notinstalled:
  case stat_configfiles:
    assert(!PEND);
    assert(!AW);
    break;
  case stat_halfinstalled:
  case stat_unpacked:
  case stat_halfconfigured:
    assert(!PEND);
    break;
  case stat_triggersawaited:
    assert(AW);
    break;
  case stat_triggerspending:
    assert(PEND);
    assert(!AW);
    break;
  case stat_installed:
    assert(!PEND);
    assert(!AW);
    break;
  default:
    internerr("unknown package status '%d'", pkg->status);
  }
#undef PEND
#undef AW

  if (flags&fw_printheader)
    varbuf_add_str(vb, "Status: ");
  varbuf_add_str(vb, wantinfos[pkg->want].name);
  varbuf_add_char(vb, ' ');
  varbuf_add_str(vb, eflaginfos[pkg->eflag].name);
  varbuf_add_char(vb, ' ');
  varbuf_add_str(vb, statusinfos[pkg->status].name);
  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void varbufdependency(struct varbuf *vb, struct dependency *dep) {
  struct deppossi *dop;
  const char *possdel;

  possdel= "";
  for (dop= dep->list; dop; dop= dop->next) {
    assert(dop->up == dep);
    varbuf_add_str(vb, possdel);
    possdel = " | ";
    varbuf_add_str(vb, dop->ed->name);
    if (!dop->arch_is_implicit)
      varbuf_add_archqual(vb, dop->arch);
    if (dop->verrel != dpkg_relation_none) {
      varbuf_add_str(vb, " (");
      switch (dop->verrel) {
      case dpkg_relation_eq:
        varbuf_add_char(vb, '=');
        break;
      case dpkg_relation_ge:
        varbuf_add_str(vb, ">=");
        break;
      case dpkg_relation_le:
        varbuf_add_str(vb, "<=");
        break;
      case dpkg_relation_gt:
        varbuf_add_str(vb, ">>");
        break;
      case dpkg_relation_lt:
        varbuf_add_str(vb, "<<");
        break;
      default:
        internerr("unknown dpkg_relation %d", dop->verrel);
      }
      varbuf_add_char(vb, ' ');
      varbufversion(vb,&dop->version,vdew_nonambig);
      varbuf_add_char(vb, ')');
    }
  }
}

void
w_dependency(struct varbuf *vb,
             const struct pkginfo *pkg, const struct pkgbin *pkgbin,
             enum fwriteflags flags, const struct fieldinfo *fip)
{
  struct dependency *dyp;
  bool dep_found = false;

  for (dyp = pkgbin->depends; dyp; dyp = dyp->next) {
    if (dyp->type != fip->integer) continue;
    assert(dyp->up == pkg);

    if (dep_found) {
      varbuf_add_str(vb, ", ");
    } else {
      if (flags & fw_printheader)
        varbuf_add_fieldname(vb, fip);
      dep_found = true;
    }
    varbufdependency(vb,dyp);
  }
  if ((flags & fw_printheader) && dep_found)
    varbuf_add_char(vb, '\n');
}

void
w_conffiles(struct varbuf *vb,
            const struct pkginfo *pkg, const struct pkgbin *pkgbin,
            enum fwriteflags flags, const struct fieldinfo *fip)
{
  struct conffile *i;

  if (!pkgbin->conffiles || pkgbin == &pkg->available)
    return;
  if (flags&fw_printheader)
    varbuf_add_str(vb, "Conffiles:\n");
  for (i = pkgbin->conffiles; i; i = i->next) {
    if (i != pkgbin->conffiles)
      varbuf_add_char(vb, '\n');
    varbuf_add_char(vb, ' ');
    varbuf_add_str(vb, i->name);
    varbuf_add_char(vb, ' ');
    varbuf_add_str(vb, i->hash);
    if (i->obsolete)
      varbuf_add_str(vb, " obsolete");
  }
  if (flags&fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_trigpend(struct varbuf *vb,
           const struct pkginfo *pkg, const struct pkgbin *pkgbin,
           enum fwriteflags flags, const struct fieldinfo *fip)
{
  struct trigpend *tp;

  if (pkgbin == &pkg->available || !pkg->trigpend_head)
    return;

  assert(pkg->status >= stat_triggersawaited &&
         pkg->status <= stat_triggerspending);

  if (flags & fw_printheader)
    varbuf_add_str(vb, "Triggers-Pending:");
  for (tp = pkg->trigpend_head; tp; tp = tp->next) {
    varbuf_add_char(vb, ' ');
    varbuf_add_str(vb, tp->name);
  }
  if (flags & fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
w_trigaw(struct varbuf *vb,
         const struct pkginfo *pkg, const struct pkgbin *pkgbin,
         enum fwriteflags flags, const struct fieldinfo *fip)
{
  struct trigaw *ta;

  if (pkgbin == &pkg->available || !pkg->trigaw.head)
    return;

  assert(pkg->status > stat_configfiles &&
         pkg->status <= stat_triggersawaited);

  if (flags & fw_printheader)
    varbuf_add_str(vb, "Triggers-Awaited:");
  for (ta = pkg->trigaw.head; ta; ta = ta->sameaw.next) {
    varbuf_add_char(vb, ' ');
    varbuf_add_pkgbin_name(vb, ta->pend, &ta->pend->installed, pnaw_nonambig);
  }
  if (flags & fw_printheader)
    varbuf_add_char(vb, '\n');
}

void
varbufrecord(struct varbuf *vb,
             const struct pkginfo *pkg, const struct pkgbin *pkgbin)
{
  const struct fieldinfo *fip;
  const struct arbitraryfield *afp;

  for (fip= fieldinfos; fip->name; fip++) {
    fip->wcall(vb, pkg, pkgbin, fw_printheader, fip);
  }
  for (afp = pkgbin->arbs; afp; afp = afp->next) {
    varbuf_add_str(vb, afp->name);
    varbuf_add_str(vb, ": ");
    varbuf_add_str(vb, afp->value);
    varbuf_add_char(vb, '\n');
  }
}

void
writerecord(FILE *file, const char *filename,
            const struct pkginfo *pkg, const struct pkgbin *pkgbin)
{
  struct varbuf vb = VARBUF_INIT;

  varbufrecord(&vb, pkg, pkgbin);
  varbuf_end_str(&vb);
  if (fputs(vb.buf,file) < 0) {
    struct varbuf pkgname = VARBUF_INIT;
    int errno_saved = errno;

    varbuf_add_pkgbin_name(&pkgname, pkg, pkgbin, pnaw_nonambig);

    errno = errno_saved;
    ohshite(_("failed to write details of `%.50s' to `%.250s'"),
            pkgname.buf, filename);
  }

  varbuf_destroy(&vb);
}

void
writedb(const char *filename, enum writedb_flags flags)
{
  static char writebuf[8192];

  struct pkgiterator *it;
  struct pkginfo *pkg;
  struct pkgbin *pkgbin;
  const char *which;
  struct atomic_file *file;
  struct varbuf vb = VARBUF_INIT;

  which = (flags & wdb_dump_available) ? "available" : "status";

  file = atomic_file_new(filename, aff_backup);
  atomic_file_open(file);
  if (setvbuf(file->fp, writebuf, _IOFBF, sizeof(writebuf)))
    ohshite(_("unable to set buffering on %s database file"), which);

  it = pkg_db_iter_new();
  while ((pkg = pkg_db_iter_next_pkg(it)) != NULL) {
    pkgbin = (flags & wdb_dump_available) ? &pkg->available : &pkg->installed;
    /* Don't dump records which have no useful content. */
    if (!pkg_is_informative(pkg, pkgbin))
      continue;
    varbufrecord(&vb, pkg, pkgbin);
    varbuf_add_char(&vb, '\n');
    varbuf_end_str(&vb);
    if (fputs(vb.buf, file->fp) < 0)
      ohshite(_("failed to write %s database record about '%.50s' to '%.250s'"),
              which, pkgbin_name(pkg, pkgbin, pnaw_nonambig), filename);
    varbuf_reset(&vb);
  }
  pkg_db_iter_free(it);
  varbuf_destroy(&vb);
  if (flags & wdb_must_sync)
    atomic_file_sync(file);

  atomic_file_close(file);
  atomic_file_commit(file);
  atomic_file_free(file);

  if (flags & wdb_must_sync)
    dir_sync_path_parent(filename);
}
