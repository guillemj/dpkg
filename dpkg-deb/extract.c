/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * extract.c - extracting archives
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
#include <fcntl.h>
#include <unistd.h>
#include <ar.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/fdio.h>
#include <dpkg/buffer.h>
#include <dpkg/subproc.h>
#include <dpkg/command.h>
#include <dpkg/compress.h>
#include <dpkg/ar.h>
#include <dpkg/myopt.h>

#include "dpkg-deb.h"

static void movecontrolfiles(const char *thing) {
  char buf[200];
  pid_t pid;

  sprintf(buf, "mv %s/* . && rmdir %s", thing, thing);
  pid = subproc_fork();
  if (pid == 0) {
    command_shell(buf, _("shell command to move files"));
  }
  subproc_wait_check(pid, _("shell command to move files"), 0);
}

static void DPKG_ATTR_NORET
read_fail(int rc, const char *filename, const char *what)
{
  if (rc == 0)
    ohshit(_("unexpected end of file in %s in %.255s"),what,filename);
  else
    ohshite(_("error reading %s from file %.255s"), what, filename);
}

static ssize_t
read_line(int fd, char *buf, size_t min_size, size_t max_size)
{
  ssize_t line_size = 0;
  size_t n = min_size;

  while (line_size < (ssize_t)max_size) {
    ssize_t r;
    char *nl;

    r = fd_read(fd, buf + line_size, n);
    if (r <= 0)
      return r;

    nl = strchr(buf + line_size, '\n');
    line_size += r;

    if (nl != NULL) {
      nl[1] = '\0';
      return line_size;
    }

    n = 1;
  }

  buf[line_size] = '\0';
  return line_size;
}

void
extracthalf(const char *debar, const char *dir, const char *taroption,
            int admininfo)
{
  char versionbuf[40];
  float versionnum;
  off_t ctrllennum, memberlen = 0;
  ssize_t r;
  int dummy;
  pid_t c1=0,c2,c3;
  int p1[2], p2[2];
  int arfd;
  struct stat stab;
  char nlc;
  int adminmember;
  bool oldformat, header_done;
  struct compressor *decompressor = &compressor_gzip;

  arfd = open(debar, O_RDONLY);
  if (arfd < 0)
    ohshite(_("failed to read archive `%.255s'"), debar);
  if (fstat(arfd, &stab))
    ohshite(_("failed to fstat archive"));

  r = read_line(arfd, versionbuf, strlen(DPKG_AR_MAGIC), sizeof(versionbuf));
  if (r < 0)
    read_fail(r, debar, _("archive magic version number"));

  if (!strcmp(versionbuf, DPKG_AR_MAGIC)) {
    oldformat = false;

    ctrllennum= 0;
    header_done = false;
    for (;;) {
      struct ar_hdr arh;

      r = fd_read(arfd, &arh, sizeof(arh));
      if (r != sizeof(arh))
        read_fail(r, debar, _("archive member header"));

      dpkg_ar_normalize_name(&arh);

      if (memcmp(arh.ar_fmag,ARFMAG,sizeof(arh.ar_fmag)))
        ohshit(_("file '%.250s' is corrupt - bad archive header magic"), debar);
      memberlen = dpkg_ar_member_get_size(debar, &arh);
      if (!header_done) {
        char *infobuf;
        char *cur;

        if (strncmp(arh.ar_name, DEBMAGIC, sizeof(arh.ar_name)) != 0)
          ohshit(_("file `%.250s' is not a debian binary archive (try dpkg-split?)"),debar);
        infobuf= m_malloc(memberlen+1);
        r = fd_read(arfd, infobuf, memberlen + (memberlen & 1));
        if (r != (memberlen + (memberlen & 1)))
          read_fail(r, debar, _("archive information header member"));
        infobuf[memberlen] = '\0';
        cur= strchr(infobuf,'\n');
        if (!cur) ohshit(_("archive has no newlines in header"));
        *cur = '\0';
        cur= strchr(infobuf,'.');
        if (!cur) ohshit(_("archive has no dot in version number"));
        *cur = '\0';
        if (strcmp(infobuf,"2"))
          ohshit(_("archive version %.250s not understood, get newer dpkg-deb"), infobuf);
        *cur= '.';
        strncpy(versionbuf,infobuf,sizeof(versionbuf));
        versionbuf[sizeof(versionbuf) - 1] = '\0';
        free(infobuf);

        header_done = true;
      } else if (arh.ar_name[0] == '_') {
        /* Members with ‘_’ are noncritical, and if we don't understand
         * them we skip them. */
        fd_null_copy(arfd, memberlen + (memberlen & 1),
                     _("skipped archive member data from %s"), debar);
      } else {
	if (strncmp(arh.ar_name, ADMINMEMBER, sizeof(arh.ar_name)) == 0)
	  adminmember = 1;
	else {
	  adminmember = -1;

	  if (strncmp(arh.ar_name, DATAMEMBER, strlen(DATAMEMBER)) == 0) {
	    const char *extension = arh.ar_name + strlen(DATAMEMBER);

	    adminmember= 0;
	    decompressor = compressor_find_by_extension(extension);
	  }

          if (adminmember == -1 || decompressor == NULL)
            ohshit(_("archive '%.250s' contains not understood data member %.*s, giving up"),
                   debar, (int)sizeof(arh.ar_name), arh.ar_name);
        }
        if (adminmember == 1) {
          if (ctrllennum != 0)
            ohshit(_("archive '%.250s' contains two control members, giving up"),
                   debar);
          ctrllennum= memberlen;
        }
        if (!adminmember != !admininfo) {
          fd_null_copy(arfd, memberlen + (memberlen & 1),
                       _("skipped archive member data from %s"), debar);
        } else {
          /* Yes! - found it. */
          break;
        }
      }
    }

    if (admininfo >= 2) {
      printf(_(" new debian package, version %s.\n"
               " size %jd bytes: control archive= %jd bytes.\n"),
             versionbuf, (intmax_t)stab.st_size, (intmax_t)ctrllennum);
      m_output(stdout, _("<standard output>"));
    }
  } else if (!strncmp(versionbuf,"0.93",4) &&
             sscanf(versionbuf,"%f%c%d",&versionnum,&nlc,&dummy) == 2 &&
             nlc == '\n') {
    char ctrllenbuf[40];
    int l = 0;

    oldformat = true;
    l = strlen(versionbuf);
    if (l && versionbuf[l - 1] == '\n')
      versionbuf[l - 1] = '\0';

    r = read_line(arfd, ctrllenbuf, 1, sizeof(ctrllenbuf));
    if (r < 0)
      read_fail(r, debar, _("archive control member size"));
    if (sscanf(ctrllenbuf, "%jd%c%d", &ctrllennum, &nlc, &dummy) != 2 ||
        nlc != '\n')
      ohshit(_("archive has malformatted control member size '%s'"), ctrllenbuf);

    if (admininfo) {
      memberlen = ctrllennum;
    } else {
      memberlen = stab.st_size - ctrllennum - strlen(ctrllenbuf) - l;
      fd_null_copy(arfd, ctrllennum,
                   _("skipped archive control member data from %s"), debar);
    }

    if (admininfo >= 2) {
      printf(_(" old debian package, version %s.\n"
               " size %jd bytes: control archive= %jd, main archive= %jd.\n"),
             versionbuf, (intmax_t)stab.st_size, (intmax_t)ctrllennum,
             (intmax_t)(stab.st_size - ctrllennum - strlen(ctrllenbuf) - l));
      m_output(stdout, _("<standard output>"));
    }
  } else {
    if (!strncmp(versionbuf,"!<arch>",7)) {
      fprintf(stderr,
              _("dpkg-deb: file looks like it might be an archive which has been\n"
                "dpkg-deb:    corrupted by being downloaded in ASCII mode\n"));
    }

    ohshit(_("`%.255s' is not a debian format archive"),debar);
  }

  m_pipe(p1);
  c1 = subproc_fork();
  if (!c1) {
    close(p1[0]);
    fd_fd_copy(arfd, p1[1], memberlen, _("failed to write to pipe in copy"));
    if (close(p1[1]))
      ohshite(_("failed to close pipe in copy"));
    exit(0);
  }
  close(p1[1]);

  if (taroption) m_pipe(p2);

  c2 = subproc_fork();
  if (!c2) {
    m_dup2(p1[0], 0);
    if (admininfo) close(p1[0]);
    if (taroption) { m_dup2(p2[1],1); close(p2[0]); close(p2[1]); }
    decompress_filter(decompressor, 0, 1, _("data"));
  }
  close(p1[0]);
  close(arfd);
  if (taroption) close(p2[1]);

  if (taroption && dir) {
    if (chdir(dir)) {
      if (errno == ENOENT) {
        if (mkdir(dir, 0777))
          ohshite(_("failed to create directory"));
        if (chdir(dir))
          ohshite(_("failed to chdir to directory after creating it"));
      } else {
        ohshite(_("failed to chdir to directory"));
      }
    }
  }

  if (taroption) {
    c3 = subproc_fork();
    if (!c3) {
      char buffer[30+2];
      if (strlen(taroption) > 30)
        internerr("taroption is too long '%s'", taroption);
      strcpy(buffer, taroption);
      strcat(buffer, "f");
      m_dup2(p2[0],0);
      close(p2[0]);

      unsetenv("TAR_OPTIONS");

      execlp(TAR, "tar", buffer, "-", NULL);
      ohshite(_("unable to execute %s (%s)"), "tar", TAR);
    }
    close(p2[0]);
    subproc_wait_check(c3, "tar", 0);
  }

  subproc_wait_check(c2, _("<decompress>"), PROCPIPE);
  if (c1 != -1)
    subproc_wait_check(c1, _("paste"), 0);
  if (oldformat && admininfo) {
    if (versionnum == 0.931F) {
      movecontrolfiles(OLDOLDDEBDIR);
    } else if (versionnum == 0.932F || versionnum == 0.933F) {
      movecontrolfiles(OLDDEBDIR);
    }
  }
}

static void controlextractvextract(int admin,
                                   const char *taroptions,
                                   const char *const *argv) {
  const char *debar, *dir;

  if (!(debar= *argv++))
    badusage(_("--%s needs a .deb filename argument"),cipaction->olong);
  dir = *argv++;
  if (!dir) {
    if (admin)
      dir = EXTRACTCONTROLDIR;
    else ohshit(_("--%s needs a target directory.\n"
                "Perhaps you should be using dpkg --install ?"),cipaction->olong);
  } else if (*argv) {
    badusage(_("--%s takes at most two arguments (.deb and directory)"),cipaction->olong);
  }
  extracthalf(debar, dir, taroptions, admin);
}

void do_fsystarfile(const char *const *argv) {
  const char *debar;

  if (!(debar= *argv++))
    badusage(_("--%s needs a .deb filename argument"),cipaction->olong);
  if (*argv)
    badusage(_("--%s takes only one argument (.deb filename)"),cipaction->olong);
  extracthalf(debar, NULL, NULL, 0);
}

void do_control(const char *const *argv) { controlextractvextract(1, "x", argv); }
void do_extract(const char *const *argv) { controlextractvextract(0, "xp", argv); }
void do_vextract(const char *const *argv) { controlextractvextract(0, "xpv", argv); }
