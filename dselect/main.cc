/*
 * dselect - Debian GNU/Linux package maintenance user interface
 * main.cc - main program
 *
 * Copyright (C) 1994,1995 Ian Jackson <iwj10@cus.cam.ac.uk>
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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <limits.h>
#include <ctype.h>
#include <assert.h>

#include <ncurses.h>
#include <term.h>

extern "C" {
#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
#include "version.h"
#include "myopt.h"
}
#include "dselect.h"
#include "bindings.h"
#include "pkglist.h"

const char thisname[]= DSELECT;
const char printforhelp[]= "Type " DPKG " --help for help.";

modstatdb_rw readwrite;
const char *admindir= ADMINDIR;
FILE *debug;

static keybindings packagelistbindings(packagelist_kinterps,packagelist_korgbindings);

struct menuentry {
  const char *option;
  const char *menuent;
  urqfunction *fn;
};

static const menuentry menuentries[]= {
  { "access",  "Choose the access method to use.",                 &urq_setup   },
  { "update",  "Update list of available packages, if possible.",  &urq_update  },
  { "select",  "Select which packages to install (or deinstall).", &urq_list    },
  { "install", "Install selected software.",                       &urq_install },
  { "config",  "Configure packages that are unconfigured.",        &urq_config  },
  { "remove",  "Remove software selected for deinstallation.",     &urq_remove  },
  { "quit",    "Quit dselect.",                                    &urq_quit    },
  { "menu",     0,                                                 &urq_menu    },
  {  0                                                                          }
};

static const char programdesc[]=
      "Debian GNU/Linux `" DSELECT "' package handling frontend.";

static const char copyrightstring[]=
      "Version " DPKG_VERSION_ARCH ".  Copyright (C) 1994,1995 Ian Jackson.   This is\n"
      "free software; see the GNU General Public Licence version 2 or later for\n"
      "copying conditions.  There is NO warranty.  See dselect --licence for details.\n";

static void printversion(void) {
  if (fprintf(stderr,"%s\n%s",programdesc,copyrightstring) == EOF) werr("stderr");
}

static void usage(void) {
  if (!fputs
      ("Usage: dselect [options]\n"
       "       dselect [options] action ...\n"
       "Options:  --admindir <directory>  (default is /var/lib/dpkg)\n"
       "          --help  --version  --licence   --debug <file> | -D<file> | -D\n"
       "Actions:  access update select install config remove quit menu\n",
       stderr)) werr("stderr");
}

/* These are called by C code, so need to have C calling convention */
extern "C" {

  static void helponly(const struct cmdinfo*, const char*) {
    usage(); exit(0);
  }
  static void versiononly(const struct cmdinfo*, const char*) {
    printversion(); exit(0);
  }

  static void setdebug(const struct cmdinfo*, const char *v) {
    debug= fopen(v,"a");
    if (!debug) ohshite("couldn't open debug file `%.255s'\n",v);
    setvbuf(debug,0,_IONBF,0);
  }

} /* End of extern "C" */

static const struct cmdinfo cmdinfos[]= {
  { "admindir",   0,   1,  0,  &admindir,  0                      },
  { "debug",     'D',  1,  0,  0,          setdebug               },
  { "help",      'h',  0,  0,  0,          helponly               },
  { "version",    0,   0,  0,  0,          versiononly            },
  { "licence",    0,   0,  0,  0,          showcopyright          }, /* UK spelling */
  { "license",    0,   0,  0,  0,          showcopyright          }, /* US spelling */
  {  0,           0                                               }
};

static int cursesareon= 0;
void curseson() {
  if (!cursesareon) {
    const char *cup, *smso;
    initscr();
    cup= tigetstr("cup");
    smso= tigetstr("smso");
    if (!cup || !smso) {
      endwin();
      if (!cup)
        fputs("Terminal does not appear to support cursor addressing.\n",stderr);
      if (!smso)
        fputs("Terminal does not appear to support highlighting.\n",stderr);
      fputs("Set your TERM variable correctly, use a better terminal,\n"
            "or make do with the per-package management tool " DPKG ".\n",stderr);
      ohshit("terminal lacks necessary features, giving up");
    }
  }
  cursesareon= 1;
}

void cursesoff() {
  if (cursesareon) {
    clear();
    refresh();
    endwin();
  }
  cursesareon=0;
}

extern void *operator new(size_t size) {
  void *p;
  p= m_malloc(size);
  assert(p);
  return p;
}

extern void operator delete(void *p) {
  free(p);
}

urqresult urq_list(void) {
  readwrite= modstatdb_init(admindir,
                            msdbrw_writeifposs|msdbrw_availablepreferversion);

  curseson();

  packagelist *l= new packagelist(&packagelistbindings);
  l->resolvesuggest();
  l->display();
  delete l;

  modstatdb_shutdown();
  resetpackages();
  return urqr_normal;
}

void dme(int i, int so) {
  char buf[120];
  const menuentry *me= &menuentries[i];
  sprintf(buf," %c %d. [%c]%-10.10s %-80.80s ",
          so ? '*' : ' ', i,
          toupper(me->option[0]), me->option+1,
          me->menuent);
  
  int y,x;
  getmaxyx(stdscr,y,x);

  attrset(so ? A_REVERSE : A_NORMAL);
  mvaddnstr(i+2,0, buf,x-1);
  attrset(A_NORMAL);
}

int refreshmenu(void) {
  curseson(); cbreak(); noecho(); nonl(); keypad(stdscr,TRUE);

  int y,x;
  getmaxyx(stdscr,y,x);

  clear();
  attrset(A_BOLD);
  mvaddnstr(0,0, programdesc,x-1);

  attrset(A_NORMAL);
  const struct menuentry *mep; int i;
  for (mep=menuentries, i=0; mep->option && mep->menuent; mep++, i++)
    dme(i,0);

  attrset(A_BOLD);
  addstr("\n\n"
         "Use ^P and ^N, cursor keys, initial letters, or digits to select;\n"
         "Press ENTER to confirm selection.   ^L to redraw screen.\n\n");

  attrset(A_NORMAL);
  addstr(copyrightstring);

  return i;
}

urqresult urq_menu(void) {
#define C(x) ((x)-'a'+1)
  int entries, c, i;
  entries= refreshmenu();
  int cursor=0;
  dme(0,1);
  for (;;) {
    refresh();
    c= getch();  if (c==ERR) ohshite("failed to getch in main menu");
    if (c==C('n') || c==KEY_DOWN || c==' ') {
      dme(cursor,0); cursor++; cursor %= entries; dme(cursor,1);
    } else if (c==C('p') || c==KEY_UP || c==C('h') ||
               c==KEY_BACKSPACE || c==KEY_DC) {
      dme(cursor,0); cursor+= entries-1; cursor %= entries; dme(cursor,1);
    } else if (c=='\n' || c=='\r' || c==KEY_ENTER) {
      clear(); refresh();
      switch (menuentries[cursor].fn()) { /* fixme: trap errors in urq_... */
      case urqr_quitmenu:
        return urqr_quitmenu;
      case urqr_normal:
        cursor++; cursor %= entries;
      case urqr_fail:
        break;
      default:
        internerr("unknown menufn");
      }
      refreshmenu(); dme(cursor,1);
    } else if (c==C('l')) {
      clearok(stdscr,TRUE); clear(); refreshmenu(); dme(cursor,1);
    } else if (isdigit(c)) {
      char buf[2]; buf[0]=c; buf[1]=0; c=atoi(buf);
      if (c < entries) {
        dme(cursor,0); cursor=c; dme(cursor,1);
      } else {
        beep();
      }
    } else if (isalpha(c)) {
      c= tolower(c);
      for (i=0; i<entries && menuentries[i].option[0] != c; i++);
      if (i < entries) {
        dme(cursor,0); cursor=i; dme(cursor,1);
      } else {
        beep();
      }
    } else {
      beep();
    }
  }
}

urqresult urq_quit(void) {
  return urqr_quitmenu;
  /* fixme: check packages OK */
}

int main(int, const char *const *argv) {
  jmp_buf ejbuf;

  if (setjmp(ejbuf)) { /* expect warning about possible clobbering of argv */
    cursesoff();
    error_unwind(ehflag_bombout); exit(2);
  }
  push_error_handler(&ejbuf,print_error_fatal,0);

  myopt(&argv,cmdinfos);

  if (*argv) {
    const char *a;
    while ((a= *argv++) != 0) {
      const menuentry *me;
      for (me= menuentries; me->option && strcmp(me->option,a); me++);
      if (!me->option) badusage("unknown action string `%.50s'",a);
      me->fn();
    }
  } else {
    urq_menu();
  }

  cursesoff();
  set_error_display(0,0);
  error_unwind(ehflag_normaltidy);
  return(0);
}
