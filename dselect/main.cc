/*
 * dselect - Debian package maintenance user interface
 * main.cc - main program
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
extern "C" {
#include <config.h>
}

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <limits.h>
#include <ctype.h>
#include <assert.h>

#include <term.h>

extern "C" {
#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>
}
#include "dselect.h"
#include "bindings.h"
#include "pkglist.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

const char thisname[]= DSELECT;
const char printforhelp[]= N_("Type dselect --help for help.");

modstatdb_rw readwrite;
const char *admindir= ADMINDIR;
FILE *debug;
int expertmode= 0;

static keybindings packagelistbindings(packagelist_kinterps,packagelist_korgbindings);

struct table_t {
  const char *name;
  const int num;
};

static const struct table_t colourtable[]= {
  {"black",	COLOR_BLACK	},
  {"red",	COLOR_RED	},
  {"green",	COLOR_GREEN	},
  {"yellow",	COLOR_YELLOW	},
  {"blue",	COLOR_BLUE	},
  {"magenta",	COLOR_MAGENTA	},
  {"cyan",	COLOR_CYAN	},
  {"white",	COLOR_WHITE	},
  {NULL, 0},
};

static const struct table_t attrtable[]= {
  {"normal",	A_NORMAL	},
  {"standout",	A_STANDOUT	},
  {"underline",	A_UNDERLINE	},
  {"reverse",	A_REVERSE	},
  {"blink",	A_BLINK		},
  {"bright",	A_BLINK		}, // on some terminals
  {"dim",	A_DIM		},
  {"bold",	A_BOLD		},
  {NULL, 0},
};

/* A slightly confusing mapping from dselect's internal names to
 * the user-visible names.*/
static const struct table_t screenparttable[]= {
  {"list",		list		},
  {"listsel",		listsel		},
  {"title",		title		},
  {"infohead",		thisstate	},
  {"pkgstate",		selstate	},
  {"pkgstatesel",	selstatesel	},
  {"listhead",		colheads	},
  {"query",		query		},
  {"info",		info		},
  {"infodesc",		info_head	},
  {"infofoot",		whatinfo	},
  {"helpscreen",	helpscreen	},
  {NULL, 0},
};

/* Historical (patriotic?) colours. */
struct colordata color[]= {
  /* fore      back            attr */
  {COLOR_WHITE,        COLOR_BLACK,    0			}, // default, not used
  {COLOR_WHITE,        COLOR_BLACK,    0			}, // list
  {COLOR_WHITE,        COLOR_BLACK,    A_REVERSE		}, // listsel
  {COLOR_WHITE,        COLOR_RED,      0			}, // title
  {COLOR_WHITE,        COLOR_BLUE,     0			}, // thisstate
  {COLOR_WHITE,        COLOR_BLACK,    A_BOLD			}, // selstate
  {COLOR_WHITE,        COLOR_BLACK,    A_REVERSE | A_BOLD	}, // selstatesel
  {COLOR_WHITE,        COLOR_BLUE,     0			}, // colheads
  {COLOR_WHITE,        COLOR_RED,      0			}, // query
  {COLOR_WHITE,        COLOR_BLACK,    0			}, // info
  {COLOR_WHITE,        COLOR_BLACK,    A_BOLD			}, // info_head
  {COLOR_WHITE,        COLOR_BLUE,     0			}, // whatinfo
  {COLOR_WHITE,        COLOR_BLACK,    0			}, // help
};

struct menuentry {
  const char *command;
  const char *key;
  const char *option;
  const char *menuent;
  urqfunction *fn;
};

static const menuentry menuentries[]= {
  { "access",	N_("a"),	N_("[A]ccess"),	N_("Choose the access method to use."),			&urq_setup   },
  { "update",	N_("u"),	N_("[U]pdate"),	N_("Update list of available packages, if possible."),	&urq_update  },
  { "select",	N_("s"),	N_("[S]elect"),	N_("Request which packages you want on your system."),	&urq_list    },
  { "install",	N_("i"),	N_("[I]nstall"),N_("Install and upgrade wanted packages."),		&urq_install },
  { "config",	N_("c"),	N_("[C]onfig"),	N_("Configure any packages that are unconfigured."),	&urq_config  },
  { "remove",	N_("r"),	N_("[R]emove"),	N_("Remove unwanted software."),			&urq_remove  },
  { "quit",	N_("q"),	N_("[Q]uit"),	N_("Quit dselect."),					&urq_quit    },
  { 0,		0,  		N_("menu"),	0,							&urq_menu    },
  { 0 }
};

static const char programdesc[]=
      N_("Debian `%s' package handling frontend.");

static const char copyrightstring[]= N_(
      "Version %s.\n"
      "Copyright (C) 1994-1996 Ian Jackson.\n"
      "Copyright (C) 2000,2001 Wichert Akkerman.\n"
      "This is free software; see the GNU General Public Licence version 2\n"
      "or later for copying conditions.  There is NO warranty.  See\n"
      "dselect --licence for details.\n");

static void printversion(void) {
  if (fprintf(stdout,gettext(programdesc),DSELECT) == EOF) werr("stdout");
  if (fprintf(stdout,"\n") == EOF) werr("stdout");
  if (fprintf(stdout,gettext(copyrightstring), DPKG_VERSION_ARCH) == EOF) werr("stdout");
}

static void usage(void) {
  int i;
  if (!fputs(
     _("Usage: dselect [options]\n"
       "       dselect [options] action ...\n"
       "Options:  --admindir <directory>  (default is /var/lib/dpkg)\n"
       "          --help  --version  --licence  --expert  --debug <file> | -D<file>\n"
       "          --colour screenpart:[foreground],[background][:attr[+attr+..]]\n"
       "Actions:  access update select install config remove quit\n"),
       stdout)) werr("stdout");

  printf(_("Screenparts:\n"));
  for (i=0; screenparttable[i].name; i++)
    printf("  %s", screenparttable[i].name);
  if (!fputs("\n", stdout)) werr("stdout");

  printf(_("Colours:\n"));
  for (i=0; colourtable[i].name; i++)
    printf("  %s", colourtable[i].name);
  if (!fputs("\n", stdout)) werr("stdout");

  printf(_("Attributes:\n"));
  for (i=0; attrtable[i].name; i++)
    printf("  %s", attrtable[i].name);
  if (!fputs("\n", stdout)) werr("stdout");
}

/* These are called by C code, so need to have C calling convention */
extern "C" {

  static void helponly(const struct cmdinfo*, const char*) NONRETURNING;
  static void helponly(const struct cmdinfo*, const char*) {
    usage(); exit(0);
  }
  static void versiononly(const struct cmdinfo*, const char*) NONRETURNING;
  static void versiononly(const struct cmdinfo*, const char*) {
    printversion(); exit(0);
  }

  static void setdebug(const struct cmdinfo*, const char *v) {
    debug= fopen(v,"a");
    if (!debug) ohshite(_("couldn't open debug file `%.255s'\n"),v);
    setvbuf(debug,0,_IONBF,0);
  }

  static void setexpert(const struct cmdinfo*, const char *v) {
    expertmode= 1;
  }

  int findintable(const struct table_t *table, const char *item, const char *tablename) {
    int i;

    for (i= 0;  item && (table[i].name!=NULL); i++)
      if (strcasecmp(item, table[i].name) == 0)
        return table[i].num;

    ohshit(_("Invalid %s `%s'\n"), tablename, item);
  }

  /*
   *  The string's format is:
   *    screenpart:[forecolor][,backcolor][:[<attr>, ...]
   *  Examples: --color title:black,cyan:bright+underline
   *            --color list:red,yellow
   *            --color colheads:,green:bright
   *            --color selstate::reverse  // doesn't work FIXME
   */
  static void setcolor(const struct cmdinfo*, const char *string) {
    char *s= (char *) malloc((strlen(string) + 1) * sizeof(char));
    char *colours, *attributes, *attrib, *colourname;
    int screenpart, aval;

    strcpy(s, string); // strtok modifies strings, keep string const
    screenpart= findintable(screenparttable, strtok(s, ":"), _("screen part"));
    colours= strtok(NULL, ":");
    attributes= strtok(NULL, ":");

    if ((colours == NULL || ! strlen(colours)) &&
        (attributes == NULL || ! strlen(attributes))) {
       ohshit(_("Null colour specification\n"));
    }

    if (colours != NULL && strlen(colours)) {
      colourname= strtok(colours, ",");
      if (colourname != NULL && strlen(colourname)) {
        // normalize attributes to prevent confusion
        color[screenpart].attr= A_NORMAL;
       color[screenpart].fore=findintable(colourtable, colourname, _("colour"));
      }
      colourname= strtok(NULL, ",");
      if (colourname != NULL && strlen(colourname)) {
        color[screenpart].attr= A_NORMAL;
        color[screenpart].back=findintable(colourtable, colourname, _("colour"));
      }
    }

    if (attributes != NULL && strlen(attributes)) {
      for (attrib= strtok(attributes, "+");
           attrib != NULL && strlen(attrib);
          attrib= strtok(NULL, "+")) {
               aval=findintable(attrtable, attrib, _("colour attribute"));
               if (aval == A_NORMAL) // set to normal
                       color[screenpart].attr= aval;
               else // add to existing attribs
                       color[screenpart].attr= color[screenpart].attr | aval;
      }
    }
  }

} /* End of extern "C" */

static const struct cmdinfo cmdinfos[]= {
  { "admindir",     0,   1,  0,  &admindir,  0               },
  { "debug",       'D',  1,  0,  0,          setdebug        },
  { "expert",      'E',  0,  0,  0,          setexpert       },
  { "help",        'h',  0,  0,  0,          helponly        },
  { "version",      0,   0,  0,  0,          versiononly     },
  { "licence",      0,   0,  0,  0,          showcopyright   }, /* UK spelling */
  { "license",      0,   0,  0,  0,          showcopyright   }, /* US spelling */
  { "color",        0,   1,  0,  0,          setcolor        }, /* US spelling */
  { "colour",       0,   1,  0,  0,          setcolor        }, /* UK spelling */
  { 0,              0,   0,  0,  0,          0               }
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
        fputs(_("Terminal does not appear to support cursor addressing.\n"),stderr);
      if (!smso)
        fputs(_("Terminal does not appear to support highlighting.\n"),stderr);
      fputs(_("Set your TERM variable correctly, use a better terminal,\n"
            "or make do with the per-package management tool "),stderr);
      fputs(DPKG ".\n",stderr);
      ohshit(_("terminal lacks necessary features, giving up"));
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
  readwrite= modstatdb_init(admindir,msdbrw_writeifposs);

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
  sprintf(buf," %c %d. %-11.11s %-80.80s ",
          so ? '*' : ' ', i,
          gettext(me->option),
          gettext(me->menuent));
  
  int y,x;
  getmaxyx(stdscr,y,x);

  attrset(so ? A_REVERSE : A_NORMAL);
  mvaddnstr(i+2,0, buf,x-1);
  attrset(A_NORMAL);
}

int refreshmenu(void) {
  char buf[2048];
  static int l,lockfd;
  static char *lockfile;

  curseson(); cbreak(); noecho(); nonl(); keypad(stdscr,TRUE);

  int y,x;
  getmaxyx(stdscr,y,x);

  clear();
  attrset(A_BOLD);
  sprintf(buf,gettext(programdesc),DSELECT);
  mvaddnstr(0,0,buf,x-1);

  attrset(A_NORMAL);
  const struct menuentry *mep; int i;
  for (mep=menuentries, i=0; mep->option && mep->menuent; mep++, i++)
    dme(i,0);

  attrset(A_BOLD);
  addstr(_("\n\n"
         "Move around with ^P and ^N, cursor keys, initial letters, or digits;\n"
         "Press <enter> to confirm selection.   ^L redraws screen.\n\n"));

  attrset(A_NORMAL);
  sprintf(buf,gettext(copyrightstring),DPKG_VERSION_ARCH);
  addstr(buf);

  l= strlen(admindir);
  lockfile= new char[l+sizeof(LOCKFILE)+2];
  strcpy(lockfile,admindir);
  strcpy(lockfile+l, "/" LOCKFILE);
  lockfd= open(lockfile, O_RDWR|O_CREAT|O_TRUNC, 0660);
  if (errno == EACCES || errno == EPERM)
    addstr(_("\n\n"
             "Read-only access: only preview of selections is available!"));

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
    do
      c= getch();
    while (c == ERR && errno == EINTR);
    if (c==ERR)  {
      if(errno != 0)
        ohshite(_("failed to getch in main menu"));
      else {
        clearok(stdscr,TRUE); clear(); refreshmenu(); dme(cursor,1); 
      }
    }

    if (c==C('n') || c==KEY_DOWN || c==' ' || c=='j') {
      dme(cursor,0); cursor++; cursor %= entries; dme(cursor,1);
    } else if (c==C('p') || c==KEY_UP || c==C('h') ||
               c==KEY_BACKSPACE || c==KEY_DC || c=='k') {
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
      for (i=0; i<entries && gettext(menuentries[i].key)[0] != c; i++);
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

  setlocale(LC_ALL, "");
  bindtextdomain(PACKAGE, LOCALEDIR);
  textdomain(PACKAGE);

  if (setjmp(ejbuf)) { /* expect warning about possible clobbering of argv */
    cursesoff();
    error_unwind(ehflag_bombout); exit(2);
  }
  push_error_handler(&ejbuf,print_error_fatal,0);

  loadcfgfile(DSELECT, cmdinfos);
  myopt(&argv,cmdinfos);

  if (*argv) {
    const char *a;
    while ((a= *argv++) != 0) {
      const menuentry *me;
      for (me= menuentries; me->command && strcmp(me->command,a); me++);
      if (!me->command) badusage(_("unknown action string `%.50s'"),a);
      me->fn();
    }
  } else {
    urq_menu();
  }

  cursesoff();
  standard_shutdown(0);
  return(0);
}

