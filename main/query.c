/*
 * dpkg - main program for package management
 * enquiry.c - status enquiry and listing options
 *
 * Copyright (C) 1995,1996 Ian Jackson <ijackson@gnu.ai.mit.edu>
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

/* fixme: per-package audit */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fnmatch.h>
#include <assert.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/termios.h>
#include <fcntl.h>

#include <config.h>
#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

#include "filesdb.h"
#include "main.h"

void ensure_package_clientdata(struct pkginfo *pkg) {
  if (pkg->clientdata) return;
  pkg->clientdata= nfmalloc(sizeof(struct perpackagestate));
  pkg->clientdata->istobe= itb_normal;
  pkg->clientdata->fileslistvalid= 0;
  pkg->clientdata->files= 0;
}

const char *pkgadminfile(struct pkginfo *pkg, const char *whichfile) {
  static struct varbuf vb;
  varbufreset(&vb);
  varbufaddstr(&vb,admindir);
  varbufaddstr(&vb,"/" INFODIR);
  varbufaddstr(&vb,pkg->name);
  varbufaddc(&vb,'.');
  varbufaddstr(&vb,whichfile);
  varbufaddc(&vb,0);
  return vb.buf;
}

void cu_closepipe(int argc, void **argv) {
  int *p1= (int*)argv[0];
  close(p1[0]); close(p1[1]);
}

void cu_closefile(int argc, void **argv) {
  FILE *f= (FILE*)(argv[0]);
  fclose(f);
}

void cu_closefd(int argc, void **argv) {
  int ip= *(int*)argv;
  close(ip);
}

int pkglistqsortcmp(const void *a, const void *b) {
  const struct pkginfo *pa= *(const struct pkginfo**)a;
  const struct pkginfo *pb= *(const struct pkginfo**)b;
  return strcmp(pa->name,pb->name);
}

static void limiteddescription(struct pkginfo *pkg, int maxl,
                               const char **pdesc_r, int *l_r) {
  const char *pdesc, *p;
  int l;
  
  pdesc= pkg->installed.valid ? pkg->installed.description : 0;
  if (!pdesc) pdesc= _("(no description available)");
  p= strchr(pdesc,'\n');
  if (!p) p= pdesc+strlen(pdesc);
  l= (p - pdesc > maxl) ? maxl : (int)(p - pdesc);
  *pdesc_r=pdesc; *l_r=l;
}

static int getwidth() {
  int fd;
  int res;
  struct winsize ws;
  const char* columns;

  if ((columns=getenv("COLUMNS")) && ((res=atoi(columns))>0))
    ws.ws_col=res;
  else if (!isatty(1))
    ws.ws_col=80;
  else {
    if ((fd=open("/dev/tty",O_RDONLY))!=-1) {
      if (ioctl(fd, TIOCGWINSZ, &ws)==-1)
        ws.ws_col=80;
      close(fd);
    }
  }
  return ws.ws_col;
}

static void list1package(struct pkginfo *pkg, int *head) {
  int l,w;
  static int nw,vw,dw;
  const char *pdesc;
  static char format[80]   = "";
    
  if (format[0]==0) {
    w=getwidth()-80;	/* get spare width */
    if (w<0) w=0;		/* lets not try to deal with terminals that are too small */
    w>>=2;		/* halve that so we can add that to the both the name and description */
    nw=(14+w);		/* name width */
    vw=(14+w);		/* version width */
    dw=(44+(2*w));	/* description width */
    sprintf(format,"%%c%%c%%c %%-%d.%ds %%-%d.%ds %%.*s\n", nw, nw, vw, vw);
  }

  if (!*head) {
    fputs(_("\
Desired=Unknown/Install/Remove/Purge/Hold\n\
| Status=Not/Installed/Config-files/Unpacked/Failed-config/Half-installed\n\
|/ Err?=(none)/Hold/Reinst-required/X=both-problems (Status,Err: uppercase=bad)\n"), stdout);
    printf(format,'|','|','/', _("Name"), _("Version"), 40, _("Description"));
    printf("+++-");					/* status */
    for (l=0;l<nw;l++) printf("="); printf("-");	/* packagename */
    for (l=0;l<vw;l++) printf("="); printf("-");	/* version */
    for (l=0;l<dw;l++) printf("="); 			/* description */
    printf("\n");
    *head= 1;
  }
  if (!pkg->installed.valid) blankpackageperfile(&pkg->installed);
  limiteddescription(pkg,dw,&pdesc,&l);
  printf(format,
         "uihrp"[pkg->want],
         "nUFiHc"[pkg->status],
         " R?#"[pkg->eflag],
         pkg->name,
         versiondescribe(&pkg->installed.version,vdew_never),
         l, pdesc);
}         

void listpackages(const char *const *argv) {
  struct pkgiterator *it;
  struct pkginfo *pkg;
  struct pkginfo **pkgl;
  const char *thisarg;
  int np, i, head, found;

  modstatdb_init(admindir,msdbrw_readonly);

  np= countpackages();
  pkgl= m_malloc(sizeof(struct pkginfo*)*np);
  it= iterpkgstart(); i=0;
  while ((pkg= iterpkgnext(it))) {
    assert(i<np);
    pkgl[i++]= pkg;
  }
  iterpkgend(it);
  assert(i==np);

  qsort(pkgl,np,sizeof(struct pkginfo*),pkglistqsortcmp);
  head=0;
  
  if (!*argv) {
    for (i=0; i<np; i++) {
      pkg= pkgl[i];
      if (pkg->status == stat_notinstalled) continue;
      list1package(pkg,&head);
    }
  } else {
    while ((thisarg= *argv++)) {
      found= 0;
      for (i=0; i<np; i++) {
        pkg= pkgl[i];
        if (fnmatch(thisarg,pkg->name,0)) continue;
        list1package(pkg,&head); found++;
      }
      if (!found) {
        fprintf(stderr,_("No packages found matching %s.\n"),thisarg);
	nerrs++;
      }
    }
  }
  if (ferror(stdout)) werr("stdout");
  if (ferror(stderr)) werr("stderr");  
}

static int searchoutput(struct filenamenode *namenode) {
  int found, i;
  struct filepackages *packageslump;

  if (namenode->divert) {
    for (i=0; i<2; i++) {
      if (namenode->divert->pkg) printf(_("diversion by %s"),namenode->divert->pkg->name);
      else printf(_("local diversion"));
      printf(" %s: %s\n", i ? _("to") : _("from"),
             i ?
             (namenode->divert->useinstead
              ? namenode->divert->useinstead->name
              : namenode->name)
             :
             (namenode->divert->camefrom
              ? namenode->divert->camefrom->name
              : namenode->name));
    }
  }
  found= 0;
  for (packageslump= namenode->packages;
       packageslump;
       packageslump= packageslump->more) {
    for (i=0; i < PERFILEPACKAGESLUMP && packageslump->pkgs[i]; i++) {
      if (found) fputs(", ",stdout);
      fputs(packageslump->pkgs[i]->name,stdout);
      found++;
    }
  }
  if (found) printf(": %s\n",namenode->name);
  return found + (namenode->divert ? 1 : 0);
}

void searchfiles(const char *const *argv) {
  struct filenamenode *namenode;
  struct fileiterator *it;
  const char *thisarg;
  int found;
  static struct varbuf vb;
  
  if (!*argv)
    badusage(_("--search needs at least one file name pattern argument"));

  modstatdb_init(admindir,msdbrw_readonly|msdbrw_noavail);
  ensure_allinstfiles_available_quiet();
  ensure_diversions();

  while ((thisarg= *argv++) != 0) {
    found= 0;
    if (!strchr("*[?/",*thisarg)) {
      varbufreset(&vb);
      varbufaddc(&vb,'*');
      varbufaddstr(&vb,thisarg);
      varbufaddc(&vb,'*');
      varbufaddc(&vb,0);
      thisarg= vb.buf;
    }
    if (strcspn(thisarg,"*[?\\") == strlen(thisarg)) {
      namenode= findnamenode(thisarg, 0);
      found += searchoutput(namenode);
    } else {
      it= iterfilestart();
      while ((namenode= iterfilenext(it)) != 0) {
        if (fnmatch(thisarg,namenode->name,0)) continue;
        found+= searchoutput(namenode);
      }
      iterfileend(it);
    }
    if (!found) {
      fprintf(stderr,_("dpkg: %s not found.\n"),thisarg);
      nerrs++;
      if (ferror(stderr)) werr("stderr");
    } else {
      if (ferror(stdout)) werr("stdout");
    }
  }
}

void enqperpackage(const char *const *argv) {
  int failures;
  const char *thisarg;
  struct fileinlist *file;
  struct pkginfo *pkg;
  struct filenamenode *namenode;
  
  if (!*argv)
    badusage(_("--%s needs at least one package name argument"), cipaction->olong);

  failures= 0;
  if (cipaction->arg==act_listfiles)
    modstatdb_init(admindir,msdbrw_readonly|msdbrw_noavail);
  else 
    modstatdb_init(admindir,msdbrw_readonly);

  while ((thisarg= *argv++) != 0) {
    pkg= findpackage(thisarg);

    switch (cipaction->arg) {
      
    case act_status:
      if (pkg->status == stat_notinstalled &&
          pkg->priority == pri_unknown &&
          !(pkg->section && *pkg->section) &&
          !pkg->files &&
          pkg->want == want_unknown &&
          !informative(pkg,&pkg->installed)) {
        fprintf(stderr,_("Package `%s' is not installed and no info is available.\n"),pkg->name);
        failures++;
      } else {
        writerecord(stdout, "<stdout>", pkg, &pkg->installed);
      }
      break;

    case act_printavail:
      if (!informative(pkg,&pkg->available)) {
        fprintf(stderr,_("Package `%s' is not available.\n"),pkg->name);
        failures++;
      } else {
        writerecord(stdout, "<stdout>", pkg, &pkg->available);
      }
      break;
      
    case act_listfiles:
      switch (pkg->status) {
      case stat_notinstalled: 
        fprintf(stderr,_("Package `%s' is not installed.\n"),pkg->name);
        failures++;
        break;
        
      default:
        ensure_packagefiles_available(pkg);
        ensure_diversions();
        file= pkg->clientdata->files;
        if (!file) {
          printf(_("Package `%s' does not contain any files (!)\n"),pkg->name);
        } else {
          while (file) {
            namenode= file->namenode;
            puts(namenode->name);
            if (namenode->divert && !namenode->divert->camefrom) {
              if (!namenode->divert->pkg) printf(_("locally diverted"));
              else if (pkg == namenode->divert->pkg) printf(_("package diverts others"));
              else printf(_("diverted by %s"),namenode->divert->pkg->name);
              printf(_(" to: %s\n"),namenode->divert->useinstead->name);
            }
            file= file->next;
          }
        }
        break;
      }
      break;

    default:
      internerr("unknown action");
    }
        
    putchar('\n');
    if (ferror(stdout)) werr("stdout");
  }

  if (failures) {
    nerrs++;
    fputs(_("Use dpkg --info (= dpkg-deb --info) to examine archive files,\n"
         "and dpkg --contents (= dpkg-deb --contents) to list their contents.\n"),stderr);
    if (ferror(stdout)) werr("stdout");
  }
}

static void printversion(void) {
  if (fputs(_("Debian GNU/Linux `"), stdout) < 0) werr("stdout");
  if (fputs(DPKG, stdout) < 0) werr("stdout");
  if (fputs(_("' package management program version "), stdout) < 0) werr("stdout");
//  if (fputs( DPKG_VERSION_ARCH ".\n", stdout) < 0) werr("stdout");
  if (fputs(_( "This is free software; see the GNU General Public Licence version 2 or\n"
		"later for copying conditions.  There is NO warranty.\n"
		"See dpkg --licence for copyright and license details.\n"),
		 stdout) < 0) werr("stdout");
}
/*
   options that need fixing:
  dpkg --yet-to-unpack                 \n\
  */
static void usage(void) {
  if (fprintf (stdout, _("\
Usage: \n\
  dpkg -s|--status <package-name> ...      display package status details\n\
  dpkg -p|--print-avail <package-name> ... display available version details\n\
  dpkg -L|--listfiles <package-name> ...   list files `owned' by package(s)\n\
  dpkg -l|--list [<pattern> ...]           list packages concisely\n\
  dpkg -S|--search <pattern> ...           find package(s) owning file(s)\n\
  dpkg --help | --version                  show this help / version number\n\
  dpkg --licence                           print copyright licensing terms\n\
\n\
Options:\n\
  --admindir=<directory>     Use <directory> instead of %s\n\
  -D|--debug=<octal>         Enable debugging - see -Dhelp or --debug=help\n"),
	    ADMINDIR) < 0) werr ("stdout");
}

const char thisname[]= "dpkg";
const char printforhelp[]= N_("\
Type dpkg-query --help for help about installing and deinstalling packages [*];\n\
Use dselect for user-friendly package management;\n\
Type dpkg-query --licence for copyright licence and lack of warranty (GNU GPL) [*].\n\
\n");

const struct cmdinfo *cipaction= 0;
int f_pending=0, f_recursive=0, f_alsoselect=1, f_skipsame=0, f_noact=0;
int f_autodeconf=0, f_nodebsig=0;
unsigned long f_debug=0;
/* Change fc_overwrite to 1 to enable force-overwrite by default */
int fc_hold=0;
int fc_conflicts=0, fc_depends=0;
int fc_badpath=0;

int errabort = 50;
const char *admindir= ADMINDIR;
const char *instdir= "";
struct packageinlist *ignoredependss=0;

static void helponly(const struct cmdinfo *cip, const char *value) NONRETURNING;
static void helponly(const struct cmdinfo *cip, const char *value) {
  usage(); exit(0);
}
static void versiononly(const struct cmdinfo *cip, const char *value) NONRETURNING;
static void versiononly(const struct cmdinfo *cip, const char *value) {
  printversion(); exit(0);
}

static void setaction(const struct cmdinfo *cip, const char *value) {
  if (cipaction)
    badusage(_("conflicting actions --%s and --%s"),cip->olong,cipaction->olong);
  cipaction= cip;
}

static const struct cmdinfo cmdinfos[]= {
  /* This table has both the action entries in it and the normal options.
   * The action entries are made with the ACTION macro, as they all
   * have a very similar structure.
   */
#define ACTION(longopt,shortopt,code,function) \
 { longopt, shortopt, 0,0,0, setaction, code, 0, (voidfnp)function }
#define OBSOLETE(longopt,shortopt) \
 { longopt, shortopt, 0,0,0, setobsolete, 0, 0, 0 }

  ACTION( "listfiles",                      'L', act_listfiles,     enqperpackage   ),		//
  ACTION( "status",                         's', act_status,               enqperpackage   ),	//
  ACTION( "print-avail",                    'p', act_printavail,           enqperpackage   ),	//
  ACTION( "list",                           'l', act_listpackages,         listpackages    ),	//
  ACTION( "search",                         'S', act_searchfiles,          searchfiles     ),	//

  { "admindir",           0,   1,  0, &admindir,       0                             },
  { "help",              'h',  0,  0, 0,               helponly                      },
  { "version",            0,   0,  0, 0,               versiononly                   },
  { "licence",/* UK spelling */ 0,0,0,0,               showcopyright                 },
  { "license",/* US spelling */ 0,0,0,0,               showcopyright                 },
  {  0,                   0                                                          }
};

int main(int argc, const char *const *argv) {
  jmp_buf ejbuf;
  static void (*actionfunction)(const char *const *argv);

  setlocale(LC_ALL, "");
  setlocale(LC_CTYPE, "C");
  bindtextdomain(PACKAGE, LOCALEDIR);
  textdomain(PACKAGE);

  if (setjmp(ejbuf)) { /* expect warning about possible clobbering of argv */
    error_unwind(ehflag_bombout); exit(2);
  }
  push_error_handler(&ejbuf,print_error_fatal,0);

  umask(022); /* Make sure all our status databases are readable. */
 
  myopt(&argv,cmdinfos);
  if (!cipaction) badusage(_("need an action option"));

  setvbuf(stdout,0,_IONBF,0);
  filesdbinit();

  actionfunction= (void (*)(const char* const*))cipaction->farg;

  actionfunction(argv);

  set_error_display(0,0);
  error_unwind(ehflag_normaltidy);

  return reportbroken_retexitstatus();
}
