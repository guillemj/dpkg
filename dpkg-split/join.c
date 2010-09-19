/*
 * dpkg-split - splitting and joining of multipart *.deb archives
 * join.c - joining
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <assert.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/myopt.h>

#include "dpkg-split.h"

void reassemble(struct partinfo **partlist, const char *outputfile) {
  FILE *output, *input;
  void *buffer;
  struct partinfo *pi;
  unsigned int i;
  size_t nr,buffersize;

  printf(P_("Putting package %s together from %d part: ",
            "Putting package %s together from %d parts: ",
            partlist[0]->maxpartn),
         partlist[0]->package,partlist[0]->maxpartn);
  
  buffersize= partlist[0]->maxpartlen;
  for (i=0; i<partlist[0]->maxpartn; i++)
    if (partlist[0]->headerlen > buffersize) buffersize= partlist[0]->headerlen;
  buffer= m_malloc(partlist[0]->maxpartlen);
  output= fopen(outputfile,"w");
  if (!output) ohshite(_("unable to open output file `%.250s'"),outputfile);
  for (i=0; i<partlist[0]->maxpartn; i++) {
    pi= partlist[i];
    input= fopen(pi->filename,"r");
    if (!input) ohshite(_("unable to (re)open input part file `%.250s'"),pi->filename);
    assert(pi->headerlen <= buffersize);
    nr= fread(buffer,1,pi->headerlen,input);
    if (nr != pi->headerlen) rerreof(input,pi->filename);
    assert(pi->thispartlen <= buffersize);
    printf("%d ",i+1);
    nr= fread(buffer,1,pi->thispartlen,input);
    if (nr != pi->thispartlen) rerreof(input,pi->filename);
    if (pi->thispartlen & 1)
      if (getc(input) == EOF) rerreof(input,pi->filename);
    if (ferror(input)) rerr(pi->filename);
    fclose(input);
    nr= fwrite(buffer,1,pi->thispartlen,output);
    if (nr != pi->thispartlen) werr(outputfile);
  }
  if (fflush(output))
    ohshite(_("unable to flush file '%s'"), outputfile);
  if (fsync(fileno(output)))
    ohshite(_("unable to sync file '%s'"), outputfile);
  if (fclose(output)) werr(outputfile);
  free(buffer);
  printf(_("done\n"));
}


void addtopartlist(struct partinfo **partlist,
                   struct partinfo *pi, struct partinfo *refi) {
  int i;
  
  if (strcmp(pi->package,refi->package) ||
      strcmp(pi->version,refi->version) ||
      strcmp(pi->md5sum,refi->md5sum) ||
      pi->orglength != refi->orglength ||
      pi->maxpartn != refi->maxpartn ||
      pi->maxpartlen != refi->maxpartlen) {
    print_info(pi);
    print_info(refi);
    ohshit(_("files `%.250s' and `%.250s' are not parts of the same file"),
           pi->filename,refi->filename);
  }
  i= pi->thispartn-1;
  if (partlist[i])
    ohshit(_("there are several versions of part %d - at least `%.250s' and `%.250s'"),
           pi->thispartn, pi->filename, partlist[i]->filename);
  partlist[i]= pi;
}

void do_join(const char *const *argv) {
  char *p;
  const char *thisarg;
  struct partqueue *pq;
  struct partinfo *refi, *pi, **partlist;
  unsigned int i;
  
  assert(!queue);
  if (!*argv)
    badusage(_("--%s requires one or more part file arguments"),
             cipaction->olong);
  while ((thisarg= *argv++)) {
    pq= nfmalloc(sizeof(struct partqueue));

    mustgetpartinfo(thisarg,&pq->info);
    
    
    pq->nextinqueue= queue;
    queue= pq;
  }
  refi= NULL;
  for (pq= queue; pq; pq= pq->nextinqueue)
    if (!refi || pq->info.thispartn < refi->thispartn) refi= &pq->info;
  assert(refi);
  partlist= nfmalloc(sizeof(struct partinfo*)*refi->maxpartn);
  for (i = 0; i < refi->maxpartn; i++)
    partlist[i] = NULL;
  for (pq= queue; pq; pq= pq->nextinqueue) {
    pi= &pq->info;
    addtopartlist(partlist,pi,refi);
  }
  for (i=0; i<refi->maxpartn; i++) {
    if (!partlist[i]) ohshit(_("part %d is missing"),i+1);
  }
  if (!opt_outputfile) {
    p= nfmalloc(strlen(refi->package)+1+strlen(refi->version)+sizeof(DEBEXT));
    strcpy(p,refi->package);
    strcat(p,"-");
    strcat(p,refi->version);
    strcat(p,DEBEXT);
    opt_outputfile = p;
  }
  reassemble(partlist, opt_outputfile);
}
