/* -*- c++ -*-
 * dselect - selection of Debian packages
 * bindings.h - keybindings class header file
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

#ifndef BINDINGS_H
#define BINDINGS_H

enum quitaction;

struct keybindings {
  struct interpretation;

  struct orgbinding {
    int key;
    const char *action;
  };
  
  struct keyname {
    int key;
    const char *kname;
  };
  
  struct description {
    const char *action, *desc;
  };

  struct binding {
    binding *next;
    int key;
    const struct interpretation *interp;
    const char *desc;
  };
  
 private:
  static const keyname keynames[];
  static const description descriptions[];

  binding *bindings;
  const description *iterate;
  const interpretation *interps;
  
  int bind(int key, const char *action);
  
 public:
  int name2key(const char *name);
  const char *key2name(int key);
  
  int bind(const char *name, const char *action) { return bind(name2key(name),action); }
  const interpretation *operator()(int key);
  const char *find(const char *action);

  void describestart() { iterate=descriptions; }
  const char **describenext();
  //... returns array, null-term, first element is description, rest are key strings
  // caller must delete[] the array.  Null means end.

  keybindings(const interpretation *ints, const orgbinding *orgbindings);
  ~keybindings();
};

#include "pkglist.h"
#include "method.h"

struct keybindings::interpretation {
  const char *action;
  void (methodlist::*mfn)();
  void (packagelist::*pfn)();
  quitaction qa;
};

extern const keybindings::interpretation packagelist_kinterps[];
extern const keybindings::orgbinding packagelist_korgbindings[];

extern const keybindings::interpretation methodlist_kinterps[];
extern const keybindings::orgbinding methodlist_korgbindings[];

#endif /* BINDINGS_H */
