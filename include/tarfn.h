#ifndef	_TAR_FUNCTION_H_
#define	_TAR_FUNCTION_H_

/*
 * Functions for extracting tar archives.
 * Bruce Perens, April-May 1995
 * Copyright (C) 1995 Bruce Perens
 * This is free software under the GNU General Public License.
 */

#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

enum TarFileType {
	NormalFile0 = '\0',	/* For compatibility with decades-old bug */
	NormalFile1 = '0',
	HardLink = '1',
	SymbolicLink = '2',
	CharacterDevice = '3',
	BlockDevice = '4',
	Directory = '5',
	FIFO = '6',
	GNU_LONGLINK = 'K',
	GNU_LONGNAME = 'L'
};
typedef enum TarFileType	TarFileType;

struct	TarInfo {
	void *		UserData;	/* User passed this in as argument */
	char *		Name;		/* File name */
	mode_t		Mode;		/* Unix mode, including device bits. */
	size_t		Size;		/* Size of file */
	time_t		ModTime;	/* Last-modified time */
	TarFileType	Type;		/* Regular, Directory, Special, Link */
	char *		LinkName;	/* Name for symbolic and hard links */
	dev_t		Device;		/* Special device for mknod() */
	uid_t		UserID;		/* Numeric UID */
	gid_t		GroupID;	/* Numeric GID */
};
typedef struct TarInfo	TarInfo;

typedef	int	(*TarReadFunction)(void * userData, char * buffer, int length);

typedef int	(*TarFunction)(TarInfo * h);

struct TarFunctions {
	TarReadFunction	Read;
	TarFunction	ExtractFile;
	TarFunction	MakeDirectory;
	TarFunction	MakeHardLink;
	TarFunction	MakeSymbolicLink;
	TarFunction	MakeSpecialFile;
};
typedef struct TarFunctions	TarFunctions;

extern int	TarExtractor(void * userData, const TarFunctions * functions);

#endif
