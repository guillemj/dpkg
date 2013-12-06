/*
 * dselect - Debian package maintenance user interface
 * methlist.cc - list of access methods and options
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2001 Wichert Akkerman <wakkerma@debian.org>
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

#include <assert.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/string.h>

#include "dselect.h"
#include "bindings.h"
#include "method.h"
#include "helpmsgs.h"

static keybindings methodlistbindings(methodlist_kinterps,methodlist_korgbindings);

const char *methodlist::itemname(int index) {
  return table[index]->name;
}

void methodlist::kd_abort() { }

void methodlist::kd_quit() {
  debug(dbg_general, "methodlist[%p]::kd_quit() setting coption=%p",
        this, table[cursorline]);
  coption= table[cursorline];
}

void methodlist::setheights() {
  debug(dbg_general, "methodlist[%p]::setheights()", this);
  baselist::setheights();
  list_height++;
}

void methodlist::setwidths() {
  debug(dbg_general, "methodlist[%p]::setwidths()", this);

  status_width= 1;
  name_width= 14;
  name_column= status_width + gap_width;
  description_column= name_column + name_width + gap_width;
  description_width= total_width - description_column;
}

void methodlist::redrawtitle() {
  if (title_height) {
    mywerase(titlewin);
    mvwaddnstr(titlewin,0,0,_("dselect - list of access methods"),xmax);
    wnoutrefresh(titlewin);
  }
}

void methodlist::redrawthisstate() {
  if (!thisstate_height) return;
  mywerase(thisstatepad);
  wprintw(thisstatepad,
          _("Access method `%s'."),
          table[cursorline]->name);
  pnoutrefresh(thisstatepad, 0,0, thisstate_row,0,
               thisstate_row, min(total_width - 1, xmax - 1));
}

void methodlist::redraw1itemsel(int index, int selected) {
  int i;
  const char *p;

  wattrset(listpad, part_attr[selected ? listsel : list]);
  mvwaddch(listpad,index,0,
           table[index] == coption ? '*' : ' ');
  wattrset(listpad, part_attr[selected ? listsel : list]);
  mvwprintw(listpad,index,name_column-1, " %-*.*s ",
            name_width, name_width, table[index]->name);

  i= description_width;
  p= table[index]->summary ? table[index]->summary : "";
  while (i>0 && *p && *p != '\n') {
    waddch(listpad,*p);
    i--; p++;
  }
  while (i>0) {
    waddch(listpad,' ');
    i--;
  }
}

void methodlist::redrawcolheads() {
  if (colheads_height) {
    wattrset(colheadspad, part_attr[colheads]);
    mywerase(colheadspad);
    mvwaddstr(colheadspad,0,0, "  ");
    mvwaddnstr(colheadspad,0,name_column, _("Abbrev."), name_width);
    mvwaddnstr(colheadspad,0,description_column, _("Description"), description_width);
  }
  refreshcolheads();
}

methodlist::methodlist() : baselist(&methodlistbindings) {
  int newcursor= -1;

  debug(dbg_general, "methodlist[%p]::methodlist()", this);

  table= new struct dselect_option*[noptions];

  struct dselect_option *opt, **ip;
  for (opt=options, ip=table, nitems=0; opt; opt=opt->next, nitems++) {
    if (opt == coption) { assert(newcursor==-1); newcursor= nitems; }
    *ip++= opt;
  }
  assert(nitems==noptions);

  if (newcursor==-1) newcursor= 0;
  setcursor(newcursor);

  debug(dbg_general, "methodlist[%p]::methodlist done; noptions=%d",
        this, noptions);
}

methodlist::~methodlist() {
  debug(dbg_general, "methodlist[%p]::~methodlist()", this);
  delete[] table;
}

quitaction methodlist::display() {
  int response;
  const keybindings::interpretation *interp;

  debug(dbg_general, "methodlist[%p]::display()", this);

  setupsigwinch();
  startdisplay();

  debug(dbg_general, "methodlist[%p]::display() entering loop", this);
  for (;;) {
    if (whatinfo_height) wcursyncup(whatinfowin);
    if (doupdate() == ERR) ohshite(_("doupdate failed"));
    signallist= this;
    if (sigprocmask(SIG_UNBLOCK, &sigwinchset, nullptr))
      ohshite(_("failed to unblock SIGWINCH"));
    do
    response= getch();
    while (response == ERR && errno == EINTR);
    if (sigprocmask(SIG_BLOCK, &sigwinchset, nullptr))
      ohshite(_("failed to re-block SIGWINCH"));
    if (response == ERR) ohshite(_("getch failed"));
    interp= (*bindings)(response);
    debug(dbg_general, "methodlist[%p]::display() response=%d interp=%s",
          this, response, interp ? interp->action : "[none]");
    if (!interp) { beep(); continue; }
    (this->*(interp->mfn))();
    if (interp->qa != qa_noquit) break;
  }
  pop_cleanup(ehflag_normaltidy); // unset the SIGWINCH handler
  enddisplay();

  debug(dbg_general, "methodlist[%p]::display() done", this);

  return interp->qa;
}

void methodlist::itd_description() {
  whatinfovb(_("Explanation"));

  wattrset(infopad, part_attr[info_head]);
  waddstr(infopad, table[cursorline]->name);
  waddstr(infopad," - ");
  waddstr(infopad, table[cursorline]->summary);
  wattrset(infopad, part_attr[info]);

  const char *m= table[cursorline]->description;
  if (str_is_unset(m))
    m = _("No explanation available.");
  waddstr(infopad,"\n\n");
  wordwrapinfo(0,m);
}

void methodlist::redrawinfo() {
  if (!info_height) return;
  whatinfovb.reset();
  werase(infopad); wmove(infopad,0,0);

  debug(dbg_general, "methodlist[%p]::redrawinfo()", this);

  itd_description();

  whatinfovb.terminate();
  int y,x;
  getyx(infopad, y,x);
  if (x) y++;
  infolines= y;

  refreshinfo();
}

const struct helpmenuentry *methodlist::helpmenulist() {
  static const struct helpmenuentry list[]= {
    { 'i', &hlp_methintro            },
    { 'k', &hlp_methkeys             },
    {  0                             }
  };
  return list;
};
