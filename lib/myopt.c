/*
 * libdpkg - Debian packaging suite library routines
 * myopt.c - my very own option parsing
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2000,2002 Wichert Akkerman <wichert@deephackmode.org>
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
 * License along with this file; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */
#include <config.h>

#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <stdlib.h>

#include <myopt.h>
#include <dpkg.h>

void myfileopt(const char* fn, const struct cmdinfo* cmdinfos) {
  FILE* file;
  char linebuf[MAXDIVERTFILENAME];

  file= fopen(fn, "r");
  if (!file) {
    if (errno==ENOENT)
      return;
    warningf(_("failed to open configuration file `%.255s' for reading"),fn);
    return;
  }

  while (fgets(linebuf, sizeof(linebuf), file)) {
    char* opt;
    const struct cmdinfo *cip;
    int l;

    if ((linebuf[0]=='#') || (linebuf[0]=='\n') || (linebuf[0]==0)) continue;
    l=strlen(linebuf);
    if (linebuf[l-1]=='\n') linebuf[l-1]=0;
    for (opt=linebuf;isalnum(*opt)||*opt=='-';opt++) ;
    if (*opt==0)
      opt=NULL;
    else {
      *opt++=0;
      if (*opt=='=') opt++;
      while (isspace(*opt)) opt++;
    }

    for (cip=cmdinfos; cip->olong || cip->oshort; cip++) {
      int l;
      if (!cip->olong) continue;
      if (!strcmp(cip->olong,linebuf)) break;
      l=strlen(cip->olong);
      if ((cip->takesvalue==2) && (linebuf[l]=='-') &&
	  !opt && !strncmp(linebuf,cip->olong,l)) {
	opt=linebuf+l+1;
	break;
      }
    }

    if (!cip->olong) ohshite(_("configuration error: unknown option %s"), linebuf);

    if (cip->takesvalue) {
      if (!opt) ohshite(_("configuration error: %s needs a value"), linebuf);
      if (cip->call) cip->call(cip,opt);
      else *cip->sassignto= strdup(opt);
    } else {
      if (opt) ohshite(_("configuration error: %s does not take a value"), linebuf);
      if (cip->call) cip->call(cip,NULL);
      else *cip->iassignto= cip->arg;
    }
  }
  if (ferror(file)) ohshite(_("read error in configuration file `%.255s'"), fn);
  if (fclose(file)) ohshite(_("error closing configuration file `%.255s'"), fn);
}

void loadcfgfile(const char *prog, const struct cmdinfo* cmdinfos) {
  char *home, *file;
  int l1, l2;
  l1 = strlen(CONFIGDIR "/.cfg") + strlen(prog);
  file = malloc(l1 + 1);
  if (file==NULL) ohshite(_("Error allocating memory for cfgfilename"));
  sprintf(file, CONFIGDIR "/%s.cfg", prog);
  myfileopt(file, cmdinfos);
  if ((home = getenv("HOME")) != NULL) {
    l2 = strlen(home) + 1 + strlen("/.cfg") + strlen(prog);
    if (l2 > l1) {
      free(file);
      file = malloc(l2 + 1);
      if (file==NULL) ohshite(_("Error allocating memory for cfgfilename"));
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
