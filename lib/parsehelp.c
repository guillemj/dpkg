/*
 * libdpkg - Debian packaging suite library routines
 * parsehelp.c - helpful routines for parsing and writing
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
#include <config.h>

#include <stdio.h>
#include <ctype.h>
#include <string.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include "parsedump.h"

void parseerr
(FILE *file, const char *filename, int lno, FILE *warnto, int *warncount,
 const struct pkginfo *pigp, int warnonly,
 const char *fmt, ...) 
{
  va_list al;
  char buf1[768], buf2[1000], *p, *q;
  if (file && ferror(file)) ohshite(_("failed to read `%s' at line %d"),filename,lno);
  sprintf(buf1, _("%s, in file `%.255s' near line %d"),
          warnonly ? _("warning") : _("parse error"), filename, lno);
  if (pigp && pigp->name) {
    sprintf(buf2, _(" package `%.255s'"), pigp->name);
    strcat(buf1,buf2);
  }
  for (p=buf1, q=buf2; *p; *q++= *p++) if (*p == '%') *q++= '%';
  strcpy(q,":\n "); strcat(q,fmt);
  va_start(al,fmt);
  if (!warnonly) ohshitv(buf2,al);
  if (warncount) (*warncount)++;
  if (warnto) {
    strcat(q,"\n");
    if (vfprintf(warnto,buf2,al) == EOF)
      ohshite(_("failed to write parsing warning"));
  }
  va_end(al);
}

const struct namevalue booleaninfos[]= {  /* Note !  These must be in order ! */
  { "no",                             0,                 2 },
  { "yes",                            1,                 3 },
  {  NULL                                                  }
};

const struct namevalue priorityinfos[]= {  /* Note !  These must be in order ! */
  { "required",                       pri_required,     8 },
  { "important",                      pri_important,    9 },
  { "standard",                       pri_standard,     8 },
  { "recommended",                    pri_recommended,  11 }, /* fixme: obsolete */
  { "optional",                       pri_optional,     8 },
  { "extra",                          pri_extra,        5 },
  { "contrib",                        pri_contrib,      7 }, /* fixme: keep? */
  { "this is a bug - please report",  pri_other,        28 },
  { "unknown",                        pri_unknown,      7 },
  { "base",                           pri_required,     4 }, /* fixme: alias, remove */
  {  NULL                                                 }
};

const struct namevalue statusinfos[]= {  /* Note !  These must be in order ! */
  { "not-installed",   stat_notinstalled,    13 },
  { "unpacked",        stat_unpacked,        8 },
  { "half-configured", stat_halfconfigured,  15, },
  { "installed",       stat_installed,       9 },
  { "half-installed",  stat_halfinstalled,   14 },
  { "config-files",    stat_configfiles,     12 },
  /* These are additional entries for reading only, in any order ... */
  { "postinst-failed", stat_halfconfigured,  15 }, /* fixme: backwards compat., remove */
  { "removal-failed",  stat_halfinstalled,   14 }, /* fixme: backwards compat., remove */
  {  NULL                                       }
};

const struct namevalue eflaginfos[]= {  /* Note !  These must be in order ! */
  { "ok",                      eflagv_ok,                2 },
  { "reinstreq",               eflagv_reinstreq,         9 },
  { "hold",                    eflagv_obsoletehold,      4 },
  { "hold-reinstreq",          eflagv_obsoleteboth,      14 },
  {  NULL                                                   }
};

const struct namevalue wantinfos[]= {  /* Note !  These must be in order ! */
  { "unknown",   want_unknown,    7 },
  { "install",   want_install,    7 },
  { "hold",      want_hold,       4 },
  { "deinstall", want_deinstall,  9 },
  { "purge",     want_purge,      5 },
  {  NULL                           }
};

const char *illegal_packagename(const char *p, const char **ep) {
  static const char alsoallowed[]= "-+._"; /* _ is deprecated */
  static char buf[150];
  int c;
  
  if (!*p) return _("may not be empty string");
  if (!isalnum(*p)) return _("must start with an alphanumeric");
  while ((c= *p++)!=0)
    if (!isalnum(c) && !strchr(alsoallowed,c)) break;
  if (!c) return NULL;
  if (isspace(c) && ep) {
    while (isspace(*p)) p++;
    *ep= p; return NULL;
  }
  snprintf(buf, sizeof(buf),
          _("character `%c' not allowed - only letters, digits and %s allowed"),
          c, alsoallowed);
  return buf;
}

const struct nickname nicknames[]= {
  /* NB: capitalisation of these strings is important. */
  { "Recommended",       "Recommends"  },
  { "Optional",          "Suggests"    },
  { "Class",             "Priority"    },
  { "Package-Revision",  "Revision"    },
  { "Package_Revision",  "Revision"    },
  {  NULL                              }
};

int informativeversion(const struct versionrevision *version) {
  return (version->epoch ||
          (version->version && *version->version) ||
          (version->revision && *version->revision));
}

void varbufversion
(struct varbuf *vb,
 const struct versionrevision *version,
 enum versiondisplayepochwhen vdew) 
{
  switch (vdew) {
  case vdew_never:
    break;
  case vdew_nonambig:
    if (!version->epoch &&
        (!version->version || !strchr(version->version,':')) &&
        (!version->revision || !strchr(version->revision,':'))) break;
  case vdew_always: /* FALL THROUGH */
    varbufprintf(vb,"%lu:",version->epoch);
    break;
  default:
    internerr("bad versiondisplayepochwhen in varbufversion");
  }
  if (version->version) varbufaddstr(vb,version->version);
  if (version->revision && *version->revision) {
    varbufaddc(vb,'-');
    varbufaddstr(vb,version->revision);
  }
}

const char *versiondescribe
(const struct versionrevision *version,
 enum versiondisplayepochwhen vdew)
{
  static struct varbuf bufs[10];
  static int bufnum=0;

  struct varbuf *vb;
  
  if (!informativeversion(version)) return _("<none>");

  vb= &bufs[bufnum]; bufnum++; if (bufnum == 10) bufnum= 0;
  varbufreset(vb);
  varbufversion(vb,version,vdew);
  varbufaddc(vb,0);

  return vb->buf;
}

const char *parseversion(struct versionrevision *rversion, const char *string) {
  char *hyphen, *colon, *eepochcolon;
  const char *end, *ptr;
  unsigned long epoch;

  if (!*string) return _("version string is empty");

  /* trim leading and trailing space */
  while (*string && (*string == ' ' || *string == '\t') ) string++;
  /* string now points to the first non-whitespace char */
  end = string;
  /* find either the end of the string, or a whitespace char */
  while (*end && *end != ' ' && *end != '\t' ) end++;
  /* check for extra chars after trailing space */
  ptr = end;
  while (*ptr && ( *ptr == ' ' || *ptr == '\t' ) ) ptr++;
  if (*ptr) return _("version string has embedded spaces");

  colon= strchr(string,':');
  if (colon) {
    epoch= strtoul(string,&eepochcolon,10);
    if (colon != eepochcolon) return _("epoch in version is not number");
    if (!*++colon) return _("nothing after colon in version number");
    string= colon;
    rversion->epoch= epoch;
  } else {
    rversion->epoch= 0;
  }
  rversion->version= nfstrnsave(string,end-string);
  hyphen= strrchr(rversion->version,'-');
  if (hyphen) *hyphen++= 0;
  rversion->revision= hyphen ? hyphen : "";
  
  return NULL;
}

void parsemustfield
(FILE *file, const char *filename, int lno,
 FILE *warnto, int *warncount,
 const struct pkginfo *pigp, int warnonly,
 const char **value, const char *what) 
{
  static const char *empty = "";
  if (!*value) {
    parseerr(file,filename,lno, warnto,warncount,pigp,warnonly, _("missing %s"),what);
    *value= empty;
  } else if (!**value) {
    parseerr(file,filename,lno, warnto,warncount,pigp,warnonly,
             _("empty value for %s"),what);
  }
}

const char *skip_slash_dotslash(const char *p) {
  while (p[0] == '/' || (p[0] == '.' && p[1] == '/')) p++;
  return p;
}
