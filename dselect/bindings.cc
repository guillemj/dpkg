/*
 * dselect - Debian package maintenance user interface
 * bindings.cc - keybinding manager object definitions and default bindings
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
extern "C" {
#include <config.h>
}

#include <stdio.h>
#include <string.h>
#include <assert.h>

extern "C" {
#include <dpkg.h>
#include <dpkg-db.h>
}
#include "dselect.h"
#include "bindings.h"

keybindings::keybindings(const interpretation *ints, const orgbinding *orgbindings) {
  interps= ints;
  bindings=0;
  const orgbinding *b= orgbindings;
  while (b->action) { bind(b->key,b->action); b++; }
  describestart();
}

int keybindings::bind(int key, const char *action) {
  if (key == -1) return 0;
  
  const interpretation *interp;
  for (interp=interps; interp->action && strcmp(interp->action,action); interp++);
  if (!interp->action) return 0;
  
  const description *desc;
  for (desc=descriptions; desc->action && strcmp(desc->action,action); desc++);

  binding *bind;
  for (bind=bindings; bind && bind->key != key; bind=bind->next);
  
  if (!bind) {
    bind= new binding;
    bind->key= key;
    bind->next= bindings;
    bindings= bind;
  }
  bind->interp= interp;
  bind->desc= desc ? desc->desc : 0;
  return 1;
}

const char *keybindings::find(const char *action) {
  binding *b;
  for (b=bindings; b && strcmp(action,b->interp->action); b=b->next);
  if (!b) return _("[not bound]");
  const char *n= key2name(b->key);
  if (n) return n;
  static char buf[50];
  sprintf(buf,_("[unk: %d]"),b->key);
  return buf;
}

const keybindings::interpretation *keybindings::operator()(int key) {
  binding *b;
  for (b=bindings; b && b->key != key; b=b->next);
  if (!b) return 0;
  return b->interp;
}

const char **keybindings::describenext() {
  binding *search;
  int count;
  for (;;) {
    if (!iterate->action) return 0;
    for (count=0, search=bindings; search; search=search->next)
      if (!strcmp(search->interp->action,iterate->action))
        count++;
    if (count) break;
    iterate++;
  }
  const char **retarray= new const char *[count+2];
  retarray[0]= iterate->desc;
  for (count=1, search=bindings; search; search=search->next)
    if (!strcmp(search->interp->action,iterate->action))
      retarray[count++]= key2name(search->key);
  retarray[count]= 0;
  iterate++;
  return retarray;
}

const char *keybindings::key2name(int key) {
  const keyname *search;
  for (search=keynames; search->key != -1 && search->key != key; search++);
  return search->kname;
}

int keybindings::name2key(const char *name) {
  const keyname *search;
  for (search=keynames; search->kname && strcasecmp(search->kname,name); search++);
  return search->key;
}

keybindings::~keybindings() {
  binding *search, *next;
  for (search=bindings; search; search=next) {
    next= search->next;
    delete search;
  }
}

const keybindings::description keybindings::descriptions[]= {
  // Actions which apply to both types of list.
  { "iscrollon",       N_("Scroll onwards through help/information")             },
  { "iscrollback",     N_("Scroll backwards through help/information")           },
  { "up",              N_("Move up")                                             },
  { "down",            N_("Move down")                                           },
  { "top",             N_("Go to top of list")                                   },
  { "bottom",          N_("Go to end of list")                                   },
  { "help",            N_("Request help (cycle through help screens)")           },
  { "info",            N_("Cycle through information displays")                  },
  { "redraw",          N_("Redraw display")                                      },
  { "scrollon1",       N_("Scroll onwards through list by 1 line")               },
  { "scrollback1",     N_("Scroll backwards through list by 1 line")             },
  { "iscrollon1",      N_("Scroll onwards through help/information by 1 line")   },
  { "iscrollback1",    N_("Scroll backwards through help/information by 1 line") },
  { "scrollon",        N_("Scroll onwards through list")                         },
  { "scrollback",      N_("Scroll backwards through list")                       },

  // Actions which apply only to lists of packages.
  { "install",         N_("Mark package(s) for installation")                    },
  { "remove",          N_("Mark package(s) for deinstallation")                  },
  { "purge",           N_("Mark package(s) for deinstall and purge")             },
  { "morespecific",    N_("Make highlight more specific")                        },
  { "lessspecific",    N_("Make highlight less specific")                        },
  { "search",          N_("Search for a package whose name contains a string")   },
  { "searchagain",     N_("Repeat last search.")                                 },
  { "swaporder",       N_("Swap sort order priority/section")                    },
  { "quitcheck",       N_("Quit, confirming, and checking dependencies")         },
  { "quitnocheck",     N_("Quit, confirming without check")                      },
  { "quitrejectsug",   N_("Quit, rejecting conflict/dependency suggestions")     },
  { "abortnocheck",    N_("Abort - quit without making changes")                 },
  { "revert",          N_("Revert to old state for all packages")                },
  { "revertsuggest",   N_("Revert to suggested state for all packages")          },
  { "revertdirect",    N_("Revert to directly requested state for all packages") },
  
  // Actions which apply only to lists of methods.
  { "select-and-quit", N_("Select currently-highlighted access method")          },
  { "abort",           N_("Quit without changing selected access method")        },
  {  0,                0                                                         }
};
