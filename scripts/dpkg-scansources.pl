#!/usr/bin/perl -w
use strict;

# $Id: dpkg-scansources.pl,v 1.6.2.1 2003/09/14 01:49:08 doogie Exp $

# Copyright 1999 Roderick Schertler
# Copyright 2002 Wichert Akkerman <wakkerma@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# For a copy of the GNU General Public License write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

# User documentation is at the __END__.
#
# Errors with a single package are warned about but don't affect the
# exit code.  Only errors which affect everything cause a non-zero exit.
#
# Dependencies are by request non-existant.  I used to use the MD5 and
# Proc::WaitStat modules.

use Getopt::Long ();

my $Exit = 0;
(my $Me = $0) =~ s-.*/--;
my $Version = q$Revision: 1.6.2.1 $ =~ /(\d\S+)/ ? $1 : '?';

# %Override is a hash of lists.  The subs following describe what's in
# the lists.

my %Override;
sub O_PRIORITY		() { 0 }
sub O_SECTION		() { 1 }
sub O_MAINT_FROM	() { 2 } # undef for non-specific, else listref
sub O_MAINT_TO		() { 3 } # undef if there's no maint override

my %Priority = (
     'extra'		=> 1,
     'optional'		=> 2,
     'standard'		=> 3,
     'important'	=> 4,
     'required'		=> 5,
);

# Switches

my $Debug	= 0;
my $No_sort	= 0;
my $Src_override = undef;

my @Option_spec = (
    'debug!'		=> \$Debug,
    'help!'		=> sub { usage() },
    'no-sort|n'		=> \$No_sort,
    'source-override|s=s' => \$Src_override,
    'version'		=> sub { print "$Me version $Version\n"; exit },
);

my $Usage = <<EOF;
usage: $Me [switch]... binary-dir [override-file [path-prefix]] > Sources

switches:
        --debug		turn debugging on
        --help		show this and then die
    -n, --no-sort	don\'t sort by package before outputting
    -s, --source-override file
			use file for additional source overrides, default
			is regular override file with .src appended
    	--version	show the version and exit

See the man page or \`perldoc $Me\' for the full documentation.
EOF

sub debug {
    print @_, "\n" if $Debug;
}

sub xwarndie_mess {
    my @mess = ("$Me: ", @_);
    $mess[$#mess] =~ s/:$/: $!\n/;	# XXX loses if it's really /:\n/
    return @mess;
}

sub xdie {
    die xwarndie_mess @_;
}

sub xwarn {
    warn xwarndie_mess @_;
    $Exit ||= 1;
}

sub xwarn_noerror {
    warn xwarndie_mess @_;
}

sub usage {
    xwarn @_ if @_;
    die $Usage;
}

# Getopt::Long has some really awful defaults.  This function loads it
# then configures it to use more sane settings.

sub getopt(@);
sub configure_getopt {
    Getopt::Long->import(2.11);
    *getopt = \&Getopt::Long::GetOptions;

    # I'm setting this environment variable lest he sneaks more bad
    # defaults into the module.
    local $ENV{POSIXLY_CORRECT} = 1;
    Getopt::Long::config qw(
	default
	no_autoabbrev
	no_getopt_compat
	require_order
	bundling
	no_ignorecase
    );
}

sub close_msg {
    my $name = shift;
    return "error closing $name (\$? $?, \$! `$!')\n";
}

sub init {
    configure_getopt;
    getopt @Option_spec or usage;
}

sub load_override {
    my $file = shift;
    local $_;

    open OVERRIDE, $file or xdie "can't read override file $file:";
    while (<OVERRIDE>) {
    	s/#.*//;
	next if /^\s*$/;
	s/\s+$//;

	my @data = split ' ', $_, 4;
	unless (@data == 3 || @data == 4) {
	    xwarn_noerror "invalid override entry at line $. (",
			    0+@data, " fields)\n";
	    next;
	}
	my ($package, $priority, $section, $maintainer) = @data;
	if (exists $Override{$package}) {
	    xwarn_noerror "ignoring duplicate override entry for $package",
	    	    	    " at line $.\n";
	    next;
	}
	if (!$Priority{$priority}) {
	    xwarn_noerror "ignoring override entry for $package,",
	    	    	    " invalid priority $priority\n";
	    next;
	}

	$Override{$package} = [];
	$Override{$package}[O_PRIORITY] = $priority;
	$Override{$package}[O_SECTION] = $section;
	if (!defined $maintainer) {
	    # do nothing
	}
	elsif ($maintainer =~ /^(.*\S)\s*=>\s*(.*)$/) {
	    $Override{$package}[O_MAINT_FROM] = [split m-\s*//\s*-, $1];
	    $Override{$package}[O_MAINT_TO] = $2;
	}
	else {
	    $Override{$package}[O_MAINT_TO] = $maintainer;
	}
    }
    close OVERRIDE or xdie "error closing override file:";
}

sub load_src_override {
    my ($user_file, $regular_file) = @_;
    my ($file);
    local $_;

    if (defined $user_file) {
	$file = $user_file;
    }
    elsif (defined $regular_file) {
	$file = "$regular_file.src";
    }
    else {
	return;
    }

    debug "source override file $file";
    unless (open SRC_OVERRIDE, $file) {
	return if !defined $user_file;
	xdie "can't read source override file $file:";
    }
    while (<SRC_OVERRIDE>) {
    	s/#.*//;
	next if /^\s*$/;
	s/\s+$//;

	my @data = split ' ', $_;
	unless (@data == 2) {
	    xwarn_noerror "invalid source override entry at line $. (",
	    	    	    0+@data, " fields)\n";
	    next;
	}

	my ($package, $section) = @data;
	my $key = "source/$package";
	if (exists $Override{$key}) {
	    xwarn_noerror "ignoring duplicate source override entry",
		    	    " for $package at line $.\n";
	    next;
	}
	$Override{$key} = [];
	$Override{$key}[O_SECTION] = $section;
    }
    close SRC_OVERRIDE or xdie "error closing source override file:";
}

# Given FILENAME (for error reporting) and STRING, drop the PGP info
# from the string and undo the encoding (if present) and return it.

sub de_pgp {
    my ($file, $s) = @_;
    if ($s =~ s/^-----BEGIN PGP SIGNED MESSAGE-----.*?\n\n//s) {
	unless ($s =~ s/\n
			-----BEGIN\040PGP\040SIGNATURE-----\n
			.*?\n
			-----END\040PGP\040SIGNATURE-----\n
		    //xs) {
	    xwarn_noerror "$file has PGP start token but not end token\n";
	    return;
	}
	$s =~ s/^- //mg;
    }
    return $s;
}

# Load DSC-FILE and return its size, MD5 and translated (de-PGPed)
# contents.

sub read_dsc {
    my $file = shift;
    my ($size, $md5, $nread, $contents);

    unless (open FILE, $file) {
    	xwarn_noerror "can't read $file:";
	return;
    }

    $size = -s FILE;
    unless (defined $size) {
	xwarn_noerror "error doing fstat on $file:";
	return;
    }

    $contents = '';
    do {
	$nread = read FILE, $contents, 16*1024, length $contents;
	unless (defined $nread) {
	    xwarn_noerror "error reading from $file:";
	    return;
	}
    } while $nread > 0;

    # Rewind the .dsc file and feed it to md5sum as stdin.
    my $pid = open MD5, '-|';
    unless (defined $pid) {
	xwarn_noerror "can't fork:";
	return;
    }
    if (!$pid) {
    	open STDIN, '<&FILE'	or xdie "can't dup $file:";
	seek STDIN, 0, 0	or xdie "can't rewind $file:";
	exec 'md5sum'		or xdie "can't exec md5sum:";
    }
    chomp($md5 = join '', <MD5>);
    unless (close MD5) {
	xwarn_noerror close_msg 'md5sum';
	return;
    }
    $md5 =~ s/ *-$//; # Remove trailing spaces and -, to work with GNU md5sum
    unless (length($md5) == 32 && $md5 !~ /[^\da-f]/i) {
	xwarn_noerror "invalid md5 output for $file ($md5)\n";
	return;
    }

    unless (close FILE) {
	xwarn_noerror "error closing $file:";
	return;
    }

    $contents = de_pgp $file, $contents;
    return unless defined $contents;

    return $size, $md5, $contents;
}

# Given PREFIX and DSC-FILE, process the file and returning the source
# package name and index record.

sub process_dsc {
    my ($prefix, $file) = @_;
    my ($source, @binary, $priority, $section, $maintainer_override,
	$dir, $dir_field, $dsc_field_start);

    my ($size, $md5, $contents) = read_dsc $file or return;

    # Allow blank lines at the end of a file, because the other programs
    # do.
    $contents =~ s/\n\n+\Z/\n/;

    if ($contents =~ /^\n/ || $contents =~ /\n\n/) {
    	xwarn_noerror "$file invalid (contains blank line)\n";
	return;
    }

    # Take the $contents and create a list of (possibly multi-line)
    # fields.  Fields can be continued by starting the next line with
    # white space.  The tricky part is I don't want to modify the data
    # at all, so I can't just collapse continued fields.
    #
    # Implementation is to start from the last line and work backwards
    # to the second.  If this line starts with space, append it to the
    # previous line and undef it.  When done drop the undef entries.
    my @line = split /\n/, $contents;
    for (my $i = $#line; $i > 0; $i--) {
    	if ($line[$i] =~ /^\s/) {
	    $line[$i-1] .= "\n$line[$i]";
	    $line[$i] = undef;
	}
    }
    my @field = map { "$_\n" } grep { defined } @line;

    # Extract information from the record.
    for my $orig_field (@field) {
	my $s = $orig_field;
	$s =~ s/\s+$//;
	$s =~ s/\n\s+/ /g;
	unless ($s =~ s/^([^:\s]+):\s*//) {
	    xwarn_noerror "invalid field in $file: $orig_field";
	    return;
	}
	my ($key, $val) = (lc $1, $s);

	# $source
	if ($key eq 'source') {
	    if (defined $source) {
		xwarn_noerror "duplicate source field in $file\n";
		return;
	    }
	    if ($val =~ /\s/) {
		xwarn_noerror "invalid source field in $file\n";
		return;
	    }
	    $source = $val;
	    next;
	}

	# @binary
	if ($key eq 'binary') {
	    if (@binary) {
		xwarn_noerror "duplicate binary field in $file\n";
		return;
	    }
	    @binary = split /\s*,\s*/, $val;
	    unless (@binary) {
		xwarn_noerror "no binary packages specified in $file\n";
		return;
	    }
	}
    }

    # The priority for the source package is the highest priority of the
    # binary packages it produces.
    my @binary_by_priority = sort {
	    ($Override{$a} ? $Priority{$Override{$a}[O_PRIORITY]} : 0)
		<=>
	    ($Override{$b} ? $Priority{$Override{$b}[O_PRIORITY]} : 0)
	} @binary;
    my $priority_override = $Override{$binary_by_priority[-1]};
    $priority = $priority_override
			? $priority_override->[O_PRIORITY]
			: undef;

    # For the section override, first check for a record from the source
    # override file, else use the regular override file.
    my $section_override = $Override{"source/$source"} || $Override{$source};
    $section = $section_override
			? $section_override->[O_SECTION]
			: undef;

    # For the maintainer override, use the override record for the first
    # binary.
    $maintainer_override = $Override{$binary[0]};

    # A directory field will be inserted just before the files field.
    $dir = ($file =~ s-(.*)/--) ? $1 : '';
    $dir = "$prefix$dir";
    $dir =~ s-/+$--;
    $dir = '.' if $dir eq '';
    $dir_field .= "Directory: $dir\n";

    # The files field will get an entry for the .dsc file itself.
    $dsc_field_start = "Files:\n $md5 $size $file\n";

    # Loop through @field, doing nececessary processing and building up
    # @new_field.
    my @new_field;
    for (@field) {
	# Rename the source field to package.
    	s/^Source:/Package:/i;

	# Override the user's priority field.
	if (/^Priority:/i && defined $priority) {
	    $_ = "Priority: $priority\n";
	    undef $priority;
	}

	# Override the user's section field.
	if (/^Section:/i && defined $section) {
	    $_ = "Section: $section\n";
	    undef $section;
	}

    	# Insert the directory line just before the files entry, and add
	# the dsc file to the files list.
    	if (defined $dir_field && s/^Files:\s*//i) {
	    push @new_field, $dir_field;
	    $dir_field = undef;
	    $_ = " $_" if length;
	    $_ = "$dsc_field_start$_";
	}

	# Modify the maintainer if necessary.
	if ($maintainer_override
		&& defined $maintainer_override->[O_MAINT_TO]
		&& /^Maintainer:\s*(.*)\n/is) {
	    my $maintainer = $1;
	    $maintainer =~ s/\n\s+/ /g;
	    if (!defined $maintainer_override->[O_MAINT_FROM]
	    	    || grep { $maintainer eq $_ }
			    @{ $maintainer_override->[O_MAINT_FROM] }){
		$_ = "Maintainer: $maintainer_override->[O_MAINT_TO]\n";
	    }
	}
    }
    continue {
	push @new_field, $_ if defined $_;
    }

    # If there was no files entry, add one.
    if (defined $dir_field) {
	push @new_field, $dir_field;
	push @new_field, $dsc_field_start;
    }

    # Add the section field if it didn't override one the user supplied.
    if (defined $section) {
	# If the record starts with a package field put it after that,
	# otherwise put it first.
	my $pos = $new_field[0] =~ /^Package:/i ? 1 : 0;
	splice @new_field, $pos, 0, "Section: $section\n";
    }

    # Add the priority field if it didn't override one the user supplied.
    if (defined $priority) {
	# If the record starts with a package field put it after that,
	# otherwise put it first.
	my $pos = $new_field[0] =~ /^Package:/i ? 1 : 0;
	splice @new_field, $pos, 0, "Priority: $priority\n";
    }

    return $source, join '', @new_field, "\n";
}

sub main {
    my (@out);

    init;
    @ARGV >= 1 && @ARGV <= 3 or usage "1 to 3 args expected\n";

    push @ARGV, undef		if @ARGV < 2;
    push @ARGV, ''		if @ARGV < 3;
    my ($dir, $override, $prefix) = @ARGV;

    load_override $override if defined $override;
    load_src_override $Src_override, $override;

    open FIND, "find \Q$dir\E -follow -name '*.dsc' -print |"
	or xdie "can't fork:";
    while (<FIND>) {
    	chomp;
	s-^\./+--;
    	my ($source, $out) = process_dsc $prefix, $_ or next;
	if ($No_sort) {
	    print $out;
	}
	else {
	    push @out, [$source, $out];
	}
    }
    close FIND or xdie close_msg 'find';

    if (@out) {
	print map { $_->[1] } sort { $a->[0] cmp $b->[0] } @out;
    }

    return 0;
}

$Exit = main || $Exit;
$Exit = 1 if $Exit and not $Exit % 256;
exit $Exit;
