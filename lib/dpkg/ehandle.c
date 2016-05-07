/*
 * libdpkg - Debian packaging suite library routines
 * ehandle.c - error handling
 *
 * Copyright © 1994,1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2008-2014 Guillem Jover <guillem@debian.org>
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

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/progname.h>
#include <dpkg/color.h>
#include <dpkg/ehandle.h>

/* 6x255 for inserted strings (%.255s &c in fmt; and %s with limited length arg)
 * 1x255 for constant text
 * 1x255 for strerror()
 * same again just in case. */
static char errmsg[4096];

/* Incremented when we do some kind of generally necessary operation,
 * so that loops &c know to quit if we take an error exit. Decremented
 * again afterwards. */
volatile int onerr_abort = 0;

#define NCALLS 2

struct cleanup_entry {
  struct cleanup_entry *next;
  struct {
    int mask;
    void (*call)(int argc, void **argv);
  } calls[NCALLS];
  int cpmask, cpvalue;
  int argc;
  void *argv[1];
};

struct error_context {
  struct error_context *next;

  enum {
    HANDLER_TYPE_FUNC,
    HANDLER_TYPE_JUMP,
  } handler_type;

  union {
    error_handler_func *func;
    jmp_buf *jump;
  } handler;

  struct {
    error_printer_func *func;
    const void *data;
  } printer;

  struct cleanup_entry *cleanups;
};

static struct error_context *volatile econtext = NULL;
static struct {
  struct cleanup_entry ce;
  void *args[20];
} emergency;

/**
 * Default fatal error handler.
 *
 * This handler performs all error unwinding for the current context, and
 * terminates the program with an error exit code.
 */
void
catch_fatal_error(void)
{
  pop_error_context(ehflag_bombout);
  exit(2);
}

void
print_fatal_error(const char *emsg, const void *data)
{
  fprintf(stderr, "%s%s:%s %s%s:%s %s\n",
          color_get(COLOR_PROG), dpkg_get_progname(), color_reset(),
          color_get(COLOR_ERROR), _("error"), color_reset(), emsg);
}

static struct error_context *
error_context_new(void)
{
  struct error_context *necp;

  necp = malloc(sizeof(struct error_context));
  if (!necp)
    ohshite(_("out of memory for new error context"));
  necp->next= econtext;
  necp->cleanups= NULL;
  econtext= necp;

  return necp;
}

static void
set_error_printer(struct error_context *ec, error_printer_func *func,
                  const void *data)
{
  ec->printer.func = func;
  ec->printer.data = data;
}

static void
set_func_handler(struct error_context *ec, error_handler_func *func)
{
  ec->handler_type = HANDLER_TYPE_FUNC;
  ec->handler.func = func;
}

static void
set_jump_handler(struct error_context *ec, jmp_buf *jump)
{
  ec->handler_type = HANDLER_TYPE_JUMP;
  ec->handler.jump = jump;
}

void
push_error_context_func(error_handler_func *handler,
                        error_printer_func *printer,
                        const void *printer_data)
{
  struct error_context *ec;

  ec = error_context_new();
  set_error_printer(ec, printer, printer_data);
  set_func_handler(ec, handler);
  onerr_abort = 0;
}

void
push_error_context_jump(jmp_buf *jumper,
                        error_printer_func *printer,
                        const void *printer_data)
{
  struct error_context *ec;

  ec = error_context_new();
  set_error_printer(ec, printer, printer_data);
  set_jump_handler(ec, jumper);
  onerr_abort = 0;
}

void
push_error_context(void)
{
  push_error_context_func(catch_fatal_error, print_fatal_error, NULL);
}

static void
print_cleanup_error(const char *emsg, const void *data)
{
  fprintf(stderr, _("%s: error while cleaning up:\n %s\n"),
          dpkg_get_progname(), emsg);
}

static void
run_cleanups(struct error_context *econ, int flagsetin)
{
  static volatile int preventrecurse= 0;
  struct cleanup_entry *volatile cep;
  struct cleanup_entry *ncep;
  struct error_context recurserr, *oldecontext;
  jmp_buf recurse_jump;
  volatile int i, flagset;

  if (econ->printer.func)
    econ->printer.func(errmsg, econ->printer.data);

  if (++preventrecurse > 3) {
    onerr_abort++;
    fprintf(stderr, _("%s: too many nested errors during error recovery!!\n"),
            dpkg_get_progname());
    flagset= 0;
  } else {
    flagset= flagsetin;
  }
  cep= econ->cleanups;
  oldecontext= econtext;
  while (cep) {
    for (i=0; i<NCALLS; i++) {
      if (cep->calls[i].call && cep->calls[i].mask & flagset) {
        if (setjmp(recurse_jump)) {
          run_cleanups(&recurserr, ehflag_bombout | ehflag_recursiveerror);
        } else {
          recurserr.cleanups= NULL;
          recurserr.next= NULL;
          set_error_printer(&recurserr, print_cleanup_error, NULL);
          set_jump_handler(&recurserr, &recurse_jump);
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

/**
 * Push an error cleanup checkpoint.
 *
 * This will arrange that when pop_error_context() is called, all previous
 * cleanups will be executed with
 *   flagset = (original_flagset & mask) | value
 * where original_flagset is the argument to pop_error_context() (as
 * modified by any checkpoint which was pushed later).
 */
void push_checkpoint(int mask, int value) {
  struct cleanup_entry *cep;
  int i;

  cep = malloc(sizeof(struct cleanup_entry) + sizeof(char *));
  if (cep == NULL) {
    onerr_abort++;
    ohshite(_("out of memory for new cleanup entry"));
  }

  for (i=0; i<NCALLS; i++) { cep->calls[i].call=NULL; cep->calls[i].mask=0; }
  cep->cpmask= mask; cep->cpvalue= value;
  cep->argc= 0; cep->argv[0]= NULL;
  cep->next= econtext->cleanups;
  econtext->cleanups= cep;
}

void push_cleanup(void (*call1)(int argc, void **argv), int mask1,
                  void (*call2)(int argc, void **argv), int mask2,
                  unsigned int nargs, ...) {
  struct cleanup_entry *cep;
  void **argv;
  int e = 0;
  va_list args;

  onerr_abort++;

  cep = malloc(sizeof(struct cleanup_entry) + sizeof(char *) * (nargs + 1));
  if (!cep) {
    if (nargs > array_count(emergency.args))
      ohshite(_("out of memory for new cleanup entry with many arguments"));
    e= errno; cep= &emergency.ce;
  }
  cep->calls[0].call= call1; cep->calls[0].mask= mask1;
  cep->calls[1].call= call2; cep->calls[1].mask= mask2;
  cep->cpmask=~0; cep->cpvalue=0; cep->argc= nargs;
  va_start(args, nargs);
  argv = cep->argv;
  while (nargs-- > 0)
    *argv++ = va_arg(args, void *);
  *argv++ = NULL;
  va_end(args);
  cep->next= econtext->cleanups;
  econtext->cleanups= cep;
  if (cep == &emergency.ce) {
    errno = e;
    ohshite(_("out of memory for new cleanup entry"));
  }

  onerr_abort--;
}

void pop_cleanup(int flagset) {
  struct cleanup_entry *cep;
  int i;

  cep= econtext->cleanups;
  econtext->cleanups= cep->next;
  for (i=0; i<NCALLS; i++) {
    if (cep->calls[i].call && cep->calls[i].mask & flagset)
      cep->calls[i].call(cep->argc,cep->argv);
  }
  if (cep != &emergency.ce) free(cep);
}

/**
 * Unwind the current error context by running its registered cleanups.
 */
void
pop_error_context(int flagset)
{
  struct error_context *tecp;

  tecp = econtext;
  econtext = tecp->next;

  /* If we are cleaning up normally, do not print anything. */
  if (flagset & ehflag_normaltidy)
    set_error_printer(tecp, NULL, NULL);
  run_cleanups(tecp, flagset);
  free(tecp);
}

static void DPKG_ATTR_NORET
run_error_handler(void)
{
  if (onerr_abort) {
    /* We arrived here due to a fatal error from which we cannot recover,
     * and trying to do so would most probably get us here again. That's
     * why we will not try to do any error unwinding either. We'll just
     * abort. Hopefully the user can fix the situation (out of disk, out
     * of memory, etc). */
    fprintf(stderr, _("%s: unrecoverable fatal error, aborting:\n %s\n"),
            dpkg_get_progname(), errmsg);
    exit(2);
  }

  if (econtext == NULL) {
    fprintf(stderr, _("%s: outside error context, aborting:\n %s\n"),
            dpkg_get_progname(), errmsg);
    exit(2);
  } else if (econtext->handler_type == HANDLER_TYPE_FUNC) {
    econtext->handler.func();
    internerr("error handler returned unexpectedly!");
  } else if (econtext->handler_type == HANDLER_TYPE_JUMP) {
    longjmp(*econtext->handler.jump, 1);
  } else {
    internerr("unknown error handler type %d!", econtext->handler_type);
  }
}

void ohshit(const char *fmt, ...) {
  va_list args;

  va_start(args, fmt);
  vsnprintf(errmsg, sizeof(errmsg), fmt, args);
  va_end(args);

  run_error_handler();
}

void
ohshitv(const char *fmt, va_list args)
{
  vsnprintf(errmsg, sizeof(errmsg), fmt, args);

  run_error_handler();
}

void ohshite(const char *fmt, ...) {
  int e;
  va_list args;
  char buf[1024];

  e=errno;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);

  snprintf(errmsg, sizeof(errmsg), "%s: %s", buf, strerror(e));

  run_error_handler();
}

void
do_internerr(const char *file, int line, const char *func, const char *fmt, ...)
{
  va_list args;
  char buf[1024];

  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);

  fprintf(stderr, "%s%s:%s:%d:%s:%s %s%s:%s %s\n", color_get(COLOR_PROG),
          dpkg_get_progname(), file, line, func, color_reset(),
          color_get(COLOR_ERROR), _("internal error"), color_reset(), buf);

  abort();
}
