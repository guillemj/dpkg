/*
 * dpkg - main program for package management
 * enquiry.c - status enquiry and listing options
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

/* fixme: per-package audit */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fnmatch.h>
#include <assert.h>
#include <unistd.h>

#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
#include "myopt.h"

#include "filesdb.h"
#include "main.h"

static int listqcmp(const void *a, const void *b) {
  struct pkginfo *pa= *(struct pkginfo**)a;
  struct pkginfo *pb= *(struct pkginfo**)b;
  return strcmp(pa->name,pb->name);
}

static void limiteddescription(struct pkginfo *pkg, int maxl,
                               const char **pdesc_r, int *l_r) {
  const char *pdesc, *p;
  int l;
  
  pdesc= pkg->installed.valid ? pkg->installed.description : 0;
  if (!pdesc) pdesc= "(no description available)";
  p= strchr(pdesc,'\n');
  if (!p) p= pdesc+strlen(pdesc);
  l= (p - pdesc > maxl) ? maxl : (int)(p - pdesc);
  *pdesc_r=pdesc; *l_r=l;
}

static void list1package(struct pkginfo *pkg, int *head) {
  int l;
  const char *pdesc;
    
  if (!*head) {
    fputs("\
Desired=Unknown/Install/Remove/Purge\n\
| Status=Not/Installed/Config-files/Unpacked/Failed-config/Half-installed\n\
|/ Err?=(none)/Hold/Reinst-required/X=both-problems (Status,Err: uppercase=bad)\n\
||/ Name            Version        Description\n\
+++-===============-==============-============================================\n",
          stdout);
    *head= 1;
  }
  
  if (!pkg->installed.valid) blankpackageperfile(&pkg->installed);
  limiteddescription(pkg,44,&pdesc,&l);
  printf("%c%c%c %-15.15s %-14.14s %.*s\n",
         "uirp"[pkg->want],
         "nUFiHc"[pkg->status],
         " hRX"[pkg->eflag],
         pkg->name,
         versiondescribe(pkg->installed.version,pkg->installed.revision),
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

  qsort(pkgl,np,sizeof(struct pkginfo*),listqcmp);
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
      if (!found)
        fprintf(stderr,"No packages found matching %s.\n",thisarg);
    }
  }
  if (ferror(stdout)) werr("stdout");
  if (ferror(stderr)) werr("stderr");  
}

struct badstatinfo {
  int (*yesno)(struct pkginfo*, const struct badstatinfo *bsi);
  int val;
  const char *explanation;
};

static int bsyn_reinstreq(struct pkginfo *pkg, const struct badstatinfo *bsi) {
  return pkg->eflag &= eflagf_reinstreq;
}

static int bsyn_status(struct pkginfo *pkg, const struct badstatinfo *bsi) {
  if (pkg->eflag &= eflagf_reinstreq) return 0;
  return pkg->status == bsi->val;
}

static const struct badstatinfo badstatinfos[]= {
  {
    bsyn_reinstreq, 0,
    "The following packages are in a mess due to serious problems during\n"
    "installation.  They must be reinstalled for them (and any packages\n"
    "that depend on them) to function properly:\n"
  }, {
    bsyn_status, stat_unpacked,
    "The following packages have been unpacked but not yet configured.\n"
    "They must be configured using " DPKG " --configure or the configure\n"
    "menu option in " DSELECT " for them to work:\n"
  }, {
    bsyn_status, stat_halfconfigured,
    "The following packages are only half configured, probably due to problems\n"
    "configuring them the first time.  The configuration should be retried using\n"
    DPKG " --configure <package> or the configure menu option in " DSELECT ":\n"
  }, {
    bsyn_status, stat_halfinstalled,
    "The following packages are only half installed, due to problems during\n"
    "installation.  The installation can probably be completed by retrying it;\n"
    "the packages can be removed using " DSELECT " or " DPKG " --remove:\n"
  }, {
    0
  }
};

static void describebriefly(struct pkginfo *pkg) {
  int maxl, l;
  const char *pdesc;

  maxl= 57;
  l= strlen(pkg->name);
  if (l>20) maxl -= (l-20);
  limiteddescription(pkg,maxl,&pdesc,&l);
  printf(" %-20s %.*s\n",pkg->name,l,pdesc);
}

void audit(const char *const *argv) {
  struct pkgiterator *it;
  struct pkginfo *pkg;
  const struct badstatinfo *bsi;
  int head;

  if (*argv) badusage("--audit does not take any arguments");

  modstatdb_init(admindir,msdbrw_readonly);

  for (bsi= badstatinfos; bsi->yesno; bsi++) {
    head= 0;
    it= iterpkgstart(); 
    while ((pkg= iterpkgnext(it))) {
      if (!bsi->yesno(pkg,bsi)) continue;
      if (!head) {
        fputs(bsi->explanation,stdout);
        head= 1;
      }
      describebriefly(pkg);
    }
    iterpkgend(it);
    if (head) putchar('\n');
  }
  if (ferror(stderr)) werr("stderr");  
}

struct sectionentry {
  struct sectionentry *next;
  const char *name;
  int count;
};

static int yettobeunpacked(struct pkginfo *pkg, const char **thissect) {
  if (pkg->want != want_install) return 0;

  switch (pkg->status) {
  case stat_unpacked: case stat_installed: case stat_halfconfigured:
    return 0;
  case stat_notinstalled: case stat_halfinstalled: case stat_configfiles:
    if (thissect)
      *thissect= pkg->section && *pkg->section ? pkg->section : "<unknown>";
    return 1;
  default:
    internerr("unknown status checking for unpackedness");
  }
}

void unpackchk(const char *const *argv) {
  int totalcount, sects;
  struct sectionentry *sectionentries, *se, **sep;
  struct pkgiterator *it;
  struct pkginfo *pkg;
  const char *thissect;
  char buf[20];
  int width;
  
  if (*argv) badusage("--yet-to-unpack does not take any arguments");

  modstatdb_init(admindir,msdbrw_readonly);

  totalcount= 0;
  sectionentries= 0;
  sects= 0;
  it= iterpkgstart(); 
  while ((pkg= iterpkgnext(it))) {
    if (!yettobeunpacked(pkg, &thissect)) continue;
    for (se= sectionentries; se && strcasecmp(thissect,se->name); se= se->next);
    if (!se) {
      se= nfmalloc(sizeof(struct sectionentry));
      for (sep= &sectionentries;
           *sep && strcasecmp(thissect,(*sep)->name) > 0;
           sep= &(*sep)->next);
      se->name= thissect;
      se->count= 0;
      se->next= *sep;
      *sep= se;
      sects++;
    }
    se->count++; totalcount++;
  }
  iterpkgend(it);

  if (totalcount == 0) exit(0);
  
  if (totalcount <= 12) {
    it= iterpkgstart(); 
    while ((pkg= iterpkgnext(it))) {
      if (!yettobeunpacked(pkg,0)) continue;
      describebriefly(pkg);
    }
    iterpkgend(it);
  } else if (sects <= 12) {
    for (se= sectionentries; se; se= se->next) {
      sprintf(buf,"%d",se->count);
      printf(" %d in %s: ",se->count,se->name);
      width= 70-strlen(se->name)-strlen(buf);
      while (width > 59) { putchar(' '); width--; }
      it= iterpkgstart(); 
      while ((pkg= iterpkgnext(it))) {
        if (!yettobeunpacked(pkg,&thissect)) continue;
        if (strcasecmp(thissect,se->name)) continue;
        width -= strlen(pkg->name); width--;
        if (width < 4) { printf(" ..."); break; }
        printf(" %s",pkg->name);
      }
      iterpkgend(it);
      putchar('\n');
    }
  } else {
    printf(" %d packages, from the following sections:",totalcount);
    width= 0;
    for (se= sectionentries; se; se= se->next) {
      sprintf(buf,"%d",se->count);
      width -= (6 + strlen(se->name) + strlen(buf));
      if (width < 0) { putchar('\n'); width= 73 - strlen(se->name) - strlen(buf); }
      printf("   %s (%d)",se->name,se->count);
    }
    putchar('\n');
  }
  fflush(stdout);
  if (ferror(stdout)) werr("stdout");
}

static int searchoutput(struct filenamenode *namenode) {
  int found, i;
  struct filepackages *packageslump;

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
  return found;
}

void searchfiles(const char *const *argv) {
  struct filenamenode *namenode;
  struct fileiterator *it;
  const char *thisarg;
  int found;
  static struct varbuf vb;
  
  if (!*argv)
    badusage("--search needs at least one file name pattern argument");

  modstatdb_init(admindir,msdbrw_readonly);
  ensure_allinstfiles_available_quiet();

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
      namenode= findnamenode(thisarg);
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
      fprintf(stderr,DPKG ": %s not found.\n",thisarg);
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
  
  if (!*argv)
    badusage("--%s needs at least one package name argument", cipaction->olong);

  failures= 0;
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
          !informativeperfile(&pkg->installed)) {
        printf("Package `%s' is not installed and no info is available.\n",pkg->name);
        failures++;
      } else {
        writerecord(stdout, "<stdout>", pkg, &pkg->installed);
      }
      break;

    case act_listfiles:
      switch (pkg->status) {
      case stat_notinstalled: 
        printf("Package `%s' is not installed.\n",pkg->name);
        failures++;
        break;
        
      default:
        ensure_packagefiles_available(pkg);
        file= pkg->clientdata->files;
        if (!file) {
          printf("Package `%s' does not contain any files (!)\n",pkg->name);
        } else {
          while (file) {
            puts(file->namenode->name);
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
    puts("Use " DPKG " --info (= " BACKEND " --info) to examine archive files,\n"
         "and " DPKG " --contents (= " BACKEND " --contents) to list their contents.");
    if (ferror(stdout)) werr("stdout");
  }
}

void assertsupportpredepends(const char *const *argv) {
  struct pkginfo *pkg;
  
  if (*argv) badusage("--assert-support-predepends does not take any arguments");

  modstatdb_init(admindir,msdbrw_readonly);
  pkg= findpackage("dpkg");

  switch (pkg->status) {
  case stat_installed:
    break;
  case stat_unpacked: case stat_halfconfigured:
    if (versionsatisfied5(pkg->configversion,pkg->configrevision,
                          "1.1.0","", dvr_laterequal))
      break;
    printf("Version of dpkg with Pre-Depends support not yet configured.\n"
           " Please use `dpkg --configure dpkg', and then try again.\n");
    exit(1);
  default:
    printf("dpkg not recorded as installed, cannot check for Pre-Depends support !\n");
    exit(1);
  }
}

void predeppackage(const char *const *argv) {
  /* Print a single package which:
   *  (a) is the target of one or more relevant predependencies.
   *  (b) has itself no unsatisfied pre-dependencies.
   * If such a package is present output is the Packages file entry,
   *  which can be massaged as appropriate.
   * Exit status:
   *  0 = a package printed, OK
   *  1 = no suitable package available
   *  2 = error
   */
  static struct varbuf vb;
  
  struct pkgiterator *it;
  struct pkginfo *pkg, *startpkg, *trypkg;
  struct dependency *dep;
  struct deppossi *possi, *provider;

  if (*argv) badusage("--predep-package does not take any argument");

  modstatdb_init(admindir,msdbrw_readonly);
  clear_istobes(); /* We use clientdata->istobe to detect loops */

  for (it=iterpkgstart(), dep=0;
       !dep && (pkg=iterpkgnext(it));
       ) {
    if (pkg->want != want_install) continue; /* Ignore packages user doesn't want */
    if (!pkg->files) continue; /* Ignore packages not available */
    pkg->clientdata->istobe= itb_preinstall;
    for (dep= pkg->available.depends; dep; dep= dep->next) {
      if (dep->type != dep_predepends) continue;
      if (depisok(dep,&vb,0,1)) continue;
      break; /* This will leave dep non-NULL, and so exit the loop. */
    }
    pkg->clientdata->istobe= itb_normal;
    /* If dep is NULL we go and get the next package. */
  }
  if (!dep) exit(1); /* Not found */
  assert(pkg);
  startpkg= pkg;
  pkg->clientdata->istobe= itb_preinstall;

  /* OK, we have found an unsatisfied predependency.
   * Now go and find the first thing we need to install, as a first step
   * towards satisfying it.
   */
  do {
    /* We search for a package which would satisfy dep, and put it in pkg */
    for (possi=dep->list, pkg=0;
         !pkg && possi;
         possi=possi->next) {
      trypkg= possi->ed;
      if (!trypkg->available.valid) continue;
      if (trypkg->files && versionsatisfied(&trypkg->available,possi)) {
        if (trypkg->clientdata->istobe == itb_normal) { pkg= trypkg; break; }
      }
      if (possi->verrel != dvr_none) continue;
      for (provider=possi->ed->available.depended;
           !pkg && provider;
           provider=provider->next) {
        if (provider->up->type != dep_provides) continue;
        trypkg= provider->up->up;
        if (!trypkg->available.valid || !trypkg->files) continue;
        if (trypkg->clientdata->istobe == itb_normal) { pkg= trypkg; break; }
      }
    }
    if (!pkg) {
      varbufreset(&vb);
      describedepcon(&vb,dep);
      varbufaddc(&vb,0);
      fprintf(stderr, DPKG ": cannot see how to satisfy pre-dependency:\n %s\n",vb.buf);
      ohshit("cannot satisfy pre-dependencies for %.250s (wanted due to %.250s)",
             dep->up->name,startpkg->name);
    }
    pkg->clientdata->istobe= itb_preinstall;
    for (dep= pkg->available.depends; dep; dep= dep->next) {
      if (dep->type != dep_predepends) continue;
      if (depisok(dep,&vb,0,1)) continue;
      break; /* This will leave dep non-NULL, and so exit the loop. */
    }
  } while (dep);

  /* OK, we've found it - pkg has no unsatisfied pre-dependencies ! */
  writerecord(stdout,"<stdout>",pkg,&pkg->available);
  if (fflush(stdout)) werr("stdout");
}

static void badlgccfn(const char *compiler, const char *output, const char *why)
     NONRETURNING;
static void badlgccfn(const char *compiler, const char *output, const char *why) {
  fprintf(stderr,
          DPKG ": unexpected output from `%s --print-libgcc-file-name':\n"
          " `%s'\n",
          compiler,output);
  ohshit("compiler libgcc filename not understood: %.250s",why);
}

void printarchitecture(const char *const *argv) {
  static const struct { const char *from, *to; } archtable[]= {
#include "archtable.inc"
    { 0,0 }
  }, *archp;
                  
  const char *ccompiler, *arch;
  int p1[2], c;
  pid_t c1;
  FILE *ccpipe;
  struct varbuf vb;
  ptrdiff_t ll;
  char *p, *q;

  ccompiler= getenv("CC");
  if (!ccompiler) ccompiler= "gcc";
  varbufinit(&vb);
  m_pipe(p1);
  ccpipe= fdopen(p1[0],"r"); if (!ccpipe) ohshite("failed to fdopen CC pipe");
  if (!(c1= m_fork())) {
    m_dup2(p1[1],1); close(p1[0]); close(p1[1]);
    execlp(ccompiler,ccompiler,"--print-libgcc-file-name",(char*)0);
    ohshite("failed to exec C compiler `%.250s'",ccompiler);
  }
  close(p1[1]);
  while ((c= getc(ccpipe)) != EOF) varbufaddc(&vb,c);
  if (ferror(ccpipe)) ohshite("error reading from CC pipe");
  waitsubproc(c1,"gcc --print-libgcc-file-name",0);
  if (!vb.used) badlgccfn(ccompiler,"","empty output");
  varbufaddc(&vb,0);
  if (vb.buf[vb.used-2] != '\n') badlgccfn(ccompiler,vb.buf,"no newline");
  vb.used-= 2; varbufaddc(&vb,0);
  p= strstr(vb.buf,"/gcc-lib/");
  if (!p) badlgccfn(ccompiler,vb.buf,"no gcc-lib component");
  p+= 9;
  q= strchr(p,'-'); if (!q) badlgccfn(ccompiler,vb.buf,"no hyphen after gcc-lib");
  ll= q-p;
  for (archp=archtable;
       archp->from && !(strlen(archp->from) == ll && !strncmp(archp->from,p,ll));
       archp++);
  arch= archp->to;
  if (!arch) {
    *q= 0; arch= p;
    fprintf(stderr,DPKG ": warning, architecture `%s' not in remapping table\n",arch);
  }
  if (printf("%s\n",arch) == EOF) werr("stdout");
  if (fflush(stdout)) werr("stdout");
}
