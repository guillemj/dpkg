/*
 * dselect - Debian GNU/Linux package maintenance user interface
 * pkginfo.cc - handles (re)draw of package list window infopad
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
 * License along with this; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <stdio.h>
#include <string.h>
#include <ncurses.h>
#include <assert.h>
#include <ctype.h>

extern "C" {
#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
}
#include "dselect.h"
#include "bindings.h"
#include "helpmsgs.h"

const struct helpmenuentry *packagelist::helpmenulist() {
  static const struct helpmenuentry
    rw[]= {
      { 'i', &hlp_mainintro       },
      { 'k', &hlp_listkeys        },
      { 'l', &hlp_displayexplain1 },
      { 'd', &hlp_displayexplain2 },
      {  0                        }
    },
    ro[]= {
      { 'i', &hlp_readonlyintro   },
      { 'k', &hlp_listkeys        },
      { 'l', &hlp_displayexplain1 },
      { 'd', &hlp_displayexplain2 },
      {  0                        }
    },
    recur[]= {
      { 'i', &hlp_recurintro      },
      { 'k', &hlp_listkeys        },
      { 'l', &hlp_displayexplain1 },
      { 'd', &hlp_displayexplain2 },
      {  0                        }
    };
  return
    !readwrite ? ro :
    !recursive ? rw :
                 recur;
}

int packagelist::itr_recursive() { return recursive; }

const packagelist::infotype packagelist::infoinfos[]= {
  { itr_recursive,     itd_relations    },
  { 0,                 itd_description  },
  { 0,                 itd_controlfile  },
  { 0,                 0                }
};

const packagelist::infotype *const packagelist::baseinfo= infoinfos;

void packagelist::severalinfoblurb(const char *whatinfoline) {
  whatinfovb(whatinfoline);
  varbuf vb;
  vb("The line you have highlighted represents many packages; "
     "if you ask to select or deselect it you will affect all the "
     "packages which match the criterion shown.\n"
     "\n"
     "If you move the highlight to a line for a particular package "
     "you will see information about that package displayed here.");
  wordwrapinfo(0,vb.string());
}

void packagelist::itd_relations() {
  if (table[cursorline]->pkg->name) {
    whatinfovb("interrelationships affecting ");
    whatinfovb(table[cursorline]->pkg->name);
    if (debug) fprintf(debug,"packagelist[%p]::idt_relations(); `%s'\n",
                       this,table[cursorline]->relations.string());
    waddstr(infopad,table[cursorline]->relations.string());
  } else {
    severalinfoblurb("interrelationships");
  }
}

void packagelist::itd_description() {
  if (table[cursorline]->pkg->name) {
    whatinfovb("description of ");
    whatinfovb(table[cursorline]->pkg->name);

    const char *m= table[cursorline]->pkg->available.description;
    if (!m || !*m) m= "no description available.";
    const char *p= strchr(m,'\n');
    int l= p ? (int)(p-m) : strlen(m);
    wattrset(infopad,info_headattr);
    waddstr(infopad, table[cursorline]->pkg->name);
    waddstr(infopad," - ");
    waddnstr(infopad,m,l);
    wattrset(infopad,info_attr);
    if (p) {
      waddstr(infopad,"\n\n");
      wordwrapinfo(1,++p);
    }
  } else {
    severalinfoblurb("description");
  }
}

void packagelist::itd_controlfile() {
  werase(infopad);
  if (!table[cursorline]->pkg->name) {
    severalinfoblurb("control file information");
  } else {
    whatinfovb("control file information for ");
    whatinfovb(table[cursorline]->pkg->name);
    varbuf vb;
    varbufrecord(&vb,table[cursorline]->pkg,&table[cursorline]->pkg->available);
    vb.terminate();
    if (debug)
      fprintf(debug,"packagelist[%p]::idt_controlfile(); `%s'\n",this,vb.string());
    waddstr(infopad,vb.string());
  }
}

void packagelist::redrawinfo() {
  for (;;) {
    if (!currentinfo || !currentinfo->display) currentinfo= baseinfo;
    if (!currentinfo->relevant) break;
    if ((this->*currentinfo->relevant)()) break;
    currentinfo++;
  }
  if (!info_height) return;
  whatinfovb.reset();
  werase(infopad); wmove(infopad,0,0);
  
  if (debug)
    fprintf(debug,"packagelist[%p]::redrawinfo(); #=%d\n", this,
            (int)(currentinfo - baseinfo));
  
  (this->*currentinfo->display)();
  whatinfovb.terminate();
  int y,x;
  getyx(infopad, y,x);
  if (x) y++;
  infolines= y;

  refreshinfo();
}
