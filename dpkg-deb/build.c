/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * build.c - building archives
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000,2001 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2007-2014 Guillem Jover <guillem@debian.org>
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

#include <config.h>
#include <compat.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <errno.h>
#include <limits.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/c-ctype.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/path.h>
#include <dpkg/varbuf.h>
#include <dpkg/fdio.h>
#include <dpkg/buffer.h>
#include <dpkg/subproc.h>
#include <dpkg/compress.h>
#include <dpkg/ar.h>
#include <dpkg/options.h>

#include "dpkg-deb.h"

/**
 * Simple structure to store information about a file.
 */
struct file_info {
  struct file_info *next;
  struct stat st;
  char *fn;
};

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

/**
 * Read a filename from the file descriptor and create a file_info struct.
 *
 * @return A file_info struct or NULL if there is nothing to read.
 */
static struct file_info *
file_info_get(const char *root, int fd)
{
  static struct varbuf fn = VARBUF_INIT;
  struct file_info *fi;
  size_t root_len;

  varbuf_reset(&fn);
  root_len = varbuf_printf(&fn, "%s/", root);

  while (1) {
    int res;

    varbuf_grow(&fn, 1);
    res = fd_read(fd, (fn.buf + fn.used), 1);
    if (res < 0)
      return NULL;
    if (res == 0) /* EOF -> parent died. */
      return NULL;
    if (fn.buf[fn.used] == '\0')
      break;

    varbuf_trunc(&fn, fn.used + 1);
  }

  fi = file_info_new(fn.buf + root_len);
  if (lstat(fn.buf, &(fi->st)) != 0)
    ohshite(_("unable to stat file name '%.250s'"), fn.buf);

  return fi;
}

/**
 * Add a new file_info struct to a single linked list of file_info structs.
 *
 * We perform a slight optimization to work around a ‘feature’ in tar: tar
 * always recurses into subdirectories if you list a subdirectory. So if an
 * entry is added and the previous entry in the list is its subdirectory we
 * remove the subdirectory.
 *
 * After a file_info struct is added to a list it may no longer be freed, we
 * assume full responsibility for its memory.
 */
static void
file_info_list_append(struct file_info **head, struct file_info **tail,
                      struct file_info *fi)
{
  if (*head == NULL)
    *head = *tail = fi;
  else
    *tail = (*tail)->next =fi;
}

/**
 * Free the memory for all entries in a list of file_info structs.
 */
static void
file_info_list_free(struct file_info *fi)
{
  while (fi) {
    struct file_info *fl;

    fl=fi; fi=fi->next;
    file_info_free(fl);
  }
}

static void
file_treewalk_feed(const char *dir, int fd_out)
{
  int pipefd[2];
  pid_t pid;
  struct file_info *fi;
  struct file_info *symlist = NULL;
  struct file_info *symlist_end = NULL;

  m_pipe(pipefd);

  pid = subproc_fork();
  if (pid == 0) {
    m_dup2(pipefd[1], 1);
    close(pipefd[0]);
    close(pipefd[1]);

    if (chdir(dir))
      ohshite(_("failed to chdir to `%.255s'"), dir);

    execlp(FIND, "find", ".", "-path", "./" BUILDCONTROLDIR, "-prune", "-o",
           "-print0", NULL);
    ohshite(_("unable to execute %s (%s)"), "find", FIND);
  }
  close(pipefd[1]);

  /* We need to reorder the files so we can make sure that symlinks
   * will not appear before their target. */
  while ((fi = file_info_get(dir, pipefd[0])) != NULL) {
    if (S_ISLNK(fi->st.st_mode)) {
      file_info_list_append(&symlist, &symlist_end, fi);
    } else {
      if (fd_write(fd_out, fi->fn, strlen(fi->fn) + 1) < 0)
        ohshite(_("failed to write filename to tar pipe (%s)"),
                _("data member"));
      file_info_free(fi);
    }
  }

  close(pipefd[0]);
  subproc_reap(pid, "find", 0);

  for (fi = symlist; fi; fi = fi->next)
    if (fd_write(fd_out, fi->fn, strlen(fi->fn) + 1) < 0)
      ohshite(_("failed to write filename to tar pipe (%s)"), _("data member"));

  file_info_list_free(symlist);
}

static const char *const maintainerscripts[] = {
  PREINSTFILE,
  POSTINSTFILE,
  PRERMFILE,
  POSTRMFILE,
  NULL,
};

/**
 * Check control directory and file permissions.
 */
static void
check_file_perms(const char *dir)
{
  struct varbuf path = VARBUF_INIT;
  const char *const *mscriptp;
  struct stat mscriptstab;

  varbuf_printf(&path, "%s/%s/", dir, BUILDCONTROLDIR);
  if (lstat(path.buf, &mscriptstab))
    ohshite(_("unable to stat control directory"));
  if (!S_ISDIR(mscriptstab.st_mode))
    ohshit(_("control directory is not a directory"));
  if ((mscriptstab.st_mode & 07757) != 0755)
    ohshit(_("control directory has bad permissions %03lo "
             "(must be >=0755 and <=0775)"),
           (unsigned long)(mscriptstab.st_mode & 07777));

  for (mscriptp = maintainerscripts; *mscriptp; mscriptp++) {
    varbuf_reset(&path);
    varbuf_printf(&path, "%s/%s/%s", dir, BUILDCONTROLDIR, *mscriptp);
    if (!lstat(path.buf, &mscriptstab)) {
      if (S_ISLNK(mscriptstab.st_mode))
        continue;
      if (!S_ISREG(mscriptstab.st_mode))
        ohshit(_("maintainer script `%.50s' is not a plain file or symlink"),
               *mscriptp);
      if ((mscriptstab.st_mode & 07557) != 0555)
        ohshit(_("maintainer script `%.50s' has bad permissions %03lo "
                 "(must be >=0555 and <=0775)"),
               *mscriptp, (unsigned long)(mscriptstab.st_mode & 07777));
    } else if (errno != ENOENT) {
      ohshite(_("maintainer script `%.50s' is not stattable"), *mscriptp);
    }
  }

  varbuf_destroy(&path);
}

/**
 * Check if conffiles contains sane information.
 */
static void
check_conffiles(const char *dir)
{
  FILE *cf;
  struct varbuf controlfile = VARBUF_INIT;
  char conffilename[MAXCONFFILENAME + 1];
  struct file_info *conffiles_head = NULL;
  struct file_info *conffiles_tail = NULL;

  varbuf_printf(&controlfile, "%s/%s/%s", dir, BUILDCONTROLDIR, CONFFILESFILE);

  cf = fopen(controlfile.buf, "r");
  if (cf == NULL) {
    if (errno == ENOENT)
      return;

    ohshite(_("error opening conffiles file"));
  }

  while (fgets(conffilename, MAXCONFFILENAME + 1, cf)) {
    struct stat controlstab;
    int n;

    n = strlen(conffilename);
    if (!n)
      ohshite(_("empty string from fgets reading conffiles"));

    if (conffilename[n - 1] != '\n')
      ohshit(_("conffile name '%s' is too long, or missing final newline"),
             conffilename);

    conffilename[n - 1] = '\0';
    varbuf_reset(&controlfile);
    varbuf_printf(&controlfile, "%s/%s", dir, conffilename);
    if (lstat(controlfile.buf, &controlstab)) {
      if (errno == ENOENT) {
        if ((n > 1) && c_isspace(conffilename[n - 2]))
          warning(_("conffile filename '%s' contains trailing white spaces"),
                  conffilename);
        ohshit(_("conffile `%.250s' does not appear in package"), conffilename);
      } else
        ohshite(_("conffile `%.250s' is not stattable"), conffilename);
    } else if (!S_ISREG(controlstab.st_mode)) {
      warning(_("conffile '%s' is not a plain file"), conffilename);
    }

    if (file_info_find_name(conffiles_head, conffilename)) {
      warning(_("conffile name '%s' is duplicated"), conffilename);
    } else {
      struct file_info *conffile;

      conffile = file_info_new(conffilename);
      file_info_list_append(&conffiles_head, &conffiles_tail, conffile);
    }
  }

  file_info_list_free(conffiles_head);
  varbuf_destroy(&controlfile);

  if (ferror(cf))
    ohshite(_("error reading conffiles file"));
  fclose(cf);
}

/**
 * Check the control file.
 *
 * @param dir	The directory from where to build the binary package.
 * @return	The pkginfo struct from the parsed control file.
 */
static struct pkginfo *
check_control_file(const char *dir)
{
  struct pkginfo *pkg;
  char *controlfile;

  m_asprintf(&controlfile, "%s/%s/%s", dir, BUILDCONTROLDIR, CONTROLFILE);
  parsedb(controlfile, pdb_parse_binary, &pkg);

  if (strspn(pkg->set->name, "abcdefghijklmnopqrstuvwxyz0123456789+-.") !=
      strlen(pkg->set->name))
    ohshit(_("package name has characters that aren't lowercase alphanums or `-+.'"));
  if (pkg->priority == PKG_PRIO_OTHER)
    warning(_("'%s' contains user-defined Priority value '%s'"),
            controlfile, pkg->otherpriority);

  free(controlfile);

  return pkg;
}

/**
 * Perform some sanity checks on the to-be-built package control area.
 *
 * @param dir	The directory from where to build the binary package.
 * @return	The pkginfo struct from the parsed control file.
 */
static struct pkginfo *
check_control_area(const char *dir)
{
  struct pkginfo *pkg;
  int warns;

  /* Start by reading in the control file so we can check its contents. */
  pkg = check_control_file(dir);
  check_file_perms(dir);
  check_conffiles(dir);

  warns = warning_get_count();
  if (warns)
    warning(P_("ignoring %d warning about the control file(s)",
               "ignoring %d warnings about the control file(s)", warns),
            warns);

  return pkg;
}

/**
 * Generate the pathname for the destination binary package.
 *
 * If the pathname cannot be computed, because the destination is a directory,
 * then NULL will be returned.
 *
 * @param dir	The directory from where to build the binary package.
 * @param dest	The destination name, either a file or directory name.
 * @return	The pathname for the package being built.
 */
static char *
gen_dest_pathname(const char *dir, const char *dest)
{
  if (dest) {
    struct stat dest_stab;

    if (stat(dest, &dest_stab)) {
      if (errno != ENOENT)
        ohshite(_("unable to check for existence of archive `%.250s'"), dest);
    } else if (S_ISDIR(dest_stab.st_mode)) {
      /* Need to compute the destination name from the package control file. */
      return NULL;
    }

    return m_strdup(dest);
  } else {
    char *pathname;

    pathname = m_malloc(strlen(dir) + sizeof(DEBEXT));
    strcpy(pathname, dir);
    path_trim_slash_slashdot(pathname);
    strcat(pathname, DEBEXT);

    return pathname;
  }
}

/**
 * Generate the pathname for the destination binary package from control file.
 *
 * @return The pathname for the package being built.
 */
static char *
gen_dest_pathname_from_pkg(const char *dir, struct pkginfo *pkg)
{
  const char *arch_sep;
  char *path;

  if (pkg->available.arch->type == DPKG_ARCH_NONE ||
      pkg->available.arch->type == DPKG_ARCH_EMPTY)
    arch_sep = "";
  else
    arch_sep = "_";

  m_asprintf(&path, "%s/%s_%s%s%s%s", dir, pkg->set->name,
             versiondescribe(&pkg->available.version, vdew_never),
             arch_sep, pkg->available.arch->name, DEBEXT);

  return path;
}

/**
 * Overly complex function that builds a .deb file.
 */
int
do_build(const char *const *argv)
{
  struct compress_params control_compress_params;
  struct dpkg_error err;
  const char *dir, *dest;
  char *debar;
  char *tfbuf;
  int arfd;
  int p1[2], p2[2], gzfd;
  pid_t c1, c2;

  /* Decode our arguments. */
  dir = *argv++;
  if (!dir)
    badusage(_("--%s needs a <directory> argument"), cipaction->olong);

  dest = *argv++;
  if (dest && *argv)
    badusage(_("--%s takes at most two arguments"), cipaction->olong);

  debar = gen_dest_pathname(dir, dest);

  /* Perform some sanity checks on the to-be-build package. */
  if (nocheckflag) {
    if (debar == NULL)
      ohshit(_("target is directory - cannot skip control file check"));
    warning(_("not checking contents of control area"));
    printf(_("dpkg-deb: building an unknown package in '%s'.\n"), debar);
  } else {
    struct pkginfo *pkg;

    pkg = check_control_area(dir);
    if (debar == NULL)
      debar = gen_dest_pathname_from_pkg(dest, pkg);
    printf(_("dpkg-deb: building package `%s' in `%s'.\n"),
           pkg->set->name, debar);
  }
  m_output(stdout, _("<standard output>"));

  /* Now that we have verified everything its time to actually
   * build something. Let's start by making the ar-wrapper. */
  arfd = creat(debar, 0644);
  if (arfd < 0)
    ohshite(_("unable to create `%.255s'"), debar);
  /* Fork a tar to package the control-section of the package. */
  unsetenv("TAR_OPTIONS");
  m_pipe(p1);
  c1 = subproc_fork();
  if (!c1) {
    m_dup2(p1[1],1); close(p1[0]); close(p1[1]);
    if (chdir(dir))
      ohshite(_("failed to chdir to `%.255s'"), dir);
    if (chdir(BUILDCONTROLDIR))
      ohshite(_("failed to chdir to `%.255s'"), ".../DEBIAN");
    execlp(TAR, "tar", "-cf", "-", "--format=gnu", ".", NULL);
    ohshite(_("unable to execute %s (%s)"), "tar -cf", TAR);
  }
  close(p1[1]);
  /* Create a temporary file to store the control data in. Immediately
   * unlink our temporary file so others can't mess with it. */
  tfbuf = path_make_temp_template("dpkg-deb");
  gzfd = mkstemp(tfbuf);
  if (gzfd == -1)
    ohshite(_("failed to make temporary file (%s)"), _("control member"));
  /* Make sure it's gone, the fd will remain until we close it. */
  if (unlink(tfbuf))
    ohshit(_("failed to unlink temporary file (%s), %s"), _("control member"),
           tfbuf);
  free(tfbuf);

  /* And run the compressor on our control archive. */
  if (opt_uniform_compression) {
    control_compress_params = compress_params;
  } else {
    control_compress_params.type = COMPRESSOR_TYPE_GZIP;
    control_compress_params.strategy = COMPRESSOR_STRATEGY_NONE;
    control_compress_params.level = -1;
  }

  c2 = subproc_fork();
  if (!c2) {
    compress_filter(&control_compress_params, p1[0], gzfd, _("compressing control member"));
    exit(0);
  }
  close(p1[0]);
  subproc_reap(c2, _("<compress> from tar -cf"), 0);
  subproc_reap(c1, "tar -cf", 0);

  if (lseek(gzfd, 0, SEEK_SET))
    ohshite(_("failed to rewind temporary file (%s)"), _("control member"));

  /* We have our first file for the ar-archive. Write a header for it
   * to the package and insert it. */
  if (deb_format.major == 0) {
    struct stat controlstab;
    char versionbuf[40];

    if (fstat(gzfd, &controlstab))
      ohshite(_("failed to stat temporary file (%s)"), _("control member"));
    sprintf(versionbuf, "%-8s\n%jd\n", OLDARCHIVEVERSION,
            (intmax_t)controlstab.st_size);
    if (fd_write(arfd, versionbuf, strlen(versionbuf)) < 0)
      ohshite(_("error writing `%s'"), debar);
    if (fd_fd_copy(gzfd, arfd, -1, &err) < 0)
      ohshit(_("cannot copy '%s' into archive '%s': %s"), _("control member"),
             debar, err.str);
  } else if (deb_format.major == 2) {
    const char deb_magic[] = ARCHIVEVERSION "\n";
    char adminmember[16 + 1];

    sprintf(adminmember, "%s%s", ADMINMEMBER,
            compressor_get_extension(control_compress_params.type));

    dpkg_ar_put_magic(debar, arfd);
    dpkg_ar_member_put_mem(debar, arfd, DEBMAGIC, deb_magic, strlen(deb_magic));
    dpkg_ar_member_put_file(debar, arfd, adminmember, gzfd, -1);
  } else {
    internerr("unknown deb format version %d.%d", deb_format.major, deb_format.minor);
  }

  close(gzfd);

  /* Control is done, now we need to archive the data. */
  if (deb_format.major == 0) {
    /* In old format, the data member is just concatenated after the
     * control member, so we do not need a temporary file and can use
     * the compression file descriptor. */
    gzfd = arfd;
  } else if (deb_format.major == 2) {
    /* Start by creating a new temporary file. Immediately unlink the
     * temporary file so others can't mess with it. */
    tfbuf = path_make_temp_template("dpkg-deb");
    gzfd = mkstemp(tfbuf);
    if (gzfd == -1)
      ohshite(_("failed to make temporary file (%s)"), _("data member"));
    /* Make sure it's gone, the fd will remain until we close it. */
    if (unlink(tfbuf))
      ohshit(_("failed to unlink temporary file (%s), %s"), _("data member"),
             tfbuf);
    free(tfbuf);
  } else {
    internerr("unknown deb format version %d.%d", deb_format.major, deb_format.minor);
  }
  /* Fork off a tar. We will feed it a list of filenames on stdin later. */
  m_pipe(p1);
  m_pipe(p2);
  c1 = subproc_fork();
  if (!c1) {
    m_dup2(p1[0],0); close(p1[0]); close(p1[1]);
    m_dup2(p2[1],1); close(p2[0]); close(p2[1]);
    if (chdir(dir))
      ohshite(_("failed to chdir to `%.255s'"), dir);
    execlp(TAR, "tar", "-cf", "-", "--format=gnu", "--null", "--no-unquote",
                       "-T", "-", "--no-recursion", NULL);
    ohshite(_("unable to execute %s (%s)"), "tar -cf", TAR);
  }
  close(p1[0]);
  close(p2[1]);
  /* Of course we should not forget to compress the archive as well. */
  c2 = subproc_fork();
  if (!c2) {
    close(p1[1]);
    compress_filter(&compress_params, p2[0], gzfd, _("compressing data member"));
    exit(0);
  }
  close(p2[0]);

  /* All the pipes are set, now lets walk the tree, and start feeding
   * filenames to tar. */
  file_treewalk_feed(dir, p1[1]);

  /* All done, clean up wait for tar and <compress> to finish their job. */
  close(p1[1]);
  subproc_reap(c2, _("<compress> from tar -cf"), 0);
  subproc_reap(c1, "tar -cf", 0);
  /* Okay, we have data.tar as well now, add it to the ar wrapper. */
  if (deb_format.major == 2) {
    char datamember[16 + 1];

    sprintf(datamember, "%s%s", DATAMEMBER,
            compressor_get_extension(compress_params.type));

    if (lseek(gzfd, 0, SEEK_SET))
      ohshite(_("failed to rewind temporary file (%s)"), _("data member"));

    dpkg_ar_member_put_file(debar, arfd, datamember, gzfd, -1);

    close(gzfd);
  }
  if (fsync(arfd))
    ohshite(_("unable to sync file '%s'"), debar);
  if (close(arfd))
    ohshite(_("unable to close file '%s'"), debar);

  free(debar);

  return 0;
}
