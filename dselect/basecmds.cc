/*
 * dselect - Debian GNU/Linux package maintenance user interface
 * bcommands.cc - base list keyboard commands display
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
 * License along with this; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <stdio.h>
#include <string.h>
#include <assert.h>

extern "C" {
#include <config.h>
#include <dpkg.h>
#include <dpkg-db.h>
}
#include "dselect.h"
#include "helpmsgs.h"

void baselist::kd_scrollon() {
  topofscreen += list_height;
  if (topofscreen > nitems - list_height) topofscreen= nitems - list_height;
  if (topofscreen < 0) topofscreen= 0;
  if (cursorline < topofscreen)
    setcursor(topofscreen);
  refreshlist();
}

void baselist::kd_scrollon1() {
  if (topofscreen >= nitems - list_height) return;
  topofscreen++;
  if (cursorline < topofscreen)
    setcursor(topofscreen);
  refreshlist();
}

void baselist::kd_scrollback() {
  topofscreen -= list_height;
  if (topofscreen < 0) topofscreen= 0;
  if (cursorline >= topofscreen + list_height)
    setcursor(topofscreen + list_height - 1);
  refreshlist();
}

void baselist::kd_scrollback1() {
  if (topofscreen <= 0) return;
  topofscreen--;
  if (cursorline >= topofscreen + list_height)
    setcursor(topofscreen + list_height - 1);
  refreshlist();
}

void baselist::kd_top() {
  topofscreen= 0; setcursor(0);
}

void baselist::kd_bottom() {
  topofscreen= nitems - list_height;
  if (topofscreen < 0) topofscreen= 0;
  setcursor(lesserint(topofscreen + list_height - 1, nitems-1));
}

void baselist::kd_redraw() {
//#define RFSH(x) werase(x); redrawwin(x)
//  RFSH(listpad);
//  RFSH(infopad); 
//  RFSH(colheadspad); 
//  RFSH(thisstatepad); 
//  RFSH(titlewin); 
//  RFSH(whatinfowin); /* fixme-ncurses: why does ncurses need this ? */
  clearok(curscr,TRUE);
  redrawall();
  if (debug) fprintf(debug,"baselist[%p]::kd_redraw() done\n",this);
}

void baselist::kd_searchagain() {
  if (!searchstring[0]) { beep(); return; }
  dosearch();
}

void baselist::kd_search() {
  char newsearchstring[50];
  strcpy(newsearchstring,searchstring);
  werase(querywin);
  mvwaddstr(querywin,0,0, _("Search for ? "));
  echo(); /* fixme: ncurses documentation or implementation */
  /* fixme: make / RET do `search again' and / DEL to abort */
  if (wgetnstr(querywin,newsearchstring,sizeof(newsearchstring)-1) == ERR)
    searchstring[0]= 0;
  raise(SIGWINCH); /* fixme: ncurses and xterm arrow keys */
  noecho(); /* fixme: ncurses */
  if (whatinfo_height) { touchwin(whatinfowin); refreshinfo(); }
  else if (info_height) { touchwin(infopad); refreshinfo(); }
  else if (thisstate_height) redrawthisstate();
  else { touchwin(listpad); refreshlist(); }
  if (newsearchstring[0]) {
    strcpy(searchstring,newsearchstring);
    dosearch();
  } else
    kd_searchagain();
}

void baselist::displayhelp(const struct helpmenuentry *helpmenu, int key) {
  const struct helpmenuentry *hme;
  int maxx, maxy, i, y, x, nextkey;
  
  getmaxyx(stdscr,maxy,maxx);
  clearok(stdscr,TRUE);
  for (;;) {
    werase(stdscr);
    for (hme= helpmenu; hme->key && hme->key != key; hme++);
    if (hme->key) {
      attrset(list_attr);
      mvaddstr(1,0, gettext(hme->msg->text));
      attrset(title_attr);
      mvaddstr(0,0, _("Help: "));
      addstr(gettext(hme->msg->title));
      getyx(stdscr,y,x);
      while (++x<maxx) addch(' ');
      attrset(thisstate_attr);
      mvaddstr(maxy-1,0,
_("? = help menu    Space = exit help    . = next help    or a help page key ")
               );
      getyx(stdscr,y,x);
      while (++x<maxx) addch(' ');
      move(maxy,maxx);
      attrset(A_NORMAL);
      nextkey= hme[1].key;
    } else {
      mvaddstr(1,1, _("Help information is available under the following topics:"));
      for (i=0, hme=helpmenu; hme->key; hme++,i++) {
        attrset(A_BOLD);
        mvaddch(i+3,3, hme->key);
        attrset(A_NORMAL);
        mvaddstr(i+3,6, gettext(hme->msg->title));
      }
      mvaddstr(i+4,1,
               _("Press a key from the list above, Space to exit help,\n"
               "  or `.' (full stop) to read each help page in turn. "));
      nextkey= helpmenu[0].key;
    }
    refresh();
    key= getch();
    if (key == EOF) ohshite(_("error reading keyboard in help"));
    if (key == ' ') {
      break;
    } else if (key == '?') {
      key= 0;
    } else if (key == '.') {
      key= nextkey;
    }
  }
  werase(stdscr);
  clearok(stdscr,TRUE);
  wnoutrefresh(stdscr);

  redrawtitle();
  refreshcolheads();
  refreshlist();
  redrawthisstate();
  refreshinfo();
  wnoutrefresh(whatinfowin);
}     

void baselist::kd_help() {
  displayhelp(helpmenulist(),0);
}

void baselist::setcursor(int index) {
  if (listpad && cursorline != -1) {
    redrawitemsrange(cursorline,cursorline+1);
    redraw1itemsel(cursorline,0);
  }
  if (cursorline != index) infotopofscreen= 0;
  cursorline= index;
  if (listpad) {
    redrawitemsrange(cursorline,cursorline+1);
    redraw1itemsel(cursorline,1);
    refreshlist();
    redrawthisstate();
  }
  redrawinfo();
}

void baselist::kd_down() {
  int ncursor= cursorline;
  // scroll by one line unless the bottom is already visible
  // or we're in the top half of the screen ...
  if (topofscreen < nitems - list_height &&
      ncursor >= topofscreen + list_height - 3) topofscreen++;
  // move cursor if there are any more ...
  if (cursorline+1 < nitems) ncursor++;
  setcursor(ncursor);
}
  
void baselist::kd_up() {
  int ncursor= cursorline;
  // scroll by one line if there are any lines not shown yet
  // and we're not in the bottom half the screen ...
  if (topofscreen > 0 &&
      ncursor <= topofscreen + 2) topofscreen--;
  // move cursor if there are any to move it to ...
  if (cursorline > 0) ncursor--;
  setcursor(ncursor);
}

void baselist::kd_iscrollon() {
  infotopofscreen += info_height;
  if (infotopofscreen > infolines - info_height)
    infotopofscreen= infolines - info_height;
  if (infotopofscreen < 0) infotopofscreen= 0;
  refreshinfo();
}

void baselist::kd_iscrollback() {
  infotopofscreen -= info_height;
  if (infotopofscreen < 0) infotopofscreen= 0;
  refreshinfo();
}

void baselist::kd_iscrollon1() {
  if (infotopofscreen >= infolines - info_height) return;
  infotopofscreen++; refreshinfo();
}

void baselist::kd_iscrollback1() {
  if (infotopofscreen <= 0) return;
  infotopofscreen--; refreshinfo();
}

void baselist::kd_panon() {
  leftofscreen += xmax/3;
  if (leftofscreen > total_width - xmax) leftofscreen= total_width - xmax;
  if (leftofscreen < 0) leftofscreen= 0;
  refreshcolheads(); refreshlist(); redrawthisstate(); refreshinfo();
}

void baselist::kd_panback() {
  leftofscreen -= xmax/3;
  if (leftofscreen < 0) leftofscreen= 0;
  refreshcolheads(); refreshlist(); redrawthisstate(); refreshinfo();
}

void baselist::kd_panon1() {
  leftofscreen++;
  if (leftofscreen > total_width - xmax) leftofscreen= total_width - xmax;
  if (leftofscreen < 0) leftofscreen= 0;
  refreshcolheads(); refreshlist(); redrawthisstate(); refreshinfo();
}

void baselist::kd_panback1() {
  leftofscreen--;
  if (leftofscreen < 0) leftofscreen= 0;
  refreshcolheads(); refreshlist(); redrawthisstate(); refreshinfo();
}
