/*
 * libdpkg - Debian packaging suite library routines
 * myopt.c - my very own option parsing
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000,2002 Wichert Akkerman <wichert@deephackmode.org>
 * Copyright © 2008,2009 Guillem Jover <guillem@debian.org>
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

#include <errno.h>
#include <ctype.h>
#include <string.h>
#include <dirent.h>
#include <stdarg.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/string.h>
#include <dpkg/myopt.h>

void
badusage(const char *fmt, ...)
{
  char buf[1024];
  va_list args;

  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);

  ohshit("%s\n\n%s", buf, gettext(printforhelp));
}

static void DPKG_ATTR_NORET DPKG_ATTR_PRINTF(3)
config_error(const char *file_name, int line_num, const char *fmt, ...)
{
  char buf[1024];
  va_list args;

  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);

  ohshit(_("configuration error: %s:%d: %s"), file_name, line_num, buf);
}

void myfileopt(const char* fn, const struct cmdinfo* cmdinfos) {
  FILE* file;
  int line_num = 0;
  char linebuf[MAX_CONFIG_LINE];

  file= fopen(fn, "r");
  if (!file) {
    if (errno==ENOENT)
      return;
    warning(_("failed to open configuration file '%.255s' for reading: %s"),
            fn, strerror(errno));
    return;
  }

  while (fgets(linebuf, sizeof(linebuf), file)) {
    char* opt;
    const struct cmdinfo *cip;
    int l;

    line_num++;

    if ((linebuf[0] == '#') || (linebuf[0] == '\n') || (linebuf[0] == '\0'))
      continue;
    l=strlen(linebuf);
    if (linebuf[l - 1] == '\n')
      linebuf[l - 1] = '\0';
    for (opt=linebuf;isalnum(*opt)||*opt=='-';opt++) ;
    if (*opt == '\0')
      opt=NULL;
    else {
      *opt++ = '\0';
      if (*opt=='=') opt++;
      while (isspace(*opt)) opt++;

      opt = str_strip_quotes(opt);
      if (opt == NULL)
        config_error(fn, line_num, _("unbalanced quotes in '%s'"), linebuf);
    }

    for (cip=cmdinfos; cip->olong || cip->oshort; cip++) {
      if (!cip->olong) continue;
      if (!strcmp(cip->olong,linebuf)) break;
      l=strlen(cip->olong);
      if ((cip->takesvalue==2) && (linebuf[l]=='-') &&
	  !opt && !strncmp(linebuf,cip->olong,l)) {
	opt=linebuf+l+1;
	break;
      }
    }

    if (!cip->olong)
      config_error(fn, line_num, _("unknown option '%s'"), linebuf);

    if (cip->takesvalue) {
      if (!opt)
        config_error(fn, line_num, _("'%s' needs a value"), linebuf);
      if (cip->call) cip->call(cip,opt);
      else
        *cip->sassignto = m_strdup(opt);
    } else {
      if (opt)
        config_error(fn, line_num, _("'%s' does not take a value"), linebuf);
      if (cip->call) cip->call(cip,NULL);
      else *cip->iassignto= cip->arg;
    }
  }
  if (ferror(file)) ohshite(_("read error in configuration file `%.255s'"), fn);
  if (fclose(file)) ohshite(_("error closing configuration file `%.255s'"), fn);
}

static int
valid_config_filename(const struct dirent *dent)
{
  const char *c;

  if (dent->d_name[0] == '.')
    return 0;

  for (c = dent->d_name; *c; c++)
    if (!isalnum(*c) && *c != '_' && *c != '-')
      return 0;

  if (*c == '\0')
    return 1;
  else
    return 0;
}

static void
load_config_dir(const char *prog, const struct cmdinfo* cmdinfos)
{
  char *dirname;
  struct dirent **dlist;
  int dlist_n, i;

  dirname = m_malloc(strlen(CONFIGDIR "/.cfg.d") + strlen(prog) + 1);
  sprintf(dirname, "%s/%s.cfg.d", CONFIGDIR, prog);

  dlist_n = scandir(dirname, &dlist, valid_config_filename, alphasort);
  if (dlist_n < 0) {
    if (errno == ENOENT) {
      free(dirname);
      return;
    } else
      ohshite(_("error opening configuration directory '%s'"), dirname);
  }

  for (i = 0; i < dlist_n; i++) {
    char *filename;

    filename = m_malloc(strlen(dirname) + 1 + strlen(dlist[i]->d_name) + 1);
    sprintf(filename, "%s/%s", dirname, dlist[i]->d_name);

    myfileopt(filename, cmdinfos);

    free(dlist[i]);
    free(filename);
  }

  free(dirname);
  free(dlist);
}

void loadcfgfile(const char *prog, const struct cmdinfo* cmdinfos) {
  char *home, *file;
  int l1, l2;

  load_config_dir(prog, cmdinfos);

  l1 = strlen(CONFIGDIR "/.cfg") + strlen(prog);
  file = m_malloc(l1 + 1);
  sprintf(file, CONFIGDIR "/%s.cfg", prog);
  myfileopt(file, cmdinfos);
  if ((home = getenv("HOME")) != NULL) {
    l2 = strlen(home) + 1 + strlen("/.cfg") + strlen(prog);
    if (l2 > l1) {
      free(file);
      file = m_malloc(l2 + 1);
    }
    sprintf(file, "%s/.%s.cfg", home, prog);
    myfileopt(file, cmdinfos);
  }
  free(file);
}

void myopt(const char *const **argvp, const struct cmdinfo *cmdinfos) {
  const struct cmdinfo *cip;
  const char *p, *value;
  int l;

  ++(*argvp);
  while ((p= **argvp) && *p == '-') {
    ++(*argvp);
    if (!strcmp(p,"--")) break;
    if (*++p == '-') {
      ++p; value=NULL;
      for (cip= cmdinfos;
           cip->olong || cip->oshort;
           cip++) {
        if (!cip->olong) continue;
        if (!strcmp(p,cip->olong)) break;
        l= strlen(cip->olong);
        if (!strncmp(p,cip->olong,l) &&
            (p[l]== ((cip->takesvalue==2) ? '-' : '='))) { value=p+l+1; break; }
      }
      if (!cip->olong) badusage(_("unknown option --%s"),p);
      if (cip->takesvalue) {
        if (!value) {
          value= *(*argvp)++;
          if (!value) badusage(_("--%s option takes a value"),cip->olong);
        }
        if (cip->call) cip->call(cip,value);
        else *cip->sassignto= value;
      } else {
        if (value) badusage(_("--%s option does not take a value"),cip->olong);
        if (cip->call) cip->call(cip,NULL);
        else *cip->iassignto= cip->arg;
      }
    } else {
      while (*p) {
        for (cip= cmdinfos; (cip->olong || cip->oshort) && *p != cip->oshort; cip++);
        if (!cip->oshort) badusage(_("unknown option -%c"),*p);
        p++;
        if (cip->takesvalue) {
          if (!*p) {
            value= *(*argvp)++;
            if (!value) badusage(_("-%c option takes a value"),cip->oshort);
          } else {
            value= p; p="";
            if (*value == '=') value++;
          }
          if (cip->call) cip->call(cip,value);
          else *cip->sassignto= value;
        } else {
          if (*p == '=') badusage(_("-%c option does not take a value"),cip->oshort);
          if (cip->call) cip->call(cip,NULL);
          else *cip->iassignto= cip->arg;
        }
      }
    }
  }
}

void
setobsolete(const struct cmdinfo *cip, const char *value)
{
  warning(_("obsolete option '--%s'\n"), cip->olong);
}

const struct cmdinfo *cipaction = NULL;

/* XXX: This function is a hack. */
static inline int
option_short(int c)
{
  return c ? c : '\b';
}

void
setaction(const struct cmdinfo *cip, const char *value)
{
  if (cipaction)
    badusage(_("conflicting actions -%c (--%s) and -%c (--%s)"),
             option_short(cip->oshort), cip->olong,
             option_short(cipaction->oshort), cipaction->olong);
  cipaction = cip;
}
