/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * build.c - building archives
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000,2001 Wichert Akkerman <wakkerma@debian.org>
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
#include <time.h>
#include <dirent.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/path.h>
#include <dpkg/buffer.h>
#include <dpkg/subproc.h>
#include <dpkg/compress.h>
#include <dpkg/myopt.h>

#include "dpkg-deb.h"

/* Simple structure to store information about a file.
 */
struct file_info {
  struct file_info *next;
  struct stat	st;
  char*	fn;
};

static const char *arbitrary_fields[] = {
  "Package-Type",
  "Subarchitecture",
  "Kernel-Version",
  "Installer-Menu-Item",
  "Homepage",
  "Tag",
  NULL
};

static const char private_prefix[] = "Private-";

static bool
known_arbitrary_field(const struct arbitraryfield *field)
{
  const char **known;

  /* Always accept fields starting with a private field prefix. */
  if (strncasecmp(field->name, private_prefix, strlen(private_prefix)) == 0)
    return true;

  for (known= arbitrary_fields; *known; known++)
    if (strcasecmp(field->name, *known) == 0)
      return true;

  return false;
}

static struct file_info *
file_info_new(const char *filename)
{
  struct file_info *fi;

  fi = m_malloc(sizeof(*fi));
  fi->fn = m_strdup(filename);
  fi->next = NULL;

  return fi;
}

static void
file_info_free(struct file_info *fi)
{
  free(fi->fn);
  free(fi);
}

static struct file_info *
file_info_find_name(struct file_info *list, const char *filename)
{
  struct file_info *node;

  for (node = list; node; node = node->next)
    if (strcmp(node->fn, filename) == 0)
      return node;

  return NULL;
}

/*
 * Read the next filename from a filedescriptor and create a file_info struct
 * for it. If there is nothing to read return NULL.
 */
static struct file_info *
getfi(const char *root, int fd)
{
  static char* fn = NULL;
  static size_t fnlen = 0;
  size_t i= 0;
  struct file_info *fi;
  size_t rl = strlen(root);

  if (fn == NULL) {
    fnlen = rl + MAXFILENAME;
    fn = m_malloc(fnlen);
  } else if (fnlen < (rl + MAXFILENAME)) {
    fnlen = rl + MAXFILENAME;
    fn = m_realloc(fn, fnlen);
  }
  i=sprintf(fn,"%s/",root);
  
  while (1) {
    int	res;
    if (i>=fnlen) {
      fnlen += MAXFILENAME;
      fn = m_realloc(fn, fnlen);
    }
    if ((res=read(fd, (fn+i), sizeof(*fn)))<0) {
      if ((errno==EINTR) || (errno==EAGAIN))
	continue;
      else
	return NULL;
    }
    if (res == 0) /* EOF -> parent died. */
      return NULL;
    if (fn[i] == '\0')
      break;

    i++;

    if (i >= MAXFILENAME)
      ohshit(_("file name '%.50s...' is too long"), fn + rl + 1);
  }

  fi = file_info_new(fn + rl + 1);
  if (lstat(fn, &(fi->st)) != 0)
    ohshite(_("unable to stat file name '%.250s'"), fn);

  return fi;
}

/*
 * Add a new file_info struct to a single linked list of file_info structs.
 * We perform a slight optimization to work around a `feature' in tar: tar
 * always recurses into subdirectories if you list a subdirectory. So if an
 * entry is added and the previous entry in the list is its subdirectory we
 * remove the subdirectory. 
 *
 * After a file_info struct is added to a list it may no longer be freed, we
 * assume full responsibility for its memory.
 */
static void
add_to_filist(struct file_info **start, struct file_info **end,
              struct file_info *fi)
{
  if (*start==NULL)
    *start=*end=fi;
  else 
    *end=(*end)->next=fi;
}

/*
 * Free the memory for all entries in a list of file_info structs.
 */
static void
free_filist(struct file_info *fi)
{
  while (fi) {
    struct file_info *fl;

    fl=fi; fi=fi->next;
    file_info_free(fl);
  }
}

/* Overly complex function that builds a .deb file
 */
void do_build(const char *const *argv) {
  static const char *const maintainerscripts[]= {
    PREINSTFILE, POSTINSTFILE, PRERMFILE, POSTRMFILE, NULL
  };
  
  char *m;
  const char *debar, *directory, *const *mscriptp, *versionstring, *arch;
  char *controlfile, *tfbuf;
  struct pkginfo *checkedinfo;
  struct arbitraryfield *field;
  FILE *ar, *cf;
  int p1[2], p2[2], p3[2], warns, n, c, subdir, gzfd;
  pid_t c1,c2,c3;
  struct stat controlstab, datastab, mscriptstab, debarstab;
  char conffilename[MAXCONFFILENAME+1];
  time_t thetime= 0;
  struct file_info *fi;
  struct file_info *symlist = NULL;
  struct file_info *symlist_end = NULL;
  
/* Decode our arguments */
  directory = *argv++;
  if (!directory)
    badusage(_("--%s needs a <directory> argument"), cipaction->olong);
  subdir= 0;
  debar = *argv++;
  if (debar != NULL) {
    if (*argv) badusage(_("--build takes at most two arguments"));
    if (debar) {
      if (stat(debar,&debarstab)) {
        if (errno != ENOENT)
          ohshite(_("unable to check for existence of archive `%.250s'"),debar);
      } else if (S_ISDIR(debarstab.st_mode)) {
        subdir= 1;
      }
    }
  } else {
    m= m_malloc(strlen(directory) + sizeof(DEBEXT));
    strcpy(m, directory);
    path_rtrim_slash_slashdot(m);
    strcat(m, DEBEXT);
    debar= m;
  }
    
  /* Perform some sanity checks on the to-be-build package.
   */
  if (nocheckflag) {
    if (subdir)
      ohshit(_("target is directory - cannot skip control file check"));
    warning(_("not checking contents of control area."));
    printf(_("dpkg-deb: building an unknown package in '%s'.\n"), debar);
  } else {
    controlfile= m_malloc(strlen(directory) + sizeof(BUILDCONTROLDIR) +
                          sizeof(CONTROLFILE) + sizeof(CONFFILESFILE) +
                          sizeof(POSTINSTFILE) + sizeof(PREINSTFILE) +
                          sizeof(POSTRMFILE) + sizeof(PRERMFILE) +
                          MAXCONFFILENAME + 5);
    /* Lets start by reading in the control-file so we can check its contents */
    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/" CONTROLFILE);
    warns = 0;
    parsedb(controlfile, pdb_recordavailable|pdb_rejectstatus,
            &checkedinfo, stderr, &warns);
    if (strspn(checkedinfo->name,
               "abcdefghijklmnopqrstuvwxyz0123456789+-.")
        != strlen(checkedinfo->name))
      ohshit(_("package name has characters that aren't lowercase alphanums or `-+.'"));
    if (checkedinfo->priority == pri_other) {
      warning(_("'%s' contains user-defined Priority value '%s'"),
              controlfile, checkedinfo->otherpriority);
      warns++;
    }
    for (field= checkedinfo->available.arbs; field; field= field->next) {
      if (known_arbitrary_field(field))
        continue;

      warning(_("'%s' contains user-defined field '%s'"),
              controlfile, field->name);
      warns++;
    }

    if (subdir) {
      versionstring= versiondescribe(&checkedinfo->available.version,vdew_never);
      arch= checkedinfo->available.architecture; if (!arch) arch= "";
      m= m_malloc(sizeof(DEBEXT)+1+strlen(debar)+1+strlen(checkedinfo->name)+
                  strlen(versionstring)+1+strlen(arch));
      sprintf(m,"%s/%s_%s%s%s" DEBEXT,debar,checkedinfo->name,versionstring,
              arch[0] ? "_" : "", arch);
      debar= m;
    }
    printf(_("dpkg-deb: building package `%s' in `%s'.\n"), checkedinfo->name, debar);

    /* Check file permissions */
    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/");
    if (lstat(controlfile, &mscriptstab))
      ohshite(_("unable to stat control directory"));
    if (!S_ISDIR(mscriptstab.st_mode))
      ohshit(_("control directory is not a directory"));
    if ((mscriptstab.st_mode & 07757) != 0755)
      ohshit(_("control directory has bad permissions %03lo (must be >=0755 "
             "and <=0775)"), (unsigned long)(mscriptstab.st_mode & 07777));

    for (mscriptp= maintainerscripts; *mscriptp; mscriptp++) {
      strcpy(controlfile, directory);
      strcat(controlfile, "/" BUILDCONTROLDIR "/");
      strcat(controlfile, *mscriptp);

      if (!lstat(controlfile,&mscriptstab)) {
        if (S_ISLNK(mscriptstab.st_mode)) continue;
        if (!S_ISREG(mscriptstab.st_mode))
          ohshit(_("maintainer script `%.50s' is not a plain file or symlink"),*mscriptp);
        if ((mscriptstab.st_mode & 07557) != 0555)
          ohshit(_("maintainer script `%.50s' has bad permissions %03lo "
                 "(must be >=0555 and <=0775)"),
                 *mscriptp, (unsigned long)(mscriptstab.st_mode & 07777));
      } else if (errno != ENOENT) {
        ohshite(_("maintainer script `%.50s' is not stattable"),*mscriptp);
      }
    }

    /* Check if conffiles contains sane information */
    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/" CONFFILESFILE);
    if ((cf= fopen(controlfile,"r"))) {
      struct file_info *conffiles_head = NULL;
      struct file_info *conffiles_tail = NULL;

      while (fgets(conffilename,MAXCONFFILENAME+1,cf)) {
        n= strlen(conffilename);
        if (!n) ohshite(_("empty string from fgets reading conffiles"));
        if (conffilename[n-1] != '\n') {
          warning(_("conffile name '%.50s...' is too long, or missing final newline"),
		  conffilename);
          warns++;
          while ((c= getc(cf)) != EOF && c != '\n');
          continue;
        }
        conffilename[n - 1] = '\0';
        strcpy(controlfile, directory);
        strcat(controlfile, "/");
        strcat(controlfile, conffilename);
        if (lstat(controlfile,&controlstab)) {
	  if (errno == ENOENT) {
	    if((n > 1) && isspace(conffilename[n-2]))
	      warning(_("conffile filename '%s' contains trailing white spaces"),
	              conffilename);
	    ohshit(_("conffile `%.250s' does not appear in package"), conffilename);
	  } else
	    ohshite(_("conffile `%.250s' is not stattable"), conffilename);
        } else if (!S_ISREG(controlstab.st_mode)) {
          warning(_("conffile '%s' is not a plain file"), conffilename);
          warns++;
        }

        if (file_info_find_name(conffiles_head, conffilename))
          warning(_("conffile name '%s' is duplicated"), conffilename);
        else {
          struct file_info *conffile;

          conffile = file_info_new(conffilename);
          add_to_filist(&conffiles_head, &conffiles_tail, conffile);
        }
      }

      free_filist(conffiles_head);

      if (ferror(cf)) ohshite(_("error reading conffiles file"));
      fclose(cf);
    } else if (errno != ENOENT) {
      ohshite(_("error opening conffiles file"));
    }
    if (warns)
      warning(_("ignoring %d warnings about the control file(s)\n"), warns);
  }
  m_output(stdout, _("<standard output>"));
  
  /* Now that we have verified everything its time to actually
   * build something. Lets start by making the ar-wrapper.
   */
  if (!(ar=fopen(debar,"wb"))) ohshite(_("unable to create `%.255s'"),debar);
  if (setvbuf(ar, NULL, _IONBF, 0))
    ohshite(_("unable to unbuffer `%.255s'"), debar);
  /* Fork a tar to package the control-section of the package */
  unsetenv("TAR_OPTIONS");
  m_pipe(p1);
  c1 = subproc_fork();
  if (!c1) {
    m_dup2(p1[1],1); close(p1[0]); close(p1[1]);
    if (chdir(directory)) ohshite(_("failed to chdir to `%.255s'"),directory);
    if (chdir(BUILDCONTROLDIR)) ohshite(_("failed to chdir to .../DEBIAN"));
    execlp(TAR, "tar", "-cf", "-", "--format=gnu", ".", NULL);
    ohshite(_("failed to exec tar -cf"));
  }
  close(p1[1]);
  /* Create a temporary file to store the control data in. Immediately unlink
   * our temporary file so others can't mess with it.
   */
  tfbuf = path_make_temp_template("dpkg-deb");
  if ((gzfd= mkstemp(tfbuf)) == -1) ohshite(_("failed to make tmpfile (control)"));
  /* make sure it's gone, the fd will remain until we close it */
  if (unlink(tfbuf)) ohshit(_("failed to unlink tmpfile (control), %s"),
      tfbuf);
  free(tfbuf);

  /* And run gzip to compress our control archive */
  c2 = subproc_fork();
  if (!c2) {
    m_dup2(p1[0],0); m_dup2(gzfd,1); close(p1[0]); close(gzfd);
    compress_filter(&compressor_gzip, 0, 1, 9, _("control"));
  }
  close(p1[0]);
  subproc_wait_check(c2, "gzip -9c", 0);
  subproc_wait_check(c1, "tar -cf", 0);
  if (fstat(gzfd,&controlstab)) ohshite(_("failed to fstat tmpfile (control)"));
  /* We have our first file for the ar-archive. Write a header for it to the
   * package and insert it.
   */
  if (oldformatflag) {
    if (fprintf(ar, "%-8s\n%ld\n", OLDARCHIVEVERSION, (long)controlstab.st_size) == EOF)
      werr(debar);
  } else {
    thetime = time(NULL);
    if (fprintf(ar,
                "!<arch>\n"
                "%-16s%-12lu0     0     100644  %-10ld`\n"
                ARCHIVEVERSION "\n"
                "%s"
                "%-16s%-12lu0     0     100644  %-10ld`\n",
                DEBMAGIC,
                thetime,
                (long)sizeof(ARCHIVEVERSION),
                (sizeof(ARCHIVEVERSION)&1) ? "\n" : "",
                ADMINMEMBER,
                (unsigned long)thetime,
                (long)controlstab.st_size) == EOF)
      werr(debar);
  }                
                
  if (lseek(gzfd,0,SEEK_SET)) ohshite(_("failed to rewind tmpfile (control)"));
  fd_fd_copy(gzfd, fileno(ar), -1, _("control"));

  /* Control is done, now we need to archive the data. Start by creating
   * a new temporary file. Immediately unlink the temporary file so others
   * can't mess with it. */
  if (!oldformatflag) {
    close(gzfd);
    tfbuf = path_make_temp_template("dpkg-deb");
    if ((gzfd= mkstemp(tfbuf)) == -1) ohshite(_("failed to make tmpfile (data)"));
    /* make sure it's gone, the fd will remain until we close it */
    if (unlink(tfbuf)) ohshit(_("failed to unlink tmpfile (data), %s"),
        tfbuf);
    free(tfbuf);
  }
  /* Fork off a tar. We will feed it a list of filenames on stdin later.
   */
  m_pipe(p1);
  m_pipe(p2);
  c1 = subproc_fork();
  if (!c1) {
    m_dup2(p1[0],0); close(p1[0]); close(p1[1]);
    m_dup2(p2[1],1); close(p2[0]); close(p2[1]);
    if (chdir(directory)) ohshite(_("failed to chdir to `%.255s'"),directory);
    execlp(TAR, "tar", "-cf", "-", "--format=gnu", "--null", "-T", "-", "--no-recursion", NULL);
    ohshite(_("failed to exec tar -cf"));
  }
  close(p1[0]);
  close(p2[1]);
  /* Of course we should not forget to compress the archive as well.. */
  c2 = subproc_fork();
  if (!c2) {
    close(p1[1]);
    m_dup2(p2[0],0); close(p2[0]);
    m_dup2(oldformatflag ? fileno(ar) : gzfd,1);
    compress_filter(compressor, 0, 1, compress_level, _("data"));
  }
  close(p2[0]);
  /* All the pipes are set, now lets run find, and start feeding
   * filenames to tar.
   */

  m_pipe(p3);
  c3 = subproc_fork();
  if (!c3) {
    m_dup2(p3[1],1); close(p3[0]); close(p3[1]);
    if (chdir(directory)) ohshite(_("failed to chdir to `%.255s'"),directory);
    execlp(FIND, "find", ".", "-path", "./" BUILDCONTROLDIR, "-prune", "-o",
           "-print0", NULL);
    ohshite(_("failed to exec find"));
  }
  close(p3[1]);
  /* We need to reorder the files so we can make sure that symlinks
   * will not appear before their target.
   */
  while ((fi=getfi(directory, p3[0]))!=NULL)
    if (S_ISLNK(fi->st.st_mode))
      add_to_filist(&symlist, &symlist_end, fi);
    else {
      if (write(p1[1], fi->fn, strlen(fi->fn)+1) ==- 1)
	ohshite(_("failed to write filename to tar pipe (data)"));
      file_info_free(fi);
    }
  close(p3[0]);
  subproc_wait_check(c3, "find", 0);

  for (fi= symlist;fi;fi= fi->next)
    if (write(p1[1], fi->fn, strlen(fi->fn)+1) == -1)
      ohshite(_("failed to write filename to tar pipe (data)"));
  /* All done, clean up wait for tar and gzip to finish their job */
  close(p1[1]);
  free_filist(symlist);
  subproc_wait_check(c2, _("<compress> from tar -cf"), 0);
  subproc_wait_check(c1, "tar -cf", 0);
  /* Okay, we have data.tar.gz as well now, add it to the ar wrapper */
  if (!oldformatflag) {
    char datamember[16 + 1];

    sprintf(datamember, "%s%s", DATAMEMBER, compressor->extension);

    if (fstat(gzfd, &datastab))
      ohshite(_("failed to fstat tmpfile (data)"));
    if (fprintf(ar,
                "%s"
                "%-16s%-12lu0     0     100644  %-10ld`\n",
                (controlstab.st_size & 1) ? "\n" : "",
                datamember,
                (unsigned long)thetime,
                (long)datastab.st_size) == EOF)
      werr(debar);

    if (lseek(gzfd,0,SEEK_SET)) ohshite(_("failed to rewind tmpfile (data)"));
    fd_fd_copy(gzfd, fileno(ar), -1, _("cat (data)"));

    if (datastab.st_size & 1)
      if (putc('\n',ar) == EOF)
        werr(debar);
  }
  if (fflush(ar))
    ohshite(_("unable to flush file '%s'"), debar);
  if (fsync(fileno(ar)))
    ohshite(_("unable to sync file '%s'"), debar);
  if (fclose(ar)) werr(debar);
                             
  exit(0);
}

