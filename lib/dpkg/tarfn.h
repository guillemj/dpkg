/*
 * libdpkg - Debian packaging suite library routines
 * tarfn.h - tar archive extraction functions
 *
 * Copyright © 1995 Bruce Perens
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

#ifndef LIBDPKG_TARFN_H
#define LIBDPKG_TARFN_H

#include <sys/types.h>

#include <unistd.h>
#include <stdlib.h>

enum tar_format {
	tar_format_old,
	tar_format_gnu,
	tar_format_ustar,
	tar_format_pax,
};

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
	enum tar_format	format;		/* Tar archive format. */
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

int TarExtractor(void *userData, const TarFunctions *functions);

#endif
