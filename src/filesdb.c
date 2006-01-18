/*
 * dpkg - main program for package management
 * filesdb.c - management of database of files installed on system
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2000,2001 Wichert Akkerman <wakkerma@debian.org>
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

#include <assert.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>

#include <pwd.h>
#include <grp.h>
#include <sys/types.h>

#include <dpkg.h>
#include <dpkg-db.h>

#include "filesdb.h"
#include "main.h"

/*** Generic data structures and routines ***/

static int allpackagesdone= 0;
static int nfiles= 0;
static struct diversion *diversions= 0;
static FILE *diversionsfile= 0;
static FILE *statoverridefile= 0;

void note_must_reread_files_inpackage(struct pkginfo *pkg) {
  allpackagesdone= 0;
  ensure_package_clientdata(pkg);
  pkg->clientdata->fileslistvalid= 0;
}

static int saidread=0;

 /* load the list of files in this package into memory, or update the
  * list if it is there but stale
  */
void ensure_packagefiles_available(struct pkginfo *pkg) {
  int fd;
  const char *filelistfile;
  struct fileinlist **lendp, *newent, *current;
  struct filepackages *packageslump;
  int search, findlast, putat;
  struct stat stat_buf;
  char *loaded_list, *loaded_list_end, *thisline, *nextline, *ptr;

  if (pkg->clientdata && pkg->clientdata->fileslistvalid) return;
  ensure_package_clientdata(pkg);

  /* Throw away any the stale data, if there was any. */
  for (current= pkg->clientdata->files;
       current;
       current= current->next) {
    /* For each file that used to be in the package,
     * go through looking for this package's entry in the list
     * of packages containing this file, and blank it out.
     */
    for (packageslump= current->namenode->packages;
         packageslump;
         packageslump= packageslump->more)
      for (search= 0;
           search < PERFILEPACKAGESLUMP && packageslump->pkgs[search];
           search++)
        if (packageslump->pkgs[search] == pkg) {
          /* Hah!  Found it. */
          for (findlast= search+1;
               findlast < PERFILEPACKAGESLUMP && packageslump->pkgs[findlast];
               findlast++);
          findlast--;
          /* findlast is now the last occupied entry, which may be the same as
           * search.  We blank out the entry for this package.  We also
           * have to copy the last entry into the empty slot, because
           * the list is null-pointer-terminated.
           */
          packageslump->pkgs[search]= packageslump->pkgs[findlast];
          packageslump->pkgs[findlast]= 0;
          /* This may result in an empty link in the list.  This is OK. */
          goto xit_search_to_delete_from_perfilenodelist;
        }
  xit_search_to_delete_from_perfilenodelist:
    ;
    /* The actual filelist links were allocated using nfmalloc, so
     * we shouldn't free them.
     */
  }
  pkg->clientdata->files= 0;

  /* Packages which aren't installed don't have a files list. */
  if (pkg->status == stat_notinstalled) {
    pkg->clientdata->fileslistvalid= 1; return;
  }

  filelistfile= pkgadminfile(pkg,LISTFILE);

  onerr_abort++;
  
  fd= open(filelistfile,O_RDONLY);

  if (fd==-1) {
    if (errno != ENOENT)
      ohshite(_("unable to open files list file for package `%.250s'"),pkg->name);
    onerr_abort--;
    if (pkg->status != stat_configfiles) {
      if (saidread == 1) putc('\n',stderr);
      fprintf(stderr,
              _("dpkg: serious warning: files list file for package `%.250s' missing,"
              " assuming package has no files currently installed.\n"), pkg->name);
    }
    pkg->clientdata->files= 0;
    pkg->clientdata->fileslistvalid= 1;
    return;
  }

  push_cleanup(cu_closefd,ehflag_bombout, 0,0, 1,&fd);
  
   if(fstat(fd, &stat_buf))
     ohshite("unable to stat files list file for package `%.250s'",pkg->name);

   if (stat_buf.st_size) {
     loaded_list = nfmalloc(stat_buf.st_size);
     loaded_list_end = loaded_list + stat_buf.st_size;
  
    fd_buf_copy(fd, loaded_list, stat_buf.st_size, _("files list for package `%.250s'"), pkg->name);
  
    lendp= &pkg->clientdata->files;
    thisline = loaded_list;
    while (thisline < loaded_list_end) {
      if (!(ptr = memchr(thisline, '\n', loaded_list_end - thisline))) 
        ohshit("files list file for package `%.250s' is missing final newline",pkg->name);
      /* where to start next time around */
      nextline = ptr + 1;
      /* strip trailing "/" */
      if (ptr > thisline && ptr[-1] == '/') ptr--;
      /* add the file to the list */
      if (ptr == thisline)
        ohshit(_("files list file for package `%.250s' contains empty filename"),pkg->name);
      *ptr = 0;
      newent= nfmalloc(sizeof(struct fileinlist));
      newent->namenode= findnamenode(thisline, fnn_nocopy);
      newent->next= 0;
      *lendp= newent;
      lendp= &newent->next;
      thisline = nextline;
    }
  }
  pop_cleanup(ehflag_normaltidy); /* fd= open() */
  if (close(fd))
    ohshite(_("error closing files list file for package `%.250s'"),pkg->name);

  onerr_abort--;

  for (newent= pkg->clientdata->files; newent; newent= newent->next) {
    packageslump= newent->namenode->packages;
    putat= 0;
    if (packageslump) {
      for (; putat < PERFILEPACKAGESLUMP && packageslump->pkgs[putat];
           putat++);
      if (putat >= PERFILEPACKAGESLUMP) packageslump= 0;
    }
    if (!packageslump) {
      packageslump= nfmalloc(sizeof(struct filepackages));
      packageslump->more= newent->namenode->packages;
      newent->namenode->packages= packageslump;
      putat= 0;
    }
    packageslump->pkgs[putat]= pkg;
    if (++putat < PERFILEPACKAGESLUMP) packageslump->pkgs[putat]= 0;
  }      
  pkg->clientdata->fileslistvalid= 1;
}

void ensure_allinstfiles_available(void) {
  struct pkgiterator *it;
  struct pkginfo *pkg;
    
  if (allpackagesdone) return;
  if (saidread<2) {
    saidread=1;
    printf(_("(Reading database ... "));
  }
  it= iterpkgstart();
  while ((pkg= iterpkgnext(it)) != 0) ensure_packagefiles_available(pkg);
  iterpkgend(it);
  allpackagesdone= 1;

  if (saidread==1) {
    printf(_("%d files and directories currently installed.)\n"),nfiles);
    saidread=2;
  }
}

void ensure_allinstfiles_available_quiet(void) {
  saidread=2;
  ensure_allinstfiles_available();
}

void write_filelist_except(struct pkginfo *pkg, struct fileinlist *list, int leaveout) {
  /* If leaveout is nonzero, will not write any file whose filenamenode
   * has the fnnf_elide_other_lists flag set.
   */
  static struct varbuf vb, newvb;
  FILE *file;

  varbufreset(&vb);
  varbufaddstr(&vb,admindir);
  varbufaddstr(&vb,"/" INFODIR);
  varbufaddstr(&vb,pkg->name);
  varbufaddstr(&vb,"." LISTFILE);
  varbufaddc(&vb,0);

  varbufreset(&newvb);
  varbufaddstr(&newvb,vb.buf);
  varbufaddstr(&newvb,NEWDBEXT);
  varbufaddc(&newvb,0);
  
  file= fopen(newvb.buf,"w+");
  if (!file)
    ohshite(_("unable to create updated files list file for package %s"),pkg->name);
  push_cleanup(cu_closefile,ehflag_bombout, 0,0, 1,(void*)file);
  while (list) {
    if (!(leaveout && (list->namenode->flags & fnnf_elide_other_lists))) {
      fputs(list->namenode->name,file);
      putc('\n',file);
    }
    list= list->next;
  }
  if (ferror(file))
    ohshite(_("failed to write to updated files list file for package %s"),pkg->name);
  if (fflush(file))
    ohshite(_("failed to flush updated files list file for package %s"),pkg->name);
  if (fsync(fileno(file)))
    ohshite(_("failed to sync updated files list file for package %s"),pkg->name);
  pop_cleanup(ehflag_normaltidy); /* file= fopen() */
  if (fclose(file))
    ohshite(_("failed to close updated files list file for package %s"),pkg->name);
  if (rename(newvb.buf,vb.buf))
    ohshite(_("failed to install updated files list file for package %s"),pkg->name);

  note_must_reread_files_inpackage(pkg);
}

void reversefilelist_init(struct reversefilelistiter *iterptr,
                          struct fileinlist *files) {
  /* Initialises an iterator that appears to go through the file
   * list `files' in reverse order, returning the namenode from
   * each.  What actually happens is that we walk the list here,
   * building up a reverse list, and then peel it apart one
   * entry at a time.
   */
  struct fileinlist *newent;
  
  iterptr->todo= 0;
  while (files) {
    newent= m_malloc(sizeof(struct fileinlist));
    newent->namenode= files->namenode;
    newent->next= iterptr->todo;
    iterptr->todo= newent;
    files= files->next;
  }
}

struct filenamenode *reversefilelist_next(struct reversefilelistiter *iterptr) {
  struct filenamenode *ret;
  struct fileinlist *todo;

  todo= iterptr->todo;
  if (!todo) return 0;
  ret= todo->namenode;
  iterptr->todo= todo->next;
  free(todo);
  return ret;
}

void reversefilelist_abort(struct reversefilelistiter *iterptr) {
  /* Clients must call this function to clean up the reversefilelistiter
   * if they wish to break out of the iteration before it is all done.
   * Calling this function is not necessary if reversefilelist_next has
   * been called until it returned 0.
   */
  while (reversefilelist_next(iterptr));
}

void ensure_statoverrides(void) {
  static struct varbuf vb;

  struct stat stab1, stab2;
  FILE *file;
  char *loaded_list, *loaded_list_end, *thisline, *nextline, *ptr;
  struct filestatoverride *fso;
  struct filenamenode *fnn;

  varbufreset(&vb);
  varbufaddstr(&vb,admindir);
  varbufaddstr(&vb,"/" STATOVERRIDEFILE);
  varbufaddc(&vb,0);

  onerr_abort++;

  file= fopen(vb.buf,"r");
  if (!file) {
    if (errno != ENOENT) ohshite(_("failed to open statoverride file"));
    if (!statoverridefile) { onerr_abort--; return; }
  } else {
    if (fstat(fileno(file),&stab2))
      ohshite(_("failed to fstat statoverride file"));
    if (statoverridefile) {
      if (fstat(fileno(statoverridefile),&stab1))
	ohshite(_("failed to fstat previous statoverride file"));
      if (stab1.st_dev == stab2.st_dev && stab1.st_ino == stab2.st_ino) {
	fclose(file); onerr_abort--; return;
      }
    }
  }
  if (statoverridefile) fclose(statoverridefile);
  statoverridefile= file;
  setcloexec(fileno(statoverridefile), vb.buf);

  /* If the statoverride list is empty we don't need to bother reading it. */
  if (!stab2.st_size) {
    onerr_abort--;
    return;
  }

  loaded_list = nfmalloc(stab2.st_size);
  loaded_list_end = loaded_list + stab2.st_size;

  fd_buf_copy(fileno(file), loaded_list, stab2.st_size, _("statoverride file `%.250s'"), vb.buf);

  thisline = loaded_list;
  while (thisline<loaded_list_end) {
    char* endptr;

    fso= nfmalloc(sizeof(struct filestatoverride));

    if (!(ptr = memchr(thisline, '\n', loaded_list_end - thisline))) 
      ohshit("statoverride file is missing final newline");
    /* where to start next time around */
    nextline = ptr + 1;
    if (ptr == thisline)
      ohshit(_("statoverride file contains empty line"));
    *ptr = 0;

    /* Extract the uid */
    if (!(ptr=memchr(thisline, ' ', nextline-thisline)))
      ohshit("syntax error in statoverride file ");
    *ptr=0;
    if (thisline[0]=='#') {
      fso->uid=strtol(thisline + 1, &endptr, 10);
      if (*endptr!=0)
	ohshit("syntax error: invalid uid in statoverride file ");
    } else {
      struct passwd* pw = getpwnam(thisline);
      if (pw==NULL)
	ohshit("syntax error: unknown user `%s' in statoverride file ", thisline);
      fso->uid=pw->pw_uid;
    }

    /* Move to the next bit */
    thisline=ptr+1;
    if (thisline>=loaded_list_end)
      ohshit("unexpected end of line in statoverride file");

    /* Extract the gid */
    if (!(ptr=memchr(thisline, ' ', nextline-thisline)))
      ohshit("syntax error in statoverride file ");
    *ptr=0;
    if (thisline[0]=='#') {
      fso->gid=strtol(thisline + 1, &endptr, 10);
      if (*endptr!=0)
	ohshit("syntax error: invalid gid in statoverride file ");
    } else {
      struct group* gr = getgrnam(thisline);
      if (gr==NULL)
	ohshit("syntax error: unknown group `%s' in statoverride file ", thisline);
      fso->gid=gr->gr_gid;
    }

    /* Move to the next bit */
    thisline=ptr+1;
    if (thisline>=loaded_list_end)
      ohshit("unexecpted end of line in statoverride file");

    /* Extract the mode */
    if (!(ptr=memchr(thisline, ' ', nextline-thisline)))
      ohshit("syntax error in statoverride file ");
    *ptr=0;
    fso->mode=strtol(thisline, &endptr, 8);
    if (*endptr!=0)
      ohshit("syntax error: invalid mode in statoverride file ");

    /* Move to the next bit */
    thisline=ptr+1;
    if (thisline>=loaded_list_end)
      ohshit("unexecpted end of line in statoverride file");

    fnn= findnamenode(thisline, 0);
    if (fnn->statoverride)
      ohshit("multiple statusoverides present for file `%.250s'", thisline);
    fnn->statoverride=fso;
    /* Moving on.. */
    thisline=nextline;
  }

  onerr_abort--;
}

void ensure_diversions(void) {
  static struct varbuf vb;

  struct stat stab1, stab2;
  char linebuf[MAXDIVERTFILENAME];
  FILE *file;
  struct diversion *ov, *oicontest, *oialtname;
  int l;
  
  varbufreset(&vb);
  varbufaddstr(&vb,admindir);
  varbufaddstr(&vb,"/" DIVERSIONSFILE);
  varbufaddc(&vb,0);

  onerr_abort++;
  
  file= fopen(vb.buf,"r");
  if (!file) {
    if (errno != ENOENT) ohshite(_("failed to open diversions file"));
    if (!diversionsfile) { onerr_abort--; return; }
  } else if (diversionsfile) {
    if (fstat(fileno(diversionsfile),&stab1))
      ohshite(_("failed to fstat previous diversions file"));
    if (fstat(fileno(file),&stab2))
      ohshite(_("failed to fstat diversions file"));
    if (stab1.st_dev == stab2.st_dev && stab1.st_ino == stab2.st_ino) {
      fclose(file); onerr_abort--; return;
    }
  }
  if (diversionsfile) fclose(diversionsfile);
  diversionsfile= file;
  setcloexec(fileno(diversionsfile), vb.buf);

  for (ov= diversions; ov; ov= ov->next) {
    ov->useinstead->divert->camefrom->divert= 0;
    ov->useinstead->divert= 0;
  }
  diversions= 0;
  if (!file) { onerr_abort--; return; }

  while (fgets(linebuf,sizeof(linebuf),file)) {
    oicontest= nfmalloc(sizeof(struct diversion));
    oialtname= nfmalloc(sizeof(struct diversion));

    l= strlen(linebuf);
    if (l == 0) ohshit(_("fgets gave an empty string from diversions [i]"));
    if (linebuf[--l] != '\n') ohshit(_("diversions file has too-long line or EOF [i]"));
    linebuf[l]= 0;
    oialtname->camefrom= findnamenode(linebuf, 0);
    oialtname->useinstead= 0;    

    if (!fgets(linebuf,sizeof(linebuf),file)) {
      if (ferror(file)) ohshite(_("read error in diversions [ii]"));
      else ohshit(_("unexpected EOF in diversions [ii]"));
    } 
    l= strlen(linebuf);
    if (l == 0) ohshit(_("fgets gave an empty string from diversions [ii]"));
    if (linebuf[--l] != '\n') ohshit(_("diversions file has too-long line or EOF [ii]"));
    linebuf[l]= 0;
    oicontest->useinstead= findnamenode(linebuf, 0);
    oicontest->camefrom= 0;
    
    if (!fgets(linebuf,sizeof(linebuf),file)) {
      if (ferror(file)) ohshite(_("read error in diversions [iii]"));
      else ohshit(_("unexpected EOF in diversions [iii]"));
    }
    l= strlen(linebuf);
    if (l == 0) ohshit(_("fgets gave an empty string from diversions [iii]"));
    if (linebuf[--l] != '\n') ohshit(_("diversions file has too-long line or EOF [ii]"));
    linebuf[l]= 0;

    oicontest->pkg= oialtname->pkg=
      strcmp(linebuf,":") ? findpackage(linebuf) : 0;

    if (oialtname->camefrom->divert || oicontest->useinstead->divert)
      ohshit(_("conflicting diversions involving `%.250s' or `%.250s'"),
             oialtname->camefrom->name, oicontest->useinstead->name);

    oialtname->camefrom->divert= oicontest;
    oicontest->useinstead->divert= oialtname;

    oicontest->next= diversions;
    diversions= oicontest;
  }
  if (ferror(file)) ohshite(_("read error in diversions [i]"));

  onerr_abort--;
}

struct fileiterator {
  struct filenamenode *namenode;
  int nbinn;
};

#define BINS (1 << 17)
 /* This must always be a power of two.  If you change it
  * consider changing the per-character hashing factor (currently
  * 1785 = 137*13) too.
  */

static struct filenamenode *bins[BINS];

struct fileiterator *iterfilestart(void) {
  struct fileiterator *i;
  i= m_malloc(sizeof(struct fileiterator));
  i->namenode= 0;
  i->nbinn= 0;
  return i;
}

struct filenamenode *iterfilenext(struct fileiterator *i) {
  struct filenamenode *r= NULL;

  while (!i->namenode) {
    if (i->nbinn >= BINS) return 0;
    i->namenode= bins[i->nbinn++];
  }
  r= i->namenode;
  i->namenode= r->next;
  return r;
}

void iterfileend(struct fileiterator *i) {
  free(i);
}

void filesdbinit(void) {
  struct filenamenode *fnn;
  int i;

  for (i=0; i<BINS; i++)
    for (fnn= bins[i]; fnn; fnn= fnn->next) {
      fnn->flags= 0;
      fnn->oldhash= 0;
      fnn->filestat= 0;
    }
}

static int hash(const char *name) {
  int v= 0;
  while (*name) { v *= 1787; v += *name; name++; }
  return v;
}

struct filenamenode *findnamenode(const char *name, enum fnnflags flags) {
  struct filenamenode **pointerp, *newnode;
  const char *orig_name = name;

  /* We skip initial slashes and ./ pairs, and add our own single leading slash. */
  name= skip_slash_dotslash(name);

  pointerp= bins + (hash(name) & (BINS-1));
  while (*pointerp) {
/* Why is this assert nescessary?  It is checking already added entries. */
    assert((*pointerp)->name[0] == '/');
    if (!strcmp((*pointerp)->name+1,name)) break;
    pointerp= &(*pointerp)->next;
  }
  if (*pointerp) return *pointerp;

  newnode= nfmalloc(sizeof(struct filenamenode));
  newnode->packages= 0;
  if((flags & fnn_nocopy) && name > orig_name && name[-1] == '/')
    newnode->name = name - 1;
  else {
    char *newname= nfmalloc(strlen(name)+2);
    newname[0]= '/'; strcpy(newname+1,name);
    newnode->name= newname;
  }
  newnode->flags= 0;
  newnode->next= 0;
  newnode->divert= 0;
  newnode->statoverride= 0;
  newnode->filestat= 0;
  *pointerp= newnode;
  nfiles++;

  return newnode;
}

/* vi: ts=8 sw=2
 */
