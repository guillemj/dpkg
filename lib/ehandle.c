/*
 * libdpkg - Debian packaging suite library routines
 * ehandle.c - error handling
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
#include <errno.h>
#include <unistd.h>
#include <stdarg.h>
#include <assert.h>

#include <dpkg.h>
#include <dpkg-db.h>

static const char *errmsg; /* points to errmsgbuf or malloc'd */
static char errmsgbuf[4096];
/* 6x255 for inserted strings (%.255s &c in fmt; also %s with limited length arg)
 * 1x255 for constant text
 * 1x255 for strerror()
 * same again just in case.
 */

#define NCALLS 2

struct cleanupentry {
  struct cleanupentry *next;
  struct {
    int mask;
    void (*call)(int argc, void **argv);
  } calls[NCALLS];
  int cpmask, cpvalue;
  int argc;
  void *argv[1];
};         

struct errorcontext {
  struct errorcontext *next;
  jmp_buf *jbufp;
  struct cleanupentry *cleanups;
  void (*printerror)(const char *emsg, const char *contextstring);
  const char *contextstring;
};

static struct errorcontext *volatile econtext= NULL;
static struct { struct cleanupentry ce; void *args[20]; } emergency;

void set_error_display(void (*printerror)(const char *, const char *),
                       const char *contextstring) {
  assert(econtext);
  econtext->printerror= printerror;
  econtext->contextstring= contextstring;
}

void push_error_handler(jmp_buf *jbufp,
                        void (*printerror)(const char *, const char *),
                        const char *contextstring) {
  struct errorcontext *necp;
  necp= malloc(sizeof(struct errorcontext));
  if (!necp) {
    int e= errno;
    snprintf(errmsgbuf, sizeof(errmsgbuf), "%s%s", 
	    _("out of memory pushing error handler: "), strerror(e));
    errmsg= errmsgbuf;
    if (econtext) longjmp(*econtext->jbufp,1);
    fprintf(stderr, "%s: %s\n", thisname, errmsgbuf); exit(2);
  }
  necp->next= econtext;
  necp->jbufp= jbufp;
  necp->cleanups= NULL;
  necp->printerror= printerror;
  necp->contextstring= contextstring;
  econtext= necp;
  onerr_abort= 0;
}

static void print_error_cleanup(const char *emsg, const char *contextstring) {
  fprintf(stderr, _("%s: error while cleaning up:\n %s\n"),thisname,emsg);
}

static void run_cleanups(struct errorcontext *econ, int flagsetin) {
  static volatile int preventrecurse= 0;
  struct cleanupentry *volatile cep;
  struct cleanupentry *ncep;
  struct errorcontext recurserr, *oldecontext;
  jmp_buf recurejbuf;
  volatile int i, flagset;

  if (econ->printerror) econ->printerror(errmsg,econ->contextstring);
     
  if (++preventrecurse > 3) {
    onerr_abort++;
    fprintf(stderr, _("dpkg: too many nested errors during error recovery !!\n"));
    flagset= 0;
  } else {
    flagset= flagsetin;
  }
  cep= econ->cleanups;
  oldecontext= econtext;
  while (cep) {
    for (i=0; i<NCALLS; i++) {
      if (cep->calls[i].call && cep->calls[i].mask & flagset) {
        if (setjmp(recurejbuf)) {
          run_cleanups(&recurserr, ehflag_bombout | ehflag_recursiveerror);
        } else {
          recurserr.jbufp= &recurejbuf;
          recurserr.cleanups= NULL;
          recurserr.next= NULL;
          recurserr.printerror= print_error_cleanup;
          recurserr.contextstring= NULL;
          econtext= &recurserr;
          cep->calls[i].call(cep->argc,cep->argv);
        }
        econtext= oldecontext;
      }
    }
    flagset &= cep->cpmask;
    flagset |= cep->cpvalue;
    ncep= cep->next;
    if (cep != &emergency.ce) free(cep);
    cep= ncep;
  }
  preventrecurse--;
}

void error_unwind(int flagset) {
  struct cleanupentry *cep;
  struct errorcontext *tecp;

  tecp= econtext;
  cep= tecp->cleanups;
  econtext= tecp->next;
  run_cleanups(tecp,flagset);
  free(tecp);
}

void push_checkpoint(int mask, int value) {
  /* This will arrange that when error_unwind() is called,
   * all previous cleanups will be executed with
   *  flagset= (original_flagset & mask) | value
   * where original_flagset is the argument to error_unwind
   * (as modified by any checkpoint which was pushed later).
   */
  struct cleanupentry *cep;
  int i;
  
  cep= m_malloc(sizeof(struct cleanupentry) + sizeof(char*));
  for (i=0; i<NCALLS; i++) { cep->calls[i].call=NULL; cep->calls[i].mask=0; }
  cep->cpmask= mask; cep->cpvalue= value;
  cep->argc= 0; cep->argv[0]= NULL;
  cep->next= econtext->cleanups;
  econtext->cleanups= cep;
}

void push_cleanup(void (*call1)(int argc, void **argv), int mask1,
                  void (*call2)(int argc, void **argv), int mask2,
                  unsigned int nargs, ...) {
  struct cleanupentry *cep;
  void **args;
  int e;
  va_list al;

  onerr_abort++;
  
  cep= malloc(sizeof(struct cleanupentry) + sizeof(char*)*(nargs+1));
  if (!cep) {
    if (nargs > sizeof(emergency.args)/sizeof(void*))
      ohshite(_("out of memory for new cleanup entry with many arguments"));
    e= errno; cep= &emergency.ce;
  }
  cep->calls[0].call= call1; cep->calls[0].mask= mask1;
  cep->calls[1].call= call2; cep->calls[1].mask= mask2;
  cep->cpmask=~0; cep->cpvalue=0; cep->argc= nargs;
  va_start(al,nargs);
  args= cep->argv; while (nargs-- >0) *args++= va_arg(al,void*);
  *args++= NULL;
  va_end(al);
  cep->next= econtext->cleanups;
  econtext->cleanups= cep;
  if (cep == &emergency.ce) { e= errno; ohshite(_("out of memory for new cleanup entry")); }

  onerr_abort--;
}

void pop_cleanup(int flagset) {
  struct cleanupentry *cep;
  int i;

  cep= econtext->cleanups;
  econtext->cleanups= cep->next;
  for (i=0; i<NCALLS; i++) {
    if (cep->calls[i].call && cep->calls[i].mask & flagset)
      cep->calls[i].call(cep->argc,cep->argv);
  }
  if (cep != &emergency.ce) free(cep);
}

void ohshit(const char *fmt, ...) {
  va_list al;
  va_start(al,fmt);
  vsnprintf(errmsgbuf,sizeof(errmsgbuf),fmt,al);
  va_end(al);
  errmsg= errmsgbuf;
  longjmp(*econtext->jbufp,1);
}

void print_error_fatal(const char *emsg, const char *contextstring) {
  fprintf(stderr, "%s: %s\n",thisname,emsg);
}

void ohshitvb(struct varbuf *vb) {
  char *m;
  varbufaddc(vb,0);
  m= m_malloc(strlen(vb->buf));
  strcpy(m,vb->buf);
  errmsg= m;
  longjmp(*econtext->jbufp,1);
}

void ohshitv(const char *fmt, va_list al) {
  vsnprintf(errmsgbuf,sizeof(errmsgbuf),fmt,al);
  errmsg= errmsgbuf;
  longjmp(*econtext->jbufp,1);
}

void ohshite(const char *fmt, ...) {
  int e;
  va_list al;
  char buf[1024];

  e=errno;
  va_start(al,fmt);
  vsnprintf(buf,sizeof(buf),fmt,al);
  va_end(al);

  snprintf(errmsgbuf,sizeof(errmsgbuf),"%s: %s",buf,strerror(e));
  errmsg= errmsgbuf; 
  longjmp(*econtext->jbufp,1);
}

void warningf(const char *fmt, ...) {
  int e;
  va_list al;
  char buf[1024];

  e=errno;
  va_start(al,fmt);
  vsnprintf(buf,sizeof(buf),fmt,al);
  va_end(al);

  fprintf(stderr,"%s: %s\n",buf,strerror(e));
}

void badusage(const char *fmt, ...) {
  char buf[1024];
  va_list al;
  va_start(al,fmt);
  vsnprintf(buf,sizeof(buf), fmt,al);
  va_end(al);
  snprintf(errmsgbuf,sizeof(errmsgbuf),"%s\n\n%s", buf, gettext(printforhelp));
  errmsg= errmsgbuf; 
  longjmp(*econtext->jbufp,1);
}

void werr(const char *fn) {
  ohshite(_("error writing `%s'"),fn);
}

void do_internerr(const char *string, int line, const char *file) {
  fprintf(stderr,_("%s:%d: internal error `%s'\n"),file,line,string);
  abort();
}


