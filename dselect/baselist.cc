/*
 * dselect - Debian GNU/Linux package maintenance user interface
 * baselist.cc - list of somethings
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
#include <curses.h>
#include <assert.h>
#include <signal.h>
#include <ctype.h>

extern "C" {
#include <config.h>
#include <dpkg.h>
#include <dpkg-db.h>
}
#include "dselect.h"
#include "bindings.h"

void mywerase(WINDOW *win) {
  int my,mx,y,x;
  getmaxyx(win,my,mx);
  for (y=0; y<my; y++) {
    wmove(win,y,0); for (x=0; x<mx; x++) waddch(win,' ');
  }
  wmove(win,0,0);
}

baselist *baselist::signallist= 0;
void baselist::sigwinchhandler(int) {
  baselist *p= signallist;
  p->enddisplay();
  endwin(); initscr();
  p->startdisplay();
  if (doupdate() == ERR) ohshite("doupdate in SIGWINCH handler failed");
}

static void cu_sigwinch(int, void **argv) {
  struct sigaction *osigactp= (struct sigaction*)argv[0];
  sigset_t *oblockedp= (sigset_t*)argv[1];
  
  if (sigaction(SIGWINCH,osigactp,0)) ohshite("failed to restore old SIGWINCH sigact");
  delete osigactp;
  if (sigprocmask(SIG_SETMASK,oblockedp,0)) ohshite("failed to restore old signal mask");
  delete oblockedp;
} 

void baselist::setupsigwinch() {
  sigemptyset(&sigwinchset);
  sigaddset(&sigwinchset,SIGWINCH);
    
  osigactp= new(struct sigaction);
  oblockedp= new(sigset_t);
  if (sigprocmask(0,0,oblockedp)) ohshite("failed to get old signal mask");
  if (sigaction(SIGWINCH,0,osigactp)) ohshite("failed to get old SIGWINCH sigact");

  push_cleanup(cu_sigwinch,~0, 0,0, 2,(void*)osigactp,(void*)oblockedp);

  if (sigprocmask(SIG_BLOCK,&sigwinchset,0)) ohshite("failed to block SIGWINCH");
  memset(&nsigact,0,sizeof(nsigact));
  nsigact.sa_handler= sigwinchhandler;
  sigemptyset(&nsigact.sa_mask);
  nsigact.sa_flags= SA_INTERRUPT;
  if (sigaction(SIGWINCH,&nsigact,0)) ohshite("failed to set new SIGWINCH sigact");
}

void baselist::setheights() {
  int y= ymax - (title_height + colheads_height + thisstate_height);
  assert(y>=1);
  if (showinfo==2 && y>=7) {
    list_height= 5;
    whatinfo_height= 1;
    info_height= y-6;
  } else if (showinfo==1 && y>=10) {
    list_height= y/2;
    info_height= (y-1)/2;
    whatinfo_height= 1;
  } else {
    list_height= y;
    info_height= 0;
    whatinfo_height= 0;
  }
  colheads_row= title_height;
  list_row= colheads_row + colheads_height;
  thisstate_row= list_row + list_height;
  info_row= thisstate_row + thisstate_height;
  whatinfo_row= ymax - 1;
}

void baselist::startdisplay() {
  if (debug) fprintf(debug,"baselist[%p]::startdisplay()\n",this);
  cbreak(); noecho(); nonl(); keypad(stdscr,TRUE);
  clear(); wnoutrefresh(stdscr);

  // find attributes
  if (has_colors() && start_color()==OK && COLOR_PAIRS >= 3) {
    if (init_pair(1,COLOR_WHITE,COLOR_BLACK) != OK ||
        init_pair(2,COLOR_WHITE,COLOR_RED) != OK ||
        init_pair(3,COLOR_WHITE,COLOR_BLUE) != OK)
      ohshite("failed to allocate colour pairs");
    list_attr= COLOR_PAIR(1);
    listsel_attr= list_attr|A_REVERSE;
    title_attr= COLOR_PAIR(2);
    thisstate_attr= COLOR_PAIR(3);
    selstate_attr= list_attr|A_BOLD;
    selstatesel_attr= listsel_attr|A_BOLD;
  } else {
    title_attr= A_REVERSE;
    thisstate_attr= A_STANDOUT;
    list_attr= 0;
    listsel_attr= A_STANDOUT;
    selstate_attr= A_BOLD;
    selstatesel_attr= A_STANDOUT;
  }
  query_attr= title_attr;
  info_attr= list_attr;
  colheads_attr= info_headattr= A_BOLD;
  whatinfo_attr= thisstate_attr;

  // set up windows and pads, based on screen size
  getmaxyx(stdscr,ymax,xmax);
  title_height= ymax>=6;
  colheads_height= ymax>=5;
  thisstate_height= ymax>=3;

  setheights();
  setwidths();
  
  titlewin= newwin(1,xmax, 0,0);
  if (!titlewin) ohshite("failed to create title window");
  wattrset(titlewin,title_attr);
  
  whatinfowin= newwin(1,xmax, whatinfo_row,0);
  if (!whatinfowin) ohshite("failed to create whatinfo window");
  wattrset(whatinfowin,whatinfo_attr);
  
  listpad= newpad(nitems+1, total_width);
  if (!listpad) ohshite("failed to create baselist pad");
  
  colheadspad= newpad(1, total_width);
  if (!colheadspad) ohshite("failed to create heading pad");
  wattrset(colheadspad,colheads_attr);
  
  thisstatepad= newpad(1, total_width);
  if (!thisstatepad) ohshite("failed to create thisstate pad");
  wattrset(thisstatepad,thisstate_attr);

  infopad= newpad(MAX_DISPLAY_INFO, total_width);
  if (!infopad) ohshite("failed to create info pad");
  wattrset(infopad,info_attr);

  querywin= newwin(1,xmax,ymax-1,0);
  if (!querywin) ohshite("failed to create query window");

  if (cursorline >= topofscreen + list_height) topofscreen= cursorline;
  if (topofscreen > nitems - list_height) topofscreen= nitems - list_height;
  if (topofscreen < 0) topofscreen= 0;

  infotopofscreen= 0; leftofscreen= 0;

  redrawall();

  if (debug)
    fprintf(debug,
            "baselist::startdisplay() done ...\n\n"
            " xmax=%d, ymax=%d;\n\n"
            " title_height=%d, colheads_height=%d, list_height=%d;\n"
            " thisstate_height=%d, info_height=%d, whatinfo_height=%d;\n\n"
            " colheads_row=%d, thisstate_row=%d, info_row=%d;\n"
            " whatinfo_row=%d, list_row=%d;\n\n",
            xmax, ymax,
            title_height, colheads_height, list_height,
            thisstate_height, info_height, whatinfo_height,
            colheads_row, thisstate_row, info_row,
            whatinfo_row, list_row);

}

void baselist::enddisplay() {
  delwin(titlewin);
  delwin(whatinfowin);
  delwin(listpad);  
  delwin(colheadspad);  
  delwin(thisstatepad);
  delwin(infopad);
  wmove(stdscr,ymax,0); wclrtoeol(stdscr);
  listpad= 0;
}

void baselist::redrawall() {
  redrawtitle();
  redrawcolheads();
  wattrset(listpad,list_attr); mywerase(listpad);
  ldrawnstart= ldrawnend= -1; // start is first drawn; end is first undrawn; -1=none
  refreshlist();
  redrawthisstate();
  redrawinfo();
}

void baselist::redraw1item(int index) {
  redraw1itemsel(index, index == cursorline);
}

baselist::baselist(keybindings *kb) {
  if (debug)
    fprintf(debug,"baselist[%p]::baselist()\n",this);

  bindings= kb;
  nitems= 0;

  xmax= -1;
  list_height=0; info_height=0;
  topofscreen= 0; leftofscreen= 0;
  listpad= 0; cursorline= -1;
  showinfo= 1;

  searchstring[0]= 0;
}  

void baselist::itd_keys() {
  whatinfovb("keybindings");
  
  const int givek= xmax/3;
  bindings->describestart();
  const char **ta;
  while ((ta= bindings->describenext()) != 0) {
    const char **tap= ta+1;
    for (;;) {
      waddstr(infopad, *tap);
      tap++;  if (!*tap) break;
      waddstr(infopad, ", ");
    }
    int y,x;
    getyx(infopad,y,x);
    if (x >= givek) y++;
    mvwaddstr(infopad, y,givek, ta[0]);
    waddch(infopad,'\n');
  }
}

void baselist::dosearch() {
  int offset, index, searchlen;
  searchlen= strlen(searchstring);
  if (debug) fprintf(debug,"packagelist[%p]::dosearch(); searchstring=`%s' len=%d\n",
                     this,searchstring,searchlen);
  for (offset=1, index=greaterint(topofscreen,cursorline+1);
       offset<nitems;
       offset++, index++) {
    if (index >= nitems) index -= nitems;
    int lendiff, i;
    const char *thisname;
    thisname= itemname(index);
    if (!thisname) continue;
    lendiff= strlen(thisname) - searchlen;
    for (i=0; i<=lendiff; i++)
      if (!strncasecmp(thisname + i, searchstring, searchlen)) {
        topofscreen= index-1;
        if (topofscreen > nitems - list_height) topofscreen= nitems-list_height;
        if (topofscreen < 0) topofscreen= 0;
        setcursor(index);
        return;
      }
  }
  beep();
}

void baselist::refreshinfo() {
  pnoutrefresh(infopad, infotopofscreen,leftofscreen, info_row,0,
               lesserint(info_row + info_height - 1, info_row + MAX_DISPLAY_INFO - 1),
               lesserint(total_width - leftofscreen - 1, xmax - 1));
  
  if (whatinfo_height) {
    mywerase(whatinfowin);
    mvwaddstr(whatinfowin,0,0, whatinfovb.string());
    if (infolines > info_height) {
      wprintw(whatinfowin,"  -- %d%%, press ",
              (int)((infotopofscreen + info_height) * 100.0 / infolines));
      if (infotopofscreen + info_height < infolines) {
        wprintw(whatinfowin,"%s for more", bindings->find("iscrollon"));
        if (infotopofscreen) waddstr(whatinfowin, ", ");
      }
      if (infotopofscreen)
        wprintw(whatinfowin, "%s to go back",bindings->find("iscrollback"));
      waddch(whatinfowin,'.');
    }
    wnoutrefresh(whatinfowin);
  }
}

void baselist::wordwrapinfo(int offset, const char *m) {
  int usemax= xmax-5;
  if (debug) fprintf(debug,"baselist[%p]::wordwrapinfo(%d, `%s')\n",this,offset,m);
  int wrapping=0;
  for (;;) {
    int offleft=offset; while (*m == ' ' && offleft>0) { m++; offleft--; }
    const char *p= strchr(m,'\n');
    int l= p ? (int)(p-m) : strlen(m);
    while (l && isspace(m[l-1])) l--;
    if (!l || *m == '.' && l == 1) {
      if (wrapping) waddch(infopad,'\n');
      waddch(infopad,'\n');
      wrapping= 0;
    } else if (*m == ' ' || usemax < 10) {
      if (wrapping) waddch(infopad,'\n');
      waddnstr(infopad, m, l);
      waddch(infopad,'\n'); wrapping= 0;
    } else {
      int x,y;
      if (wrapping) {
        getyx(infopad, y,x);
        if (x+1 >= usemax) {
          waddch(infopad,'\n');
        } else {
          waddch(infopad,' ');
        }
      }
      for (;;) {
        getyx(infopad, y,x);
        int dosend= usemax-x;
        if (l <= dosend) {
          dosend=l;
        } else {
          int i=dosend;
          while (i > 0 && m[i] != ' ') i--;
          if (i > 0 || x > 0) dosend=i;
        }
        if (dosend) waddnstr(infopad, m, dosend);
        while (dosend < l && m[dosend] == ' ') dosend++;
        l-= dosend; m+= dosend;
        if (l <= 0) break;
        waddch(infopad,'\n');
      }
      wrapping= 1;
    }
    if (!p) break;
    m= ++p;
  }
  if (debug) fprintf(debug,"baselist[%p]::wordwrapinfo() done\n",this);
}

baselist::~baselist() { }
