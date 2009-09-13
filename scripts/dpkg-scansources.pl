#!/usr/bin/perl
#
# Copyright © 1999 Roderick Schertler
# Copyright © 2002 Wichert Akkerman <wakkerma@debian.org>
# Copyright © 2006-2009 Guillem Jover <guillem@debian.org>
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


# Errors with a single package are warned about but don't affect the
# exit code.  Only errors which affect everything cause a non-zero exit.
#
# Dependencies are by request non-existant.  I used to use the MD5 and
# Proc::WaitStat modules.


use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Control;
use Dpkg::Checksums;

textdomain("dpkg-dev");

use Getopt::Long ();

my $Exit = 0;

# %Override is a hash of lists.  The subs following describe what's in
# the lists.

my %Override;
sub O_PRIORITY		() { 0 }
sub O_SECTION		() { 1 }
sub O_MAINT_FROM	() { 2 } # undef for non-specific, else listref
sub O_MAINT_TO		() { 3 } # undef if there's no maint override
my %Extra_Override;

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
my $Extra_override_file = undef;

my @Option_spec = (
    'debug!'		=> \$Debug,
    'help!'		=> \&usage,
    'no-sort|n'		=> \$No_sort,
    'source-override|s=s' => \$Src_override,
    'extra-override|e=s' => \$Extra_override_file,
    'version'		=> \&version,
);

sub debug {
    print @_, "\n" if $Debug;
}

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;
    exit;
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <binarypath> [<overridefile> [<pathprefix>]] > Sources

Options:
  -n, --no-sort            don't sort by package before outputting.
  -e, --extra-override <file>
                           use extra override file.
  -s, --source-override <file>
                           use file for additional source overrides, default
                           is regular override file with .src appended.
      --debug              turn debugging on.
      --help               show this help message.
      --version            show the version.

See the man page for the full documentation.
"), $progname;

    exit;
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
    return sprintf(_g("error closing %s (\$? %d, \$! `%s')"),
                   $name, $?, $!)."\n";
}

sub init {
    configure_getopt;
    getopt @Option_spec or usage;
}

sub load_override {
    my $file = shift;
    local $_;

    open OVERRIDE, $file or syserr(_g("can't read override file %s"), $file);
    while (<OVERRIDE>) {
    	s/#.*//;
	next if /^\s*$/;
	s/\s+$//;

	my @data = split ' ', $_, 4;
	unless (@data == 3 || @data == 4) {
	    warning(_g("invalid override entry at line %d (%d fields)"),
	            $., 0 + @data);
	    next;
	}
	my ($package, $priority, $section, $maintainer) = @data;
	if (exists $Override{$package}) {
	    warning(_g("ignoring duplicate override entry for %s at line %d"),
	            $package, $.);
	    next;
	}
	if (!$Priority{$priority}) {
	    warning(_g("ignoring override entry for %s, invalid priority %s"),
	            $package, $priority);
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
    close OVERRIDE or syserr(_g("error closing override file"));
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
	syserr(_g("can't read source override file %s"), $file);
    }
    while (<SRC_OVERRIDE>) {
    	s/#.*//;
	next if /^\s*$/;
	s/\s+$//;

	my @data = split ' ', $_;
	unless (@data == 2) {
	    warning(_g("invalid source override entry at line %d (%d fields)"),
	            $., 0 + @data);
	    next;
	}

	my ($package, $section) = @data;
	my $key = "source/$package";
	if (exists $Override{$key}) {
	    warning(_g("ignoring duplicate source override entry for %s at line %d"),
	            $package, $.);
	    next;
	}
	$Override{$key} = [];
	$Override{$key}[O_SECTION] = $section;
    }
    close SRC_OVERRIDE or syserr(_g("error closing source override file"));
}

sub load_override_extra
{
    my $extra_override = shift;
    open(OVERRIDE, "<", $extra_override) or
        syserr(_g("Couldn't open override file %s"), $extra_override);

    while (<OVERRIDE>) {
	s/\#.*//;
	s/\s+$//;
	next unless $_;

	my ($p, $field, $value) = split(/\s+/, $_, 3);
        $Extra_Override{$p}{$field} = $value;
    }
    close(OVERRIDE);
}

# Given PREFIX and DSC-FILE, process the file and returns the fields.

sub process_dsc {
    my ($prefix, $file) = @_;

    # Parse ‘.dsc’ file.
    open(CDATA, '<', $file) || syserr(_g("cannot open %s"), $file);
    my $fields = parsecdata(\*CDATA,
                            sprintf(_g("source control file %s"), $file),
                            allow_pgp => 1);
    error(_g("parsing an empty file %s"), $file) unless (defined $fields);
    close(CDATA) || syserr(_g("cannot close %s"), $file);

    # Get checksums
    my $size;
    my $sums = {};
    getchecksums($file, $sums, \$size);

    my $source = $fields->{Source};
    my @binary = split /\s*,\s*/, $fields->{Binary};

    error(_g("no binary packages specified in %s"), $file) unless (@binary);

    # Rename the source field to package.
    $fields->{Package} = $fields->{Source};
    delete $fields->{Source};

    # The priority for the source package is the highest priority of the
    # binary packages it produces.
    my @binary_by_priority = sort {
	    ($Override{$a} ? $Priority{$Override{$a}[O_PRIORITY]} : 0)
		<=>
	    ($Override{$b} ? $Priority{$Override{$b}[O_PRIORITY]} : 0)
	} @binary;
    my $priority_override = $Override{$binary_by_priority[-1]};
    my $priority = $priority_override
			? $priority_override->[O_PRIORITY]
			: undef;
    $fields->{Priority} = $priority if defined $priority;

    # For the section override, first check for a record from the source
    # override file, else use the regular override file.
    my $section_override = $Override{"source/$source"} || $Override{$source};
    my $section = $section_override
			? $section_override->[O_SECTION]
			: undef;
    $fields->{Section} = $section if defined $section;

    # For the maintainer override, use the override record for the first
    # binary. Modify the maintainer if necessary.
    my $maintainer_override = $Override{$binary[0]};
    if ($maintainer_override && defined $maintainer_override->[O_MAINT_TO]) {
        if (!defined $maintainer_override->[O_MAINT_FROM] ||
            grep { $fields->{Maintainer} eq $_ }
                @{ $maintainer_override->[O_MAINT_FROM] }) {
            $fields->{Maintainer} = $maintainer_override->[O_MAINT_TO];
        }
    }

    # Process extra override
    if (exists $Extra_Override{$source}) {
        my ($field, $value);
        while(($field, $value) = each %{$Extra_Override{$source}}) {
            $fields->{$field} = $value;
        }
    }

    # A directory field will be inserted just before the files field.
    my $dir;
    $dir = ($file =~ s-(.*)/--) ? $1 : '';
    $dir = "$prefix$dir";
    $dir =~ s-/+$--;
    $dir = '.' if $dir eq '';
    $fields->{Directory} = $dir;

    # The files field will get an entry for the .dsc file itself.
    foreach my $alg (@check_supported) {
        if ($alg eq "md5") {
            $fields->{Files} =~ s/^\n/\n $sums->{$alg} $size $file\n/;
        } else {
            my $name = "Checksums-" . ucfirst($alg);
            $fields->{$name} =~ s/^\n/\n $sums->{$alg} $size $file\n/
                if defined $fields->{$name};
        }
    }

    return $fields;
}

# FIXME: Try to reuse from Dpkg::Source::Package
use Dpkg::Deps qw(@src_dep_fields);
my @src_fields = (qw(Format Package Binary Architecture Version Origin
                     Maintainer Uploaders Dm-Upload-Allowed Homepage
                     Standards-Version Vcs-Browser Vcs-Arch Vcs-Bzr
                     Vcs-Cvs Vcs-Darcs Vcs-Git Vcs-Hg Vcs-Mtn Vcs-Svn),
                  @src_dep_fields,
                  qw(Directory Files Checksums-Md5 Checksums-Sha1 Checksums-Sha256));

sub main {
    my (@out);

    init;
    @ARGV >= 1 && @ARGV <= 3 or usageerr(_g("1 to 3 args expected\n"));

    push @ARGV, undef		if @ARGV < 2;
    push @ARGV, ''		if @ARGV < 3;
    my ($dir, $override, $prefix) = @ARGV;

    load_override $override if defined $override;
    load_src_override $Src_override, $override;
    load_extra_override $Extra_override_file if defined $Extra_override_file;

    open FIND, "find \Q$dir\E -follow -name '*.dsc' -print |"
        or syserr(_g("cannot fork for %s"), "find");
    while (<FIND>) {
    	chomp;
	s-^\./+--;

        my $fields;

        # FIXME: Fix it instead to not die on syntax and general errors?
        eval {
            $fields = process_dsc($prefix, $_);
        };
        if ($@) {
            warn $@;
            next;
        }

        tied(%{$fields})->set_field_importance(@src_fields);
	if ($No_sort) {
            tied(%{$fields})->output(\*STDOUT);
            print "\n";
	}
	else {
            push @out, $fields;
	}
    }
    close FIND or error(close_msg, 'find');

    if (@out) {
        map {
            tied(%{$_})->output(\*STDOUT);
            print "\n";
        } sort {
            $a->{Package} cmp $b->{Package}
        } @out;
    }

    return 0;
}

$Exit = main || $Exit;
$Exit = 1 if $Exit and not $Exit % 256;
exit $Exit;
