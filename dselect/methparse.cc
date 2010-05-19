/*
 * dselect - Debian package maintenance user interface
 * methparse.cc - access method list parsing
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
#include <sys/wait.h>

#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <ctype.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

#include "dselect.h"
#include "bindings.h"
#include "method.h"

int noptions=0;
struct dselect_option *options=0, *coption=0;
struct method *methods=0;

static void DPKG_ATTR_NORET
badmethod(const char *pathname, const char *why)
{
  ohshit(_("syntax error in method options file `%.250s' -- %s"), pathname, why);
}

static void DPKG_ATTR_NORET
eofmethod(const char *pathname, FILE *f, const char *why)
{
  if (ferror(f)) ohshite(_("error reading options file `%.250s'"),pathname);
  badmethod(pathname,why);
}

void readmethods(const char *pathbase, dselect_option **optionspp, int *nread) {
  static const char *const methodprograms[]= {
    METHODSETUPSCRIPT, METHODUPDATESCRIPT, METHODINSTALLSCRIPT, 0
  };
  const char *const *ccpp;
  int methodlen, c, baselen;
  char *pathinmeth, *pathbuf, *pathmeth;
  DIR *dir;
  FILE *names, *descfile;
  struct dirent *dent;
  struct varbuf vb;
  method *meth;
  dselect_option *opt;
  struct stat stab;

  baselen= strlen(pathbase);
  pathbuf= new char[baselen+IMETHODMAXLEN+IOPTIONMAXLEN+sizeof(OPTIONSDESCPFX)+10];
  strcpy(pathbuf,pathbase);
  strcpy(pathbuf+baselen,"/");
  pathmeth= pathbuf+baselen+1;

  dir= opendir(pathbuf);
  if (!dir) {
    if (errno == ENOENT) {
      delete[] pathbuf;
      return;
    }
    ohshite(_("unable to read `%.250s' directory for reading methods"),pathbuf);
  }

  if (debug) fprintf(debug,"readmethods(`%s',...) directory open\n", pathbase);
  
  while ((dent= readdir(dir)) != 0) {
    c= dent->d_name[0];
    if (debug) fprintf(debug,"readmethods(`%s',...) considering `%s' ...\n",
                       pathbase,dent->d_name);
    if (c != '_' && !isalpha(c)) continue;
    char *p = dent->d_name + 1;
    while ((c = *p) != 0 && isalnum(c) && c != '_')
      p++;
    if (c) continue;
    methodlen= strlen(dent->d_name);
    if (methodlen > IMETHODMAXLEN)
      ohshit(_("method `%.250s' has name that is too long (%d > %d characters)"),
             dent->d_name, methodlen, IMETHODMAXLEN);
    /* Check if there is a localized version of this method */
    
    strcpy(pathmeth, dent->d_name);
    strcpy(pathmeth+methodlen, "/");
    pathinmeth= pathmeth+methodlen+1;

    for (ccpp= methodprograms; *ccpp; ccpp++) {
      strcpy(pathinmeth,*ccpp);
      if (access(pathbuf,R_OK|X_OK))
        ohshite(_("unable to access method script `%.250s'"),pathbuf);
    }
    if (debug) fprintf(debug," readmethods(`%s',...) scripts ok\n", pathbase);

    strcpy(pathinmeth,METHODOPTIONSFILE);
    names= fopen(pathbuf,"r");
    if (!names) ohshite(_("unable to read method options file `%.250s'"),pathbuf);

    meth= new method;
    meth->name= new char[strlen(dent->d_name)+1];
    strcpy(meth->name,dent->d_name);
    meth->path= new char[baselen+1+methodlen+2+50];
    strncpy(meth->path,pathbuf,baselen+1+methodlen);
    strcpy(meth->path+baselen+1+methodlen,"/");
    meth->pathinmeth= meth->path+baselen+1+methodlen+1;
    meth->next= methods;
    meth->back= 0;
    if (methods) methods->back= meth;
    methods= meth;
    if (debug) fprintf(debug," readmethods(`%s',...) new method"
                       " name=`%s' path=`%s' pathinmeth=`%s'\n",
                       pathbase, meth->name, meth->path, meth->pathinmeth);
    
    while ((c= fgetc(names)) != EOF) {
      if (isspace(c)) continue;
      opt= new dselect_option;
      opt->meth= meth;
      vb.reset();
      do {
        if (!isdigit(c)) badmethod(pathbuf,_("non-digit where digit wanted"));
        vb(c);
        c= fgetc(names);
        if (c == EOF) eofmethod(pathbuf,names,_("EOF in index string"));
      } while (!isspace(c));
      if (strlen(vb.string()) > OPTIONINDEXMAXLEN)
        badmethod(pathbuf,_("index string too long"));
      strcpy(opt->index,vb.string());
      do {
        if (c == '\n') badmethod(pathbuf,_("newline before option name start"));
        c= fgetc(names);
        if (c == EOF) eofmethod(pathbuf,names,_("EOF before option name start"));
      } while (isspace(c));
      vb.reset();
      if (!isalpha(c) && c != '_')
        badmethod(pathbuf,_("nonalpha where option name start wanted"));
      do {
        if (!isalnum(c) && c != '_') badmethod(pathbuf,_("non-alphanum in option name"));
        vb(c);
        c= fgetc(names);
        if (c == EOF) eofmethod(pathbuf,names,_("EOF in option name"));
      } while (!isspace(c));
      opt->name= new char[strlen(vb.string())+1];
      strcpy(opt->name,vb.string());
      do {
        if (c == '\n') badmethod(pathbuf,_("newline before summary"));
        c= fgetc(names);
        if (c == EOF) eofmethod(pathbuf,names,_("EOF before summary"));
      } while (isspace(c));
      vb.reset();
      do {
        vb(c);
        c= fgetc(names);
        if (c == EOF) eofmethod(pathbuf,names,_("EOF in summary - missing newline"));
      } while (c != '\n');
      opt->summary= new char[strlen(vb.string())+1];
      strcpy(opt->summary,vb.string());
      
      strcpy(pathinmeth,OPTIONSDESCPFX);
      strcpy(pathinmeth+sizeof(OPTIONSDESCPFX)-1,opt->name);
      descfile= fopen(pathbuf,"r");
      if (!descfile) {
        if (errno != ENOENT)
          ohshite(_("unable to open option description file `%.250s'"),pathbuf);
        opt->description= 0;
      } else { /* descfile != 0 */
        if (fstat(fileno(descfile),&stab))
          ohshite(_("unable to stat option description file `%.250s'"),pathbuf);
        opt->description= new char[stab.st_size+1];  errno=0;
        unsigned long filelen= stab.st_size;
        if (fread(opt->description,1,stab.st_size+1,descfile) != filelen)
          ohshite(_("failed to read option description file `%.250s'"),pathbuf);
        opt->description[stab.st_size]= 0;
        if (ferror(descfile))
          ohshite(_("error during read of option description file `%.250s'"),pathbuf);
        fclose(descfile);
      }
      strcpy(pathinmeth,METHODOPTIONSFILE);
      
      if (debug) fprintf(debug," readmethods(`%s',...) new option"
                         " index=`%s' name=`%s' summary=`%.20s'"
                         " strlen(description=%s)=%ld"
                         " method name=`%s' path=`%s' pathinmeth=`%s'\n",
                         pathbase,
                         opt->index, opt->name, opt->summary,
                         opt->description ? "`...'" : "null",
                         opt->description ? (long) strlen(opt->description) : -1,
                         opt->meth->name, opt->meth->path, opt->meth->pathinmeth);

      dselect_option **optinsert = optionspp;
      while (*optinsert && strcmp(opt->index, (*optinsert)->index) > 0)
        optinsert = &(*optinsert)->next;
      opt->next= *optinsert;
      *optinsert= opt;
      (*nread)++;
    }
    if (ferror(names))
      ohshite(_("error during read of method options file `%.250s'"),pathbuf);
    fclose(names);
  }
  closedir(dir);
  if (debug) fprintf(debug,"readmethods(`%s',...) done\n", pathbase);
  delete[] pathbuf;
}

static char *methoptfile= 0;

void getcurrentopt() {
  char methoptbuf[IMETHODMAXLEN+1+IOPTIONMAXLEN+2];
  FILE *cmo;
  int l;
  int admindirlen;
  char *p;
  
  if (!methoptfile) {
    admindirlen= strlen(admindir);
    methoptfile= new char[admindirlen + sizeof(CMETHOPTFILE) + 2];
    strcpy(methoptfile,admindir);
    strcpy(methoptfile+admindirlen, "/" CMETHOPTFILE);
  }

  coption= 0;
  cmo= fopen(methoptfile,"r");
  if (!cmo) {
    if (errno == ENOENT) return;
    ohshite(_("unable to open current option file `%.250s'"),methoptfile);
  }
  if (debug) fprintf(debug,"getcurrentopt() cmethopt open\n");
  if (!fgets(methoptbuf,sizeof(methoptbuf),cmo)) { fclose(cmo); return; }
  if (fgetc(cmo) != EOF) { fclose(cmo); return; }
  if (!feof(cmo)) { fclose(cmo); return; }
  if (debug) fprintf(debug,"getcurrentopt() cmethopt eof\n");
  fclose(cmo);
  if (debug) fprintf(debug,"getcurrentopt() cmethopt read\n");
  l= strlen(methoptbuf);  if (!l || methoptbuf[l-1] != '\n') return;
  methoptbuf[--l]= 0;
  if (debug) fprintf(debug,"getcurrentopt() cmethopt len and newline\n");
  p= strchr(methoptbuf,' ');  if (!p) return;
  if (debug) fprintf(debug,"getcurrentopt() cmethopt space\n");
  *p++= 0;
  if (debug) fprintf(debug,"getcurrentopt() cmethopt meth name `%s'\n", methoptbuf);
  method *meth = methods;
  while (meth && strcmp(methoptbuf, meth->name))
    meth = meth->next;
  if (!meth) return;
  if (debug) fprintf(debug,"getcurrentopt() cmethopt meth found; opt `%s'\n",p);
  dselect_option *opt = options;
  while (opt && (opt->meth != meth || strcmp(p, opt->name)))
    opt = opt->next;
  if (!opt) return;
  if (debug) fprintf(debug,"getcurrentopt() cmethopt opt found\n");
  coption= opt;
}

void writecurrentopt() {
  FILE *cmo;
  int l;
  static char *newfile=0;

  assert(methoptfile);
  if (!newfile) {
    l= strlen(methoptfile);
    newfile= new char[l + sizeof(NEWDBEXT) + 1];
    strcpy(newfile,methoptfile);
    strcpy(newfile+l, NEWDBEXT);
  }
  cmo= fopen(newfile,"w");
  if (!cmo) ohshite(_("unable to open new option file `%.250s'"),newfile);
  if (fprintf(cmo,"%s %s\n",coption->meth->name,coption->name) == EOF) {
    fclose(cmo);
    ohshite(_("unable to write new option to `%.250s'"),newfile);
  }
  if (fclose(cmo))
    ohshite(_("unable to close new option file `%.250s'"),newfile);
  if (rename(newfile,methoptfile))
    ohshite(_("unable to install new option as `%.250s'"),methoptfile);
}
