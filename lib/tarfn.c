/*
 * Functions for extracting tar archives.
 * Bruce Perens, April-May 1995
 * Copyright (C) 1995 Bruce Perens
 * This is free software under the GNU General Public License.
 */
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>
#include "tarfn.h"

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
	= (unsigned int)&(((TarHeader *)0)->Checksum);

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

static int
DecodeTarHeader(char * block, TarInfo * d)
{
	TarHeader *			h = (TarHeader *)block;
	unsigned char *		s = (unsigned char *)block;
	struct passwd *		passwd = 0;
	struct group *		group = 0;
	unsigned int		i;
	long				sum;
	long				checksum;

	if ( *h->UserName )
		passwd = getpwnam(h->UserName);
	if ( *h->GroupName )
		group = getgrnam(h->GroupName);

	d->Name = h->Name;
	d->LinkName = h->LinkName;
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

extern int
TarExtractor(
 void *			userData
,const TarFunctions *	functions)
{
	int	status;
	char	buffer[512];
	TarInfo	h;

	h.UserData = userData;

	while ( (status = functions->Read(userData, buffer, 512)) == 512 ) {
		int	nameLength;

		if ( !DecodeTarHeader(buffer, &h) ) {
			if ( h.Name[0] == '\0' ) {
				return 0;	/* End of tape */
			} else {
				errno = 0;	/* Indicates broken tarfile */
				return -1;	/* Header checksum error */
			}
		}
		if ( h.Name[0] == '\0' ) {
			errno = 0;	/* Indicates broken tarfile */
			return -1;	/* Bad header data */
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
			h.Name[nameLength - 1] = '\0';
			status = (*functions->MakeDirectory)(&h);
			break;
		case HardLink:
			status = (*functions->MakeHardLink)(&h);
			break;
		case SymbolicLink:
			status = (*functions->MakeSymbolicLink)(&h);
			break;
		case CharacterDevice:
		case BlockDevice:
		case FIFO:
			status = (*functions->MakeSpecialFile)(&h);
			break;
		default:
			errno = 0;	/* Indicates broken tarfile */
			return -1;	/* Bad header field */
		}
		if ( status != 0 )
			return status;	/* Pass on status from coroutine */
	}
	if ( status > 0 ) {	/* Read partial header record */
		errno = 0;	/* Indicates broken tarfile */
		return -1;
	} else {
		return status;	/* Whatever I/O function returned */
	}
}
