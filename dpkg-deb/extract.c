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
#include <unistd.h>
#include <ar.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/buffer.h>
#include <dpkg/subproc.h>
#include <dpkg/compress.h>
#include <dpkg/ar.h>
#include <dpkg/myopt.h>

#include "dpkg-deb.h"

static void movecontrolfiles(const char *thing) {
  char buf[200];
  pid_t c1;
  
  sprintf(buf, "mv %s/* . && rmdir %s", thing, thing);
  c1 = subproc_fork();
  if (!c1) {
    execlp("sh", "sh", "-c", buf, NULL);
    ohshite(_("failed to exec sh -c mv foo/* &c"));
  }
  subproc_wait_check(c1, "sh -c mv foo/* &c", 0);
}

static void DPKG_ATTR_NORET
readfail(FILE *a, const char *filename, const char *what)
{
  if (ferror(a)) {
    ohshite(_("error reading %s from file %.255s"), what, filename);
  } else {
    ohshit(_("unexpected end of file in %s in %.255s"),what,filename);
  }
}

static size_t
parseheaderlength(const char *inh, size_t len,
                  const char *fn, const char *what)
{
  char lintbuf[15];
  ssize_t r;
  char *endp;

  if (memchr(inh,0,len))
    ohshit(_("file `%.250s' is corrupt - %.250s length contains nulls"),fn,what);
  assert(sizeof(lintbuf) > len);
  memcpy(lintbuf,inh,len);
  lintbuf[len]= ' ';
  *strchr(lintbuf, ' ') = '\0';
  r = strtol(lintbuf, &endp, 10);
  if (r < 0)
    ohshit(_("file `%.250s' is corrupt - negative member length %zi"), fn, r);
  if (*endp)
    ohshit(_("file `%.250s' is corrupt - bad digit (code %d) in %s"),fn,*endp,what);
  return (size_t)r;
}

static void
safe_fflush(FILE *f)
{
#if defined(__GLIBC__) && (__GLIBC__ == 2) && (__GLIBC_MINOR__ > 0)
  /* XXX: Glibc 2.1 and some versions of Linux want to make fflush()
   * move the current fpos. Remove this code some time. */
  fpos_t fpos;

  if (fgetpos(f, &fpos))
    ohshit(_("failed getting the current file position"));
  fflush(f);
  if (fsetpos(f, &fpos))
    ohshit(_("failed setting the current file position"));
#else
  fflush(f);
#endif
}

void extracthalf(const char *debar, const char *directory,
                 const char *taroption, int admininfo) {
  char versionbuf[40];
  float versionnum;
  char ctrllenbuf[40], *infobuf;
  size_t ctrllennum, memberlen= 0;
  int dummy, l= 0;
  pid_t c1=0,c2,c3;
  void *ctrlarea = NULL;
  int p1[2], p2[2];
  FILE *ar, *pi;
  struct stat stab;
  char nlc;
  char *cur;
  struct ar_hdr arh;
  int readfromfd, adminmember;
  bool oldformat, header_done;
  struct compressor *decompressor = &compressor_gzip;
  
  ar= fopen(debar,"r"); if (!ar) ohshite(_("failed to read archive `%.255s'"),debar);
  if (fstat(fileno(ar),&stab)) ohshite(_("failed to fstat archive"));
  if (!fgets(versionbuf,sizeof(versionbuf),ar)) readfail(ar,debar,_("version number"));

  if (!strcmp(versionbuf,"!<arch>\n")) {
    oldformat = false;

    ctrllennum= 0;
    header_done = false;
    for (;;) {
      if (fread(&arh,1,sizeof(arh),ar) != sizeof(arh))
        readfail(ar,debar,_("between members"));

      dpkg_ar_normalize_name(&arh);

      if (memcmp(arh.ar_fmag,ARFMAG,sizeof(arh.ar_fmag)))
        ohshit(_("file `%.250s' is corrupt - bad magic at end of first header"),debar);
      memberlen= parseheaderlength(arh.ar_size,sizeof(arh.ar_size),
                                   debar, _("member length"));
      if (!header_done) {
        if (strncmp(arh.ar_name, DEBMAGIC, sizeof(arh.ar_name)) != 0)
          ohshit(_("file `%.250s' is not a debian binary archive (try dpkg-split?)"),debar);
        infobuf= m_malloc(memberlen+1);
        if (fread(infobuf,1, memberlen + (memberlen&1), ar) != memberlen + (memberlen&1))
          readfail(ar,debar,_("header info member"));
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
        header_done = true;
      } else if (arh.ar_name[0] == '_') {
          /* Members with `_' are noncritical, and if we don't understand them
           * we skip them.
           */
	stream_null_copy(ar, memberlen + (memberlen&1),_("skipped member data from %s"), debar);
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
            ohshit(_("file `%.250s' contains ununderstood data member %.*s, giving up"),
                   debar, (int)sizeof(arh.ar_name), arh.ar_name);
        }
        if (adminmember == 1) {
          if (ctrllennum != 0)
            ohshit(_("file `%.250s' contains two control members, giving up"), debar);
          ctrllennum= memberlen;
        }
        if (!adminmember != !admininfo) {
	  stream_null_copy(ar, memberlen + (memberlen&1),_("skipped member data from %s"), debar);
        } else {
          break; /* Yes ! - found it. */
        }
      }
    }

    if (admininfo >= 2) {
      printf(_(" new debian package, version %s.\n"
               " size %ld bytes: control archive= %zi bytes.\n"),
             versionbuf, (long)stab.st_size, ctrllennum);
      m_output(stdout, _("<standard output>"));
    }
  } else if (!strncmp(versionbuf,"0.93",4) &&
             sscanf(versionbuf,"%f%c%d",&versionnum,&nlc,&dummy) == 2 &&
             nlc == '\n') {
    
    oldformat = true;
    l = strlen(versionbuf);
    if (l && versionbuf[l - 1] == '\n')
      versionbuf[l - 1] = '\0';
    if (!fgets(ctrllenbuf,sizeof(ctrllenbuf),ar))
      readfail(ar, debar, _("control information length"));
    if (sscanf(ctrllenbuf,"%zi%c%d",&ctrllennum,&nlc,&dummy) !=2 || nlc != '\n')
      ohshit(_("archive has malformatted control length `%s'"), ctrllenbuf);

    if (admininfo >= 2) {
      printf(_(" old debian package, version %s.\n"
               " size %ld bytes: control archive= %zi, main archive= %ld.\n"),
             versionbuf, (long)stab.st_size, ctrllennum,
             (long) (stab.st_size - ctrllennum - strlen(ctrllenbuf) - l));
      m_output(stdout, _("<standard output>"));
    }

    ctrlarea = m_malloc(ctrllennum);

    errno=0; if (fread(ctrlarea,1,ctrllennum,ar) != ctrllennum)
      readfail(ar, debar, _("control area"));

  } else {
    
    if (!strncmp(versionbuf,"!<arch>",7)) {
      fprintf(stderr,
              _("dpkg-deb: file looks like it might be an archive which has been\n"
                "dpkg-deb:    corrupted by being downloaded in ASCII mode\n"));
    }

    ohshit(_("`%.255s' is not a debian format archive"),debar);

  }

  safe_fflush(ar);

  if (oldformat) {
    if (admininfo) {
      m_pipe(p1);
      c1 = subproc_fork();
      if (!c1) {
        close(p1[0]);
	pi = fdopen(p1[1], "w");
	if (!pi)
	  ohshite(_("failed to open pipe descriptor `1' in paste"));
        errno=0; if (fwrite(ctrlarea,1,ctrllennum,pi) != ctrllennum)
          ohshit(_("failed to write to gzip -dc"));
        if (fclose(pi)) ohshit(_("failed to close gzip -dc"));
        exit(0);
      }
      close(p1[1]);
      readfromfd= p1[0];
    } else {
      if (lseek(fileno(ar),l+strlen(ctrllenbuf)+ctrllennum,SEEK_SET) == -1)
        ohshite(_("failed to syscall lseek to files archive portion"));
      c1= -1;
      readfromfd= fileno(ar);
    }
  } else {
    m_pipe(p1);
    c1 = subproc_fork();
    if (!c1) {
      close(p1[0]);
      stream_fd_copy(ar, p1[1], memberlen, _("failed to write to pipe in copy"));
      if (close(p1[1]) == EOF) ohshite(_("failed to close pipe in copy"));
      exit(0);
    }
    close(p1[1]);
    readfromfd= p1[0];
  }
  
  if (taroption) m_pipe(p2);
  
  c2 = subproc_fork();
  if (!c2) {
    m_dup2(readfromfd,0);
    if (admininfo) close(p1[0]);
    if (taroption) { m_dup2(p2[1],1); close(p2[0]); close(p2[1]); }
    decompress_filter(decompressor, 0, 1, _("data"));
  }
  if (readfromfd != fileno(ar)) close(readfromfd);
  if (taroption) close(p2[1]);

  if (taroption && directory) {
    if (chdir(directory)) {
      if (errno == ENOENT) {
        if (mkdir(directory,0777)) ohshite(_("failed to create directory"));
        if (chdir(directory)) ohshite(_("failed to chdir to directory after creating it"));
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
      ohshite(_("failed to exec tar"));
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
  const char *debar, *directory;
  
  if (!(debar= *argv++))
    badusage(_("--%s needs a .deb filename argument"),cipaction->olong);
  if (!(directory= *argv++)) {
    if (admin) directory= EXTRACTCONTROLDIR;
    else ohshit(_("--%s needs a target directory.\n"
                "Perhaps you should be using dpkg --install ?"),cipaction->olong);
  } else if (*argv) {
    badusage(_("--%s takes at most two arguments (.deb and directory)"),cipaction->olong);
  }
  extracthalf(debar, directory, taroptions, admin);
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



