# Copyright © 2008 Raphaël Hertzog <hertzog@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::Source::Package;

use strict;
use warnings;

our $VERSION = "0.01";

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Control;
use Dpkg::Checksums;
use Dpkg::Version;
use Dpkg::Compression;
use Dpkg::Exit;
use Dpkg::Path qw(check_files_are_the_same);
use Dpkg::IPC;
use Dpkg::Vendor qw(run_vendor_hook);

use POSIX;
use File::Basename;

# Public variables
our $diff_ignore_default_regexp = '
# Ignore general backup files
(?:^|/).*~$|
# Ignore emacs recovery files
(?:^|/)\.#.*$|
# Ignore vi swap files
(?:^|/)\..*\.sw.$|
# Ignore baz-style junk files or directories
(?:^|/),,.*(?:$|/.*$)|
# local-options must not be exported in the resulting source package
(?:^|/)debian/source/local-options$|
# File-names that should be ignored (never directories)
(?:^|/)(?:DEADJOE|\.arch-inventory|\.(?:bzr|cvs|hg|git)ignore)$|
# File or directory names that should be ignored
(?:^|/)(?:CVS|RCS|\.deps|\{arch\}|\.arch-ids|\.svn|\.hg(?:tags)?|_darcs|\.git(?:attributes)?|
\.shelf|_MTN|\.be|\.bzr(?:\.backup|tags)?)(?:$|/.*$)
';
# Take out comments and newlines
$diff_ignore_default_regexp =~ s/^#.*$//mg;
$diff_ignore_default_regexp =~ s/\n//sg;
no warnings 'qw';
our @tar_ignore_default_pattern = qw(
*.a
*.la
*.o
*.so
.*.sw?
*/*~
,,*
.[#~]*
.arch-ids
.arch-inventory
.be
.bzr
.bzr.backup
.bzr.tags
.bzrignore
.cvsignore
.deps
.git
.gitattributes
.gitignore
.hg
.hgignore
.hgtags
.shelf
.svn
CVS
DEADJOE
RCS
_MTN
_darcs
{arch}
);

# Object methods
sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = {
        'fields' => Dpkg::Control->new(type => CTRL_PKG_SRC),
        'options' => {},
	'checksums' => Dpkg::Checksums->new(),
    };
    bless $self, $class;
    if (exists $args{'options'}) {
        $self->{'options'} = $args{'options'};
    }
    if (exists $args{"filename"}) {
        $self->initialize($args{"filename"});
        $self->init_options();
    }
    return $self;
}

sub init_options {
    my ($self) = @_;
    # Use full ignore list by default
    # note: this function is not called by V1 packages
    $self->{'options'}{'diff_ignore_regexp'} ||= $diff_ignore_default_regexp;
    if (defined $self->{'options'}{'tar_ignore'}) {
        $self->{'options'}{'tar_ignore'} = [ @tar_ignore_default_pattern ]
            unless @{$self->{'options'}{'tar_ignore'}};
    } else {
        $self->{'options'}{'tar_ignore'} = [ @tar_ignore_default_pattern ];
    }
    push @{$self->{'options'}{'tar_ignore'}}, "debian/source/local-options";
    # Skip debianization while specific to some formats has an impact
    # on code common to all formats
    $self->{'options'}{'skip_debianization'} ||= 0;
}

sub initialize {
    my ($self, $filename) = @_;
    my ($fn, $dir) = fileparse($filename);
    error(_g("%s is not the name of a file"), $filename) unless $fn;
    $self->{'basedir'} = $dir || "./";
    $self->{'filename'} = $fn;

    # Check if it contains a signature
    open(DSC, "<", $filename) || syserr(_g("cannot open %s"), $filename);
    $self->{'is_signed'} = 0;
    while (<DSC>) {
        next if /^\s*$/o;
        $self->{'is_signed'} = 1 if /^-----BEGIN PGP SIGNED MESSAGE-----\s*$/o;
        last;
    }
    close(DSC);
    # Read the fields
    my $fields = Dpkg::Control->new(type => CTRL_PKG_SRC);
    $fields->load($filename);
    $self->{'fields'} = $fields;

    foreach my $f (qw(Source Version Files)) {
        unless (defined($fields->{$f})) {
            error(_g("missing critical source control field %s"), $f);
        }
    }

    $self->{'checksums'}->add_from_control($fields, use_files_for_md5 => 1);

    $self->upgrade_object_type(0);
}

sub upgrade_object_type {
    my ($self, $update_format) = @_;
    $update_format = 1 unless defined $update_format;
    $self->{'fields'}{'Format'} = '1.0'
        unless exists $self->{'fields'}{'Format'};
    my $format = $self->{'fields'}{'Format'};

    if ($format =~ /^([\d\.]+)(?:\s+\((.*)\))?$/) {
        my ($version, $variant, $major, $minor) = ($1, $2, $1, undef);
        $major =~ s/\.[\d\.]+$//;
        my $module = "Dpkg::Source::Package::V$major";
        $module .= "::$variant" if defined $variant;
        eval "require $module; \$minor = \$${module}::CURRENT_MINOR_VERSION;";
        $minor = 0 unless defined $minor;
        if ($update_format) {
            $self->{'fields'}{'Format'} = "$major.$minor";
            $self->{'fields'}{'Format'} .= " ($variant)" if defined $variant;
        }
        if ($@) {
	    error(_g("source package format `%s' is not supported (Perl module %s is required)"), $format, $module);
        }
        bless $self, $module;
    } else {
        error(_g("invalid Format field `%s'"), $format);
    }
}

sub get_filename {
    my ($self) = @_;
    return $self->{'basedir'} . $self->{'filename'};
}

sub get_files {
    my ($self) = @_;
    return $self->{'checksums'}->get_files();
}

sub check_checksums {
    my ($self) = @_;
    my $checksums = $self->{'checksums'};
    # add_from_file verify the checksums if they are already existing
    foreach my $file ($checksums->get_files()) {
	$checksums->add_from_file($self->{'basedir'} . $file, key => $file);
    }
}

sub get_basename {
    my ($self, $with_revision) = @_;
    my $f = $self->{'fields'};
    unless (exists $f->{'Source'} and exists $f->{'Version'}) {
        error(_g("source and version are required to compute the source basename"));
    }
    my $v = Dpkg::Version->new($f->{'Version'});
    my $basename = $f->{'Source'} . "_" . $v->version();
    if ($with_revision and $f->{'Version'} =~ /-/) {
        $basename .= "-" . $v->revision();
    }
    return $basename;
}

sub find_original_tarballs {
    my ($self, %opts) = @_;
    $opts{extension} = $compression_re_file_ext unless exists $opts{extension};
    $opts{include_main} = 1 unless exists $opts{include_main};
    $opts{include_supplementary} = 1 unless exists $opts{include_supplementary};
    my $basename = $self->get_basename();
    my @tar;
    foreach my $dir (".", $self->{'basedir'}, $self->{'options'}{'origtardir'}) {
        next unless defined($dir) and -d $dir;
        opendir(DIR, $dir) || syserr(_g("cannot opendir %s"), $dir);
        push @tar, map { "$dir/$_" } grep {
		($opts{include_main} and
		 /^\Q$basename\E\.orig\.tar\.$opts{extension}$/) or
		($opts{include_supplementary} and
		 /^\Q$basename\E\.orig-[[:alnum:]-]+\.tar\.$opts{extension}$/)
	    } readdir(DIR);
        closedir(DIR);
    }
    return @tar;
}

sub is_signed {
    my $self = shift;
    return $self->{'is_signed'};
}

sub check_signature {
    my ($self) = @_;
    my $dsc = $self->get_filename();
    my @exec;
    if (-x '/usr/bin/gpgv') {
        push @exec, "gpgv";
    } elsif (-x '/usr/bin/gpg') {
        push @exec, "gpg", "--no-default-keyring", "-q", "--verify";
    }
    if (scalar(@exec)) {
        if (-r "$ENV{'HOME'}/.gnupg/trustedkeys.gpg") {
            push @exec, "--keyring", "$ENV{'HOME'}/.gnupg/trustedkeys.gpg";
        }
        foreach my $vendor_keyring (run_vendor_hook('keyrings')) {
            if (-r $vendor_keyring) {
                push @exec, "--keyring", $vendor_keyring;
            }
        }
        push @exec, $dsc;

        my ($stdout, $stderr);
        spawn('exec' => \@exec, wait_child => 1, nocheck => 1,
              to_string => \$stdout, error_to_string => \$stderr,
              timeout => 10);
        if (WIFEXITED($?)) {
            my $gpg_status = WEXITSTATUS($?);
            print STDERR "$stdout$stderr" if $gpg_status;
            if ($gpg_status == 1 or ($gpg_status &&
                $self->{'options'}{'require_valid_signature'}))
            {
                error(_g("failed to verify signature on %s"), $dsc);
            } elsif ($gpg_status) {
                warning(_g("failed to verify signature on %s"), $dsc);
            }
        } else {
            subprocerr("@exec");
        }
    } else {
        if ($self->{'options'}{'require_valid_signature'}) {
            error(_g("could not verify signature on %s since gpg isn't installed"), $dsc);
        } else {
            warning(_g("could not verify signature on %s since gpg isn't installed"), $dsc);
        }
    }
}

sub parse_cmdline_options {
    my ($self, @opts) = @_;
    foreach (@opts) {
        if (not $self->parse_cmdline_option($_)) {
            warning(_g("%s is not a valid option for %s"), $_, ref($self));
        }
    }
}

sub parse_cmdline_option {
    return 0;
}

sub extract {
    my $self = shift;
    my $newdirectory = $_[0];

    my ($ok, $error) = version_check($self->{'fields'}{'Version'});
    error($error) unless $ok;

    # Copy orig tarballs
    if ($self->{'options'}{'copy_orig_tarballs'}) {
        my $basename = $self->get_basename();
        my ($dirname, $destdir) = fileparse($newdirectory);
        $destdir ||= "./";
	my $ext = $compression_re_file_ext;
        foreach my $orig (grep { /^\Q$basename\E\.orig(-[[:alnum:]-]+)?\.tar\.$ext$/ }
                          $self->get_files())
        {
            my $src = File::Spec->catfile($self->{'basedir'}, $orig);
            my $dst = File::Spec->catfile($destdir, $orig);
            if (not check_files_are_the_same($src, $dst, 1)) {
                system('cp', '--', $src, $dst);
                subprocerr("cp $src to $dst") if $?;
            }
        }
    }

    # Try extract
    eval { $self->do_extract(@_) };
    if ($@) {
        &$_() foreach reverse @Dpkg::Exit::handlers;
        die $@;
    }

    # Store format if non-standard so that next build keeps the same format
    if ($self->{'fields'}{'Format'} ne "1.0" and
        not $self->{'options'}{'skip_debianization'})
    {
        my $srcdir = File::Spec->catdir($newdirectory, "debian", "source");
        my $format_file = File::Spec->catfile($srcdir, "format");
	unless (-e $format_file) {
	    mkdir($srcdir) unless -e $srcdir;
	    open(FORMAT, ">", $format_file) || syserr(_g("cannot write %s"), $format_file);
	    print FORMAT $self->{'fields'}{'Format'} . "\n";
	    close(FORMAT);
	}
    }

    # Make sure debian/rules is executable
    my $rules = File::Spec->catfile($newdirectory, "debian", "rules");
    my @s = lstat($rules);
    if (not scalar(@s)) {
        unless ($! == ENOENT) {
            syserr(_g("cannot stat %s"), $rules);
        }
        warning(_g("%s does not exist"), $rules)
            unless $self->{'options'}{'skip_debianization'};
    } elsif (-f _) {
        chmod($s[2] | 0111, $rules) ||
            syserr(_g("cannot make %s executable"), $rules);
    } else {
        warning(_g("%s is not a plain file"), $rules);
    }
}

sub do_extract {
    internerr("Dpkg::Source::Package doesn't know how to unpack a " .
              "source package. Use one of the subclasses.");
}

# Function used specifically during creation of a source package

sub before_build {
    my ($self, $dir) = @_;
}

sub build {
    my $self = shift;
    eval { $self->do_build(@_) };
    if ($@) {
        &$_() foreach reverse @Dpkg::Exit::handlers;
        die $@;
    }
}

sub after_build {
    my ($self, $dir) = @_;
}

sub do_build {
    internerr("Dpkg::Source::Package doesn't know how to build a " .
              "source package. Use one of the subclasses.");
}

sub can_build {
    my ($self, $dir) = @_;
    return (0, "can_build() has not been overriden");
}

sub add_file {
    my ($self, $filename) = @_;
    my ($fn, $dir) = fileparse($filename);
    if ($self->{'checksums'}->has_file($fn)) {
        internerr("tried to add file '%s' twice", $fn);
    }
    $self->{'checksums'}->add_from_file($filename, key => $fn);
    $self->{'checksums'}->export_to_control($self->{'fields'},
					    use_files_for_md5 => 1);
}

sub write_dsc {
    my ($self, %opts) = @_;
    my $fields = $self->{'fields'};

    foreach my $f (keys %{$opts{'override'}}) {
	$fields->{$f} = $opts{'override'}{$f};
    }

    unless($opts{'nocheck'}) {
        foreach my $f (qw(Source Version)) {
            unless (defined($fields->{$f})) {
                error(_g("missing information for critical output field %s"), $f);
            }
        }
        foreach my $f (qw(Maintainer Architecture Standards-Version)) {
            unless (defined($fields->{$f})) {
                warning(_g("missing information for output field %s"), $f);
            }
        }
    }

    foreach my $f (keys %{$opts{'remove'}}) {
	delete $fields->{$f};
    }

    my $filename = $opts{'filename'};
    unless (defined $filename) {
        $filename = $self->get_basename(1) . ".dsc";
    }
    open(DSC, ">", $filename) || syserr(_g("cannot write %s"), $filename);
    $fields->apply_substvars($opts{'substvars'});
    $fields->output(\*DSC);
    close(DSC);
}

# vim: set et sw=4 ts=8
1;
