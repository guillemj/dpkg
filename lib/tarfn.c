/*
 * Functions for extracting tar archives.
 * Bruce Perens, April-May 1995
 * Copyright (C) 1995 Bruce Perens
 * This is free software under the GNU General Public License.
 */
#include <config.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>
#include <tarfn.h>

struct TarHeader {
	char Name[100];
	char Mode[8];
	char UserID[8];
	char GroupID[8];
	char Size[12];
	char ModificationTime[12];
	char Checksum[8];
	char LinkFlag;
	char LinkName[100];
	char MagicNumber[8];
	char UserName[32];
	char GroupName[32];
	char MajorDevice[8];
	char MinorDevice[8];
};
typedef struct TarHeader	TarHeader;

static const unsigned int	TarChecksumOffset
	= (unsigned int)&(((TarHeader *)NULL)->Checksum);

/* Octal-ASCII-to-long */
static long
OtoL(const char * s, int size)
{
	int	n = 0;

	while ( *s == ' ' ) {
		s++;
		size--;
	}

	while ( --size >= 0 && *s >= '0' && *s <= '7' )
		n = (n * 010) + (*s++ - '0');

	return n;
}

/* String block to C null-terminated string */
char *
StoC(const char *s, int size)
{
	int	len;
	char *	str;

	len = strnlen(s, size);
	str = malloc(len + 1);
	memcpy(str, s, len);
	str[len] = 0;

	return str;
}

static int
DecodeTarHeader(char * block, TarInfo * d)
{
	TarHeader *		h = (TarHeader *)block;
	unsigned char *		s = (unsigned char *)block;
	struct passwd *		passwd = NULL;
	struct group *		group = NULL;
	unsigned int		i;
	long			sum;
	long			checksum;

	if ( *h->UserName )
		passwd = getpwnam(h->UserName);
	if ( *h->GroupName )
		group = getgrnam(h->GroupName);

	d->Name = StoC(h->Name, sizeof(h->Name));
	d->LinkName = StoC(h->LinkName, sizeof(h->LinkName));
	d->Mode = (mode_t)OtoL(h->Mode, sizeof(h->Mode));
	d->Size = (size_t)OtoL(h->Size, sizeof(h->Size));
	d->ModTime = (time_t)OtoL(h->ModificationTime
	 ,sizeof(h->ModificationTime));
	d->Device = ((OtoL(h->MajorDevice, sizeof(h->MajorDevice)) & 0xff) << 8)
	 | (OtoL(h->MinorDevice, sizeof(h->MinorDevice)) & 0xff);
	checksum = OtoL(h->Checksum, sizeof(h->Checksum));
	d->UserID = (uid_t)OtoL(h->UserID, sizeof(h->UserID));
	d->GroupID = (gid_t)OtoL(h->GroupID, sizeof(h->GroupID));
	d->Type = (TarFileType)h->LinkFlag;

	if ( passwd )
		d->UserID = passwd->pw_uid;

	if ( group )
		d->GroupID = group->gr_gid;

	
	sum = ' ' * sizeof(h->Checksum);/* Treat checksum field as all blank */
	for ( i = TarChecksumOffset; i > 0; i-- )
		sum += *s++;
	s += sizeof(h->Checksum);	/* Skip the real checksum field */
	for ( i = (512 - TarChecksumOffset - sizeof(h->Checksum)); i > 0; i-- )
		sum += *s++;

	return ( sum == checksum );
}

typedef struct symlinkList {
	TarInfo h;
	struct symlinkList *next;
} symlinkList;

extern int
TarExtractor(
 void *			userData
,const TarFunctions *	functions)
{
	int	status;
	char	buffer[512];
	TarInfo	h;

       char    *next_long_name, *next_long_link;
       char    *bp;
       char    **longp;
       int     long_read;
	symlinkList *symListTop, *symListBottom, *symListPointer;

       next_long_name = NULL;
       next_long_link = NULL;
       long_read = 0;
	symListBottom = symListPointer = symListTop = malloc(sizeof(symlinkList));
	symListTop->next = NULL;

	h.UserData = userData;

	while ( (status = functions->Read(userData, buffer, 512)) == 512 ) {
		int	nameLength;

		if ( !DecodeTarHeader(buffer, &h) ) {
			if ( h.Name[0] == '\0' ) {
				status = 0;	/* End of tape */
			} else {
				errno = 0;	/* Indicates broken tarfile */
				status = -1;	/* Header checksum error */
			}
			break;
		}
               if ( h.Type != GNU_LONGLINK && h.Type != GNU_LONGNAME ) {
                 if (next_long_name) {
                   h.Name = next_long_name;
                 }

                 if (next_long_link) {
                   h.LinkName = next_long_link;
                 }

                 next_long_link = NULL;
                 next_long_name = NULL;
               }

		if ( h.Name[0] == '\0' ) {
			errno = 0;	/* Indicates broken tarfile */
			status = -1;	/* Bad header data */
			break;
		}

		nameLength = strlen(h.Name);

		switch ( h.Type ) {
		case NormalFile0:
		case NormalFile1:
			/* Compatibility with pre-ANSI ustar */
			if ( h.Name[nameLength - 1] != '/' ) {
				status = (*functions->ExtractFile)(&h);
				break;
			}
			/* Else, Fall Through */
		case Directory:
			if ( h.Name[nameLength - 1] == '/' ) {
				h.Name[nameLength - 1] = '\0';
			}
			status = (*functions->MakeDirectory)(&h);
			break;
		case HardLink:
			status = (*functions->MakeHardLink)(&h);
			break;
		case SymbolicLink:
			memcpy(&symListBottom->h, &h, sizeof(TarInfo));
			if ((symListBottom->h.Name = strdup(h.Name)) == NULL) {
				status = -1;
				errno = 0;
				break;
			}
			if ((symListBottom->h.LinkName = strdup(h.LinkName)) == NULL) {
				free(symListBottom->h.Name);
				status = -1;
				errno = 0;
				break;
			}
			if ((symListBottom->next = malloc(sizeof(symlinkList))) == NULL) {
				free(symListBottom->h.LinkName);
				free(symListBottom->h.Name);
				status = -1;
				errno = 0;
				break;
			}
			symListBottom = symListBottom->next;
			symListBottom->next = NULL;
			status = 0;
			break;
		case CharacterDevice:
		case BlockDevice:
		case FIFO:
			status = (*functions->MakeSpecialFile)(&h);
			break;
               case GNU_LONGLINK:
               case GNU_LONGNAME:
                 // set longp to the location of the long filename or link
                 // we're trying to deal with
                 longp = ((h.Type == GNU_LONGNAME)
                          ? &next_long_name
                          : &next_long_link);

                 if (*longp)
                   free(*longp);

                 if (NULL == (*longp = (char *)malloc(h.Size))) {
                   /* malloc failed, so bail */
                   errno = 0;
		   status = -1;
		   break;
                 }
                 bp = *longp;

                 // the way the GNU long{link,name} stuff works is like this:  
		 // The first header is a "dummy" header that contains the size
		 // of the filename.  The next N headers contain the filename.
		 // After the headers with the filename comes the "real" header
		 // with a bogus name or link.
                 for (long_read = h.Size; long_read > 0;
                      long_read -= 512) {

                   int copysize;

                   status = functions->Read(userData, buffer, 512);
                   // if we didn't get 512 bytes read, punt
                   if (512 != status) {
		     if ( status > 0 ) { /* Read partial header record */
		       errno = 0;
		       status = -1;
                     }
                     break;
		   }

                   copysize = long_read > 512 ? 512 : long_read;
                   memcpy (bp, buffer, copysize);
                   bp += copysize;

                 };
                 // This decode function expects status to be 0 after
                 // the case statement if we successfully decoded.  I
                 // guess what we just did was successful.
                 status = 0;
                 break;
		default:
			errno = 0;	/* Indicates broken tarfile */
			status = -1;	/* Bad header field */
		}
		if ( status != 0 )
			break;	/* Pass on status from coroutine */
	}
	while(symListPointer->next) {
		if ( status == 0 )
			status = (*functions->MakeSymbolicLink)(&symListPointer->h);
		symListBottom = symListPointer->next;
		free(symListPointer->h.Name);
		free(symListPointer->h.LinkName);
		free(symListPointer);
		symListPointer = symListBottom;
	}
	free(symListPointer);
	free(h.Name);
	free(h.LinkName);
	if ( status > 0 ) {	/* Read partial header record */
		errno = 0;	/* Indicates broken tarfile */
		return -1;
	} else {
		return status;	/* Whatever I/O function returned */
	}
}

