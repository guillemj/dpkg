#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <ncurses/curses.h>

struct kd { int v; const char *n; } kds[]= {
#include "curkeys.inc"
};

int main(int argc, char **argv) {
  int n=0, c, y,x;
  struct kd *kdp;

  initscr(); cbreak(); noecho(); nonl();
  keypad(stdscr,TRUE);
  getmaxyx(stdscr,y,x);
  mvprintw(5,5,"q to quit; b to beep; (y%d x%d)",y,x);

  for (;;) {
    refresh();
    c= getch(); if (c==ERR) { endwin(); perror("err"); exit(1); }
    for (kdp=kds; kdp->v != -1 && kdp->v != c; kdp++);
    n++; mvprintw(10 + (n%4),10,"n %10d  keycode %4d  %-10s  F0 + %4d",n,c,
                  kdp->n, c-KEY_F0);
    if (c == 'q') break;
    if (c == 'b') beep();
  }
  endwin();
  return 0;
}
