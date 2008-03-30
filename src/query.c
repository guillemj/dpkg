/*
 * dpkg-query - program for query the dpkg database
 * query.c - status enquiry and listing options
 *
 * dpkg - main program for package management
 * enquiry.c - status enquiry and listing options
 *
 * Copyright (C) 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 200,2001 Wichert Akkerman <wakkerma@debian.org>
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

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

#include "filesdb.h"
#include "main.h"

static const char* showformat		= "${Package}\t${Version}\n";


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

static int getwidth(void) {
  int fd;
  int res;
  struct winsize ws;
  const char* columns;

  if ((columns=getenv("COLUMNS")) && ((res=atoi(columns))>0))
    return res;
  else if (!isatty(1))
    return -1;
  else {
    if ((fd=open("/dev/tty",O_RDONLY))!=-1) {
      if (ioctl(fd, TIOCGWINSZ, &ws)==-1)
	ws.ws_col=80;
      close(fd);
    }
    return ws.ws_col;
  }
}

static void list1package(struct pkginfo *pkg, int *head,
			 struct pkginfo **pkgl, int np) {
  int i,l,w;
  static int nw,vw,dw;
  const char *pdesc;
  static char format[80]   = "";
    
  if (format[0]==0) {
    w=getwidth();
    if (w == -1) {
      nw=14, vw=14, dw=44;
      for (i=0; i<np; i++) {
	const char *pdesc;
	int plen, vlen, dlen;

	pdesc= pkg->installed.valid ? pkg->installed.description : 0;
	if (!pdesc) pdesc= _("(no description available)");

	plen= strlen(pkgl[i]->name);
	vlen = strlen(versiondescribe(&pkgl[i]->installed.version, vdew_nonambig));
	dlen= strcspn(pdesc, "\n");
	if (plen > nw) nw = plen;
	if (vlen > vw) vw = vlen;
	if (dlen > dw) dw = dlen;
      }
    } else {
      w-=80;
      if (w<0) w=0;		/* lets not try to deal with terminals that are too small */
      w>>=2;		/* halve that so we can add that to the both the name and description */
      nw=(14+w);		/* name width */
      vw=(14+w);		/* version width */
      dw=(44+(2*w));	/* description width */
    }
    sprintf(format,"%%c%%c%%c %%-%d.%ds %%-%d.%ds %%.*s\n", nw, nw, vw, vw);
  }

  if (!*head) {
    fputs(_("\
Desired=Unknown/Install/Remove/Purge/Hold\n\
| Status=Not/Inst/Cfg-files/Unpacked/Failed-cfg/Half-inst/trig-aWait/Trig-pend\n\
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
         "ncHUFWti"[pkg->status],
         " R?#"[pkg->eflag],
         pkg->name,
         versiondescribe(&pkg->installed.version, vdew_nonambig),
         l, pdesc);
}

void listpackages(const char *const *argv) {
  struct pkgiterator *it;
  struct pkginfo *pkg;
  struct pkginfo **pkgl;
  int np, i, head;

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

  qsort(pkgl, np, sizeof(struct pkginfo*), pkglistqsortcmp);
  head = 0;

  if (!*argv) {
    for (i=0; i<np; i++) {
      pkg= pkgl[i];
      if (pkg->status == stat_notinstalled) continue;
      list1package(pkg, &head, pkgl, np);
    }
  } else {
    int argc, ip, *found;

    for (argc = 0; argv[argc]; argc++);
    found = m_malloc(sizeof(int) * argc);
    memset(found, 0, sizeof(int) * argc);

    for (i = 0; i < np; i++) {
      pkg = pkgl[i];
      for (ip = 0; ip < argc; ip++) {
        if (!fnmatch(argv[ip], pkg->name, 0)) {
          list1package(pkg, &head, pkgl, np);
          found[ip]++;
          break;
        }
      }
    }

    /* FIXME: we might get non-matching messages for sub-patterns specified
     * after their super-patterns, due to us skipping on first match. */
    for (ip = 0; ip < argc; ip++) {
      if (!found[ip]) {
        fprintf(stderr, _("No packages found matching %s.\n"), argv[ip]);
        nerrs++;
      }
    }
  }

  if (ferror(stdout)) werr("stdout");
  if (ferror(stderr)) werr("stderr");  
  modstatdb_shutdown();
}

static int searchoutput(struct filenamenode *namenode) {
  int found, i;
  struct filepackages *packageslump;

  if (namenode->divert) {
    const char *name_from = namenode->divert->camefrom ?
                            namenode->divert->camefrom->name : namenode->name;
    const char *name_to = namenode->divert->useinstead ?
                          namenode->divert->useinstead->name : namenode->name;

    if (namenode->divert->pkg) {
      printf(_("diversion by %s from: %s\n"),
             namenode->divert->pkg->name, name_from);
      printf(_("diversion by %s to: %s\n"),
             namenode->divert->pkg->name, name_to);
    } else {
      printf(_("local diversion from: %s\n"), name_from);
      printf(_("local diversion to: %s\n"), name_to);
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
  modstatdb_shutdown();
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
              if (!namenode->divert->pkg)
		printf(_("locally diverted to: %s\n"),
		       namenode->divert->useinstead->name);
              else if (pkg == namenode->divert->pkg)
		printf(_("package diverts others to: %s\n"),
		       namenode->divert->useinstead->name);
              else
		printf(_("diverted by %s to: %s\n"),
		       namenode->divert->pkg->name,
		       namenode->divert->useinstead->name);
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

    if (*(argv + 1) == 0)
      putchar('\n');
    if (ferror(stdout)) werr("stdout");
  }

  if (failures) {
    nerrs++;
    fputs(_("Use dpkg --info (= dpkg-deb --info) to examine archive files,\n"
         "and dpkg --contents (= dpkg-deb --contents) to list their contents.\n"),stderr);
    if (ferror(stdout)) werr("stdout");
  }
  modstatdb_shutdown();
}

void showpackages(const char *const *argv) {
  struct pkgiterator *it;
  struct pkginfo *pkg;
  struct pkginfo **pkgl;
  int np, i;
  struct lstitem* fmt = parseformat(showformat);

  if (!fmt) {
    nerrs++;
    return;
  }

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
  
  if (!*argv) {
    for (i=0; i<np; i++) {
      pkg= pkgl[i];
      if (pkg->status == stat_notinstalled) continue;
      show1package(fmt,pkg);
    }
  } else {
    int argc, ip, *found;

    for (argc = 0; argv[argc]; argc++);
    found = m_malloc(sizeof(int) * argc);
    memset(found, 0, sizeof(int) * argc);

    for (i = 0; i < np; i++) {
      pkg = pkgl[i];
      for (ip = 0; ip < argc; ip++) {
        if (!fnmatch(argv[ip], pkg->name, 0)) {
          show1package(fmt, pkg);
          found[ip]++;
          break;
        }
      }
    }

    /* FIXME: we might get non-matching messages for sub-patterns specified
     * after their super-patterns, due to us skipping on first match. */
    for (ip = 0; ip < argc; ip++) {
      if (!found[ip]) {
        fprintf(stderr, _("No packages found matching %s.\n"), argv[ip]);
        nerrs++;
      }
    }
  }

  if (ferror(stdout)) werr("stdout");
  if (ferror(stderr)) werr("stderr");  
  freeformat(fmt);
  modstatdb_shutdown();
}

void
printversion(void)
{
  if (printf(_("Debian `%s' package management program query tool\n"),
	     DPKGQUERY) < 0) werr("stdout");
  if (printf(_("This is free software; see the GNU General Public License version 2 or\n"
	       "later for copying conditions. There is NO warranty.\n"
	       "See %s --license for copyright and license details.\n"),
	     DPKGQUERY) < 0) werr("stdout");
}
/*
   options that need fixing:
  dpkg --yet-to-unpack                 \n\
  */
void
usage(void)
{
  if (printf(_(
"Usage: %s [<option> ...] <command>\n"
"\n"), DPKGQUERY) < 0) werr ("stdout");

  if (printf(_(
"Commands:\n"
"  -s|--status <package> ...        Display package status details.\n"
"  -p|--print-avail <package> ...   Display available version details.\n"
"  -L|--listfiles <package> ...     List files `owned' by package(s).\n"
"  -l|--list [<pattern> ...]        List packages concisely.\n"
"  -W|--show <pattern> ...          Show information on package(s).\n"
"  -S|--search <pattern> ...        Find package(s) owning file(s).\n"
"\n")) < 0) werr ("stdout");

  if (printf(_(
"  -h|--help                        Show this help message.\n"
"  --version                        Show the version.\n"
"  --license|--licence              Show the copyright licensing terms.\n"
"\n")) < 0) werr ("stdout");

  if (printf(_(
"Options:\n"
"  --admindir=<directory>           Use <directory> instead of %s.\n"
"  -f|--showformat=<format>         Use alternative format for --show.\n"
"\n"), ADMINDIR) < 0) werr ("stdout");

  if (printf(_(
"Format syntax:\n"
"  A format is a string that will be output for each package. The format\n"
"  can include the standard escape sequences \\n (newline), \\r (carriage\n"
"  return) or \\\\ (plain backslash). Package information can be included\n"
"  by inserting variable references to package fields using the ${var[;width]}\n"
"  syntax. Fields will be right-aligned unless the width is negative in which\n"
"  case left alignment will be used.\n")) < 0) werr ("stdout");
}

const char thisname[]= "dpkg-query";
const char printforhelp[]= N_("\
Use --help for help about querying packages;\n\
Use --license for copyright license and lack of warranty (GNU GPL).\n\
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

static void setaction(const struct cmdinfo *cip, const char *value) {
  if (cipaction)
    badusage(_("conflicting actions -%c (--%s) and -%c (--%s)"),
             cip->oshort, cip->olong, cipaction->oshort, cipaction->olong);
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

  ACTION( "listfiles",                      'L', act_listfiles,     enqperpackage   ),
  ACTION( "status",                         's', act_status,        enqperpackage   ),
  ACTION( "print-avail",                    'p', act_printavail,    enqperpackage   ),
  ACTION( "list",                           'l', act_listpackages,  listpackages    ),
  ACTION( "search",                         'S', act_searchfiles,   searchfiles     ),
  ACTION( "show",                           'W', act_listpackages,  showpackages    ),

  { "admindir",           0,   1,  0, &admindir,       0                            },
  { "showformat",        'f',  1,  0, &showformat,     0                            },
  { "help",              'h',  0,  0, 0,               helponly                     },
  { "version",            0,   0,  0, 0,               versiononly                  },
  { "licence",/* UK spelling */ 0,0,0,0,               showcopyright                },
  { "license",/* US spelling */ 0,0,0,0,               showcopyright                },
  {  0,                   0                                                         }
};

int main(int argc, const char *const *argv) {
  jmp_buf ejbuf;
  static void (*actionfunction)(const char *const *argv);

  standard_startup(&ejbuf, argc, &argv, NULL, 0, cmdinfos);
  if (!cipaction) badusage(_("need an action option"));

  setvbuf(stdout,0,_IONBF,0);
  filesdbinit();

  actionfunction= (void (*)(const char* const*))cipaction->farg;

  actionfunction(argv);

  standard_shutdown(0);

  return reportbroken_retexitstatus();
}
