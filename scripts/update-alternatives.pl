#!/usr/bin/perl --

BEGIN { # Work-around for bug #479711 in perl
    $ENV{PERL_DL_NONLAZY} = 1;
}

use strict;
use warnings;

use POSIX qw(:errno_h);
use Dpkg;
use Dpkg::Gettext;

textdomain("dpkg");

# Global variables:

my $altdir = '/etc/alternatives';
my $admdir = $admindir . '/alternatives';

my $action = '';      # Action to perform (display / query / install / remove / auto / config)
my $alternative;      # Alternative worked on
my $inst_alt;         # Alternative to install
my $fileset;          # Set of files to install in the alternative
my $path;             # Path of alternative we are offering
my $log_file = "/var/log/dpkg.log";
my $skip_auto = 0;    # Skip alternatives properly configured in auto mode (for --config)
my $verbosemode = 0;
my $force = 0;
my @pass_opts;

$| = 1;

#
# Main program
#

my @COPY_ARGV = @ARGV;
while (@ARGV) {
    $_ = shift(@ARGV);
    last if m/^--$/;
    if (!m/^--/) {
        error(_g("unknown argument \`%s'"), $_);
    } elsif (m/^--help$/) {
        usage();
        exit(0);
    } elsif (m/^--version$/) {
        version();
        exit(0);
    } elsif (m/^--verbose$/) {
        $verbosemode= +1;
        push @pass_opts, $_;
    } elsif (m/^--quiet$/) {
        $verbosemode= -1;
        push @pass_opts, $_;
    } elsif (m/^--install$/) {
	set_action("install");
        @ARGV >= 4 || badusage(_g("--install needs <link> <name> <path> <priority>"));
        my $link = shift @ARGV;
        my $name = shift @ARGV;
        my $path = shift @ARGV;
        my $priority = shift @ARGV;
        badusage(_g("<link> and <path> can't be the same")) if $link eq $path;
        $priority =~ m/^[-+]?\d+/ || badusage(_g("priority must be an integer"));
        $alternative = Alternative->new($name);
        $inst_alt = Alternative->new($name);
        $inst_alt->set_status("auto");
        $inst_alt->set_link($link);
        $fileset = FileSet->new($path, $priority);
    } elsif (m/^--(remove|set)$/) {
	set_action($1);
        @ARGV >= 2 || badusage(_g("--%s needs <name> <path>"), $1);
        $alternative = Alternative->new(shift(@ARGV));
        $path = shift @ARGV;
    } elsif (m/^--(display|query|auto|config|list|remove-all)$/) {
	set_action($1);
        @ARGV || badusage(_g("--%s needs <name>"), $1);
        $alternative = Alternative->new(shift(@ARGV));
    } elsif (m/^--(all|get-selections|set-selections)$/) {
	set_action($1);
    } elsif (m/^--slave$/) {
        badusage(_g("--slave only allowed with --install"))
            unless $action eq "install";
        @ARGV >= 3 || badusage(_g("--slave needs <link> <name> <path>"));
        my $slink = shift @ARGV;
        my $sname = shift @ARGV;
        my $spath = shift @ARGV;
        badusage(_g("<link> and <path> can't be the same")) if $slink eq $spath;
        badusage(_g("name %s is both primary and slave"), $inst_alt->name())
            if $sname eq $inst_alt->name();
        if ($inst_alt->has_slave($sname)) {
            badusage(_g("slave name %s duplicated"), $sname);
        }
        foreach my $slave ($inst_alt->slaves()) {
            my $link = $inst_alt->slave_link($slave) || "";
            badusage(_g("slave link %s duplicated"), $slink) if $link eq $slink;
            badusage(_g("link %s is both primary and slave"), $slink)
                if $link eq $inst_alt->link();
        }
        $inst_alt->add_slave($sname, $slink);
        $fileset->add_slave($sname, $spath);
    } elsif (m/^--log$/) {
        @ARGV || badusage(_g("--%s needs a <file> argument"), "log");
        $log_file = shift @ARGV;
        push @pass_opts, $_, $log_file;
    } elsif (m/^--altdir$/) {
        @ARGV || badusage(_g("--%s needs a <directory> argument"), "altdir");
        $altdir = shift @ARGV;
        push @pass_opts, $_, $altdir;
    } elsif (m/^--admindir$/) {
        @ARGV || badusage(_g("--%s needs a <directory> argument"), "admindir");
        $admdir = shift @ARGV;
        push @pass_opts, $_, $admdir;
    } elsif (m/^--skip-auto$/) {
	$skip_auto = 1;
        push @pass_opts, $_;
    } elsif (m/^--force$/) {
	$force = 1;
        push @pass_opts, $_;
    } else {
        badusage(_g("unknown option \`%s'"), $_);
    }
}

badusage(_g("need --display, --query, --list, --get-selections, --config," .
            "--set, --set-selections, --install, --remove, --all, " .
            "--remove-all or --auto"))
    unless $action;

# Load infos about all alternatives to be able to check for mistakes
my %ALL;
foreach my $alt_name (get_all_alternatives()) {
    my $alt = Alternative->new($alt_name);
    next unless $alt->load("$admdir/$alt_name", 1);
    $ALL{objects}{$alt_name} = $alt;
    $ALL{links}{$alt->link()} = $alt_name;
    $ALL{parent}{$alt_name} = $alt_name;
    foreach my $slave ($alt->slaves()) {
        $ALL{links}{$alt->slave_link($slave)} = $slave;
        $ALL{parent}{$slave} = $alt_name;
    }
}
# Check that caller don't mix links between alternatives and don't mix
# alternatives between slave/master, and that the various parameters
# are fine
if ($action eq "install") {
    my ($name, $link, $file) = ($inst_alt->name(), $inst_alt->link(), $fileset->master());
    if (exists $ALL{parent}{$name} and $ALL{parent}{$name} ne $name) {
        error(_g("alternative %s can't be master: %s"), $name,
              sprintf(_g("it is a slave of %s"), $ALL{parent}{$name}));
    }
    if (exists $ALL{links}{$link} and $ALL{links}{$link} ne $name) {
        error(_g("alternative link %s is already managed by %s."),
              $link, $ALL{parent}{$ALL{links}{$link}});
    }
    error(_g("alternative link is not absolute as it should be: %s"),
          $link) unless $link =~ m|^/|;
    error(_g("alternative path is not absolute as it should be: %s"),
          $file) unless $file =~ m|^/|;
    error(_g("alternative path %s doesn't exist."), $file)
        unless -e $file;
    error(_g("alternative name (%s) must not contain '/' and spaces."), $name)
        if $name =~ m|[/\s]|;
    foreach my $slave ($inst_alt->slaves()) {
        $link = $inst_alt->slave_link($slave);
        $file = $fileset->slave($slave);
        if (exists $ALL{parent}{$slave} and $ALL{parent}{$slave} ne $name) {
            error(_g("alternative %s can't be slave of %s: %s"),
                  $slave, $name, ($ALL{parent}{$slave} eq $slave) ?
                      _g("it is a master alternative.") :
                      sprintf(_g("it is a slave of %s"), $ALL{parent}{$slave})
                 );
        }
        if (exists $ALL{links}{$link} and $ALL{links}{$link} ne $slave) {
            error(_g("alternative link %s is already managed by %s."),
                  $link, $ALL{parent}{$ALL{links}{$link}});
        }
        error(_g("alternative link is not absolute as it should be: %s"),
              $link) unless $link =~ m|^/|;
        error(_g("alternative path is not absolute as it should be: %s"),
              $file) unless $file =~ m|^/|;
        error(_g("alternative name (%s) must not contain '/' and spaces."), $slave)
            if $slave =~ m|[/\s]|;
    }
}

# Handle actions
if ($action eq 'all') {
    config_all();
    exit 0;
} elsif ($action eq 'get-selections') {
    foreach my $alt_name (sort keys %{$ALL{objects}}) {
        my $obj = $ALL{objects}{$alt_name};
        printf "%-30s %-8s %s\n", $alt_name, $obj->status(), $obj->current() || "";
    }
    exit 0;
} elsif ($action eq 'set-selections') {
    log_msg("run with @COPY_ARGV");
    my $line;
    my $prefix = "[$progname --set-selections] ";
    while (defined($line = <STDIN>)) {
        chomp($line);
        my ($alt_name, $status, $choice) = split(/\s+/, $line, 3);
        if (exists $ALL{objects}{$alt_name}) {
            my $obj = $ALL{objects}{$alt_name};
            if ($status eq "auto") {
                pr($prefix . _g("Call %s."), "$0 --auto $alt_name");
                system($0, @pass_opts, "--auto", $alt_name);
                exit $? if $?;
            } else {
                if ($obj->has_choice($choice)) {
                    pr($prefix . _g("Call %s."), "$0 --set $alt_name $choice");
                    system($0, @pass_opts, "--set", $alt_name, $choice);
                    exit $? if $?;
                } else {
                    pr($prefix . _g("Alternative %s unchanged because choice " .
                       "%s is not available."), $alt_name, $choice);
                }
            }
        } else {
            pr($prefix . _g("Skip unknown alternative %s."), $alt_name);
        }
    }
    exit 0;
}


# Load the alternative info, stop on failure except for --install
if (not $alternative->load("$admdir/" . $alternative->name())
    and $action ne "install")
{
    # FIXME: Be consistent for now with the case when we try to remove a
    # non-existing path from an existing link group file.
    if ($action eq "remove") {
        verbose(_g("no alternatives for %s."), $alternative->name());
        exit 0;
    }
    error(_g("no alternatives for %s."), $alternative->name());
}

if ($action eq 'display') {
    $alternative->display_user();
    exit 0;
} elsif ($action eq 'query') {
    $alternative->display_query();
    exit 0;
} elsif ($action eq 'list') {
    $alternative->display_list();
    exit 0;
}

# Actions below might modify the system
log_msg("run with @COPY_ARGV");

my $current_choice = '';
if ($alternative->has_current_link()) {
    $current_choice = $alternative->current();
    # Detect manually modified alternative, switch to manual
    if (not $alternative->has_choice($current_choice)) {
        if (not -e $current_choice) {
            warning(_g("%s is dangling, it will be updated with best choice."),
                    "$altdir/" . $alternative->name());
            $alternative->set_status('auto');
        } elsif ($alternative->status() ne "manual") {
            warning(_g("%s has been changed (manually or by a script). " .
                    "Switching to manual updates only."),
                    "$altdir/" . $alternative->name());
            $alternative->set_status('manual');
        }
    }
} else {
    # Lack of alternative link => automatic mode
    verbose(_g("setting up automatic selection of %s."), $alternative->name());
    $alternative->set_status('auto');
}

my $new_choice;
if ($action eq 'set') {
    $alternative->set_status('manual');
    $new_choice = $path;
} elsif ($action eq 'auto') {
    $alternative->set_status('auto');
    $new_choice = $alternative->best();
} elsif ($action eq 'config') {
    if (not scalar($alternative->choices())) {
        pr(_g("There is no program which provides %s."), $alternative->name());
        pr(_g("Nothing to configure."));
    } elsif ($skip_auto && $alternative->status() eq 'auto') {
        $alternative->display_user();
    } elsif (scalar($alternative->choices()) == 1 and
             $alternative->status() eq 'auto' and
             $alternative->has_current_link()) {
        pr(_g("There is only one alternative in link group %s: %s"),
           $alternative->name(), $alternative->current());
        pr(_g("Nothing to configure."));
    } else {
        $new_choice = $alternative->select_choice();
    }
} elsif ($action eq 'remove') {
    if ($alternative->has_choice($path)) {
        $alternative->remove_choice($path);
    } else {
        verbose(_g("alternative %s for %s not registered, not removing."),
                $path, $alternative->name());
    }
    if ($current_choice eq $path) {
        # Current choice is removed
        if ($alternative->status() eq "manual") {
            # And it was manual, switch to auto
            info(_g("removing manually selected alternative - " .
                    "switching %s to auto mode"), $alternative->name());
            $alternative->set_status('auto');
        }
        $new_choice = $alternative->best();
    }
} elsif ($action eq 'remove-all') {
    foreach my $choice ($alternative->choices()) {
        $alternative->remove_choice($choice);
    }
} elsif ($action eq 'install') {
    if (defined($alternative->link())) {
        # Alternative already exists, check if anything got updated
        my ($old, $new) = ($alternative->link(), $inst_alt->link());
        $alternative->set_link($new);
        if ($old ne $new and -l $old) {
            info(_g("renaming %s link from %s to %s."), $inst_alt->name(),
                 $old, $new);
            checked_mv($old, $new);
        }
        # Check if new slaves have been added, or existing ones renamed
        foreach my $slave ($inst_alt->slaves()) {
            $new = $inst_alt->slave_link($slave);
            if (not $alternative->has_slave($slave)) {
                $alternative->add_slave($slave, $new);
                next;
            }
            $old = $alternative->slave_link($slave);
            $alternative->add_slave($slave, $new);
            my $new_file = ($current_choice eq $fileset->master()) ?
                            $fileset->slave($slave) :
                            readlink("$admdir/$slave") || "";
            if ($old ne $new and -l $old) {
                if (-e $new_file) {
                    info(_g("renaming %s slave link from %s to %s."),
                         $slave,$old, $new);
                    checked_mv($old, $new);
                } else {
                    checked_rm($old);
                }
            }
        }
    } else {
        # Alternative doesn't exist, create from parameters
        $alternative = $inst_alt;
    }
    $alternative->add_choice($fileset);
    if ($alternative->status() eq "auto") {
        # Update automatic choice if needed
        $new_choice = $alternative->best();
    } else {
        verbose(_g("automatic updates of %s are disabled, leaving it alone."),
                "$altdir/" . $alternative->name());
        verbose(_g("to return to automatic updates use ".
                   "\`update-alternatives --auto %s'."), $alternative->name());
    }
}

# No choice left, remove everything
if (not scalar($alternative->choices())) {
    log_msg("link group " . $alternative->name() . " fully removed");
    $alternative->remove();
    exit 0;
}

# New choice wanted
if (defined($new_choice) and ($current_choice ne $new_choice)) {
    log_msg("link group " . $alternative->name() .
            " updated to point to " . $new_choice);
    info(_g("using %s to provide %s (%s) in %s."), $new_choice,
         $alternative->link(), $alternative->name(),
         ($alternative->status() eq "auto" ? _g("auto mode") : _g("manual mode")));
    $alternative->prepare_install($new_choice);
} elsif ($alternative->is_broken()) {
    log_msg("auto-repair link group " . $alternative->name());
    warning(_g("forcing reinstallation of alternative %s " .
               "because link group %s is broken."),
            $current_choice, $alternative->name());
    $alternative->prepare_install($current_choice) if $current_choice;
}

# Save administrative file if needed
if ($alternative->is_modified()) {
    $alternative->save("$admdir/" . $alternative->name() . ".dpkg-tmp");
    checked_mv("$admdir/" . $alternative->name() . ".dpkg-tmp",
               "$admdir/" . $alternative->name());
}

# Replace all symlinks in one pass
$alternative->commit();

exit 0;

### FUNCTIONS ####
sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1995 Ian Jackson.
Copyright (C) 2000-2002 Wichert Akkerman.
Copyright (C) 2009 Raphael Hertzog.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <command>

Commands:
  --install <link> <name> <path> <priority>
    [--slave <link> <name> <path>] ...
                           add a group of alternatives to the system.
  --remove <name> <path>   remove <path> from the <name> group alternative.
  --remove-all <name>      remove <name> group from the alternatives system.
  --auto <name>            switch the master link <name> to automatic mode.
  --display <name>         display information about the <name> group.
  --query <name>           machine parseable version of --display <name>.
  --list <name>            display all targets of the <name> group.
  --config <name>          show alternatives for the <name> group and ask the
                           user to select which one to use.
  --set <name> <path>      set <path> as alternative for <name>.
  --all                    call --config on all alternatives.

<link> is the symlink pointing to %s/<name>.
  (e.g. /usr/bin/pager)
<name> is the master name for this link group.
  (e.g. pager)
<path> is the location of one of the alternative target files.
  (e.g. /usr/bin/less)
<priority> is an integer; options with higher numbers have higher priority in
  automatic mode.

Options:
  --altdir <directory>     change the alternatives directory.
  --admindir <directory>   change the administrative directory.
  --skip-auto              skip prompt for alternatives correctly configured
                           in automatic mode (relevant for --config only)
  --verbose                verbose operation, more output.
  --quiet                  quiet operation, minimal output.
  --help                   show this help message.
  --version                show the version.
"), $progname, $altdir;
}

sub error {
    my ($format, @params) = @_;
    $! = 2;
    die sprintf("%s: %s: %s\n", $progname, _g("error"),
                sprintf($format, @params));
}

sub badusage {
    my ($format, @params) = @_;
    printf STDERR "%s: %s\n\n", $progname, sprintf($format, @params);
    usage();
    exit(2);
}

sub warning {
    my ($format, @params) = @_;
    if ($verbosemode >= 0) {
        printf STDERR "%s: %s: %s\n", $progname, _g("warning"),
                      sprintf($format, @params);
    }
}

sub msg {
    my ($min_level, $format, @params) = @_;
    if ($verbosemode >= $min_level) {
        printf STDOUT "%s: %s\n", $progname, sprintf($format, @params);
    }
}

sub verbose {
    msg(1, @_);
}

sub info {
    msg(0, @_);
}

sub pr {
    my ($format, @params) = @_;
    printf ($format . "\n", @params);
}

sub set_action {
    my ($value) = @_;
    if ($action) {
        badusage(_g("two commands specified: --%s and --%s"), $value, $action);
    }
    $action = $value;
}

{
    my $fh_log;
    sub log_msg {
        my ($msg) = @_;
        # XXX: the C rewrite must use the std function to get the
        # filename from /etc/dpkg/dpkg.cfg or from command line
        if (!defined($fh_log) and -w $log_file) {
            open($fh_log, ">>", $log_file) ||
                error(_g("Can't append to %s"), $log_file);
        }
        if (defined($fh_log)) {
            $msg = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime()) .
                   " $progname: $msg\n";
            print $fh_log $msg;
        }
    }
}

sub get_all_alternatives {
    opendir(ADMINDIR, $admdir)
        or error(_g("can't readdir %s: %s"), $admdir, $!);
    my @filenames = grep { !/^\.\.?$/ and !/\.dpkg-tmp$/ } (readdir(ADMINDIR));
    close(ADMINDIR);
    return sort @filenames;
}

sub config_all {
    foreach my $name (get_all_alternatives()) {
        system($0, @pass_opts, "--config", $name);
        exit $? if $?;
        print "\n";
    }
}

sub rename_mv {
    my ($source, $dest) = @_;
    lstat($source);
    return 0 if not -e _;
    if (not rename($source, $dest)) {
        if (system("mv", $source, $dest) != 0) {
            return 0;
        }
    }
    return 1;
}

sub checked_symlink {
    my ($filename, $linkname) = @_;
    symlink($filename, $linkname) ||
        error(_g("unable to make %s a symlink to %s: %s"), $linkname, $filename, $!);
}

sub checked_mv {
    my ($source, $dest) = @_;
    rename_mv($source, $dest) ||
        error(_g("unable to install %s as %s: %s"), $source, $dest, $!);
}

sub checked_rm {
    my ($f) = @_;
    unlink($f) || $! == ENOENT || error(_g("unable to remove %s: %s"), $f, $!);
}

### OBJECTS ####

package FileSet;

use Dpkg::Gettext;

sub new {
    my ($class, $master_file, $prio) = @_;
    my $self = {
        "master_file" => $master_file,
        "priority" => $prio,
        "slaves" =>
            {
                # "slave_name" => "slave_file"
            },
    };
    return bless $self, $class;
}
sub add_slave {
    my ($self, $name, $file) = @_;
    $self->{slaves}{$name} = $file;
}
sub has_slave {
    my ($self, $slave) = @_;
    return (exists $self->{"slaves"}{$slave} and $self->{"slaves"}{$slave});
}
sub master {
    my ($self, $val) = @_;
    return $self->{"master_file"};
}
sub priority {
    my ($self) = @_;
    return $self->{"priority"};
}
sub slave {
    my ($self, $slave) = @_;
    return $self->{"slaves"}{$slave};
}

package Alternative;

use Dpkg::Gettext;
use POSIX qw(:errno_h);

sub pr { main::pr(@_) }
sub error { main::error(@_) }

sub new {
    my ($class, $name) = @_;
    my $self = {};
    bless $self, $class;
    $self->reset($name);
    return $self;
}
sub reset {
    my ($self, $name) = @_;
    my $new = {
        "master_name" => $name,
        "master_link" => undef,
        "status" => undef,
        "slaves" => {
            # "slave_name" => "slave_link"
        },
        "choices" => {
            # "master_file" => $fileset
        },
        "modified" => 0,
        "commit_ops" => [],
    };
    %$self = %$new;
}
sub choices {
    my ($self) = @_;
    my @choices = sort { $a cmp $b } keys %{$self->{choices}};
    return wantarray ? @choices : scalar(@choices);
}
sub slaves {
    my ($self) = @_;
    my @slaves = sort { $a cmp $b } keys %{$self->{slaves}};
    return wantarray ? @slaves : scalar(@slaves);
}
sub name {
    my ($self) = @_;
    return $self->{master_name};
}
sub link {
    my ($self) = @_;
    return $self->{master_link};
}
sub status {
    my ($self) = @_;
    return $self->{status};
}
sub fileset {
    my ($self, $id) = @_;
    return $self->{choices}{$id} if exists $self->{choices}{$id};
    return undef;
}
sub slave_link {
    my ($self, $id) = @_;
    return $self->{slaves}{$id} if exists $self->{slaves}{$id};
    return undef;
}
sub has_slave {
    my ($self, $slave) = @_;
    return (exists $self->{"slaves"}{$slave} and $self->{"slaves"}{$slave});
}
sub is_modified {
    my ($self) = @_;
    return $self->{modified};
}
sub has_choice {
    my ($self, $id) = @_;
    return exists $self->{choices}{$id};
}
sub add_choice {
    my ($self, $fileset) = @_;
    $self->{choices}{$fileset->master()} = $fileset;
    $self->{modified} = 1; # XXX: be smarter in detecting change ?
}
sub add_slave {
    my ($self, $slave, $link) = @_;
    $self->{slaves}{$slave} = $link;
}
sub set_status {
    my ($self, $status) = @_;
    if (!defined($self->status()) or $status ne $self->status()) {
        $self->{modified} = 1;
    }
    main::log_msg("status of link group " . $self->name() . " set to $status")
        if defined($self->status()) and $status ne $self->status();
    $self->{status} = $status;
}
sub set_link {
    my ($self, $link) = @_;
    if (!defined($self->link()) or $link ne $self->link()) {
        $self->{modified} = 1;
    }
    $self->{master_link} = $link;
}
sub remove_choice {
    my ($self, $id) = @_;
    if ($self->has_choice($id)) {
        delete $self->{choices}{$id};
        $self->{modified} = 1;
        return 1;
    }
    return 0;
}

{
    # Helper functions for load() and save()
    my ($fh, $filename);
    sub config_helper {
        ($fh, $filename) = @_;
    }
    sub gl {
        undef $!;
        my $line = <$fh>;
        unless (defined($line)) {
            error(_g("while reading %s: %s"), $filename, $!) if $!;
            error(_g("unexpected end of file in %s while trying to read %s"),
                 $filename, $_[0]);
        }
        chomp($line);
        return $line;
    }
    sub badfmt {
        my ($format, @params) = @_;
        error(_g("%s corrupt: %s"), $filename, sprintf($format, @params));
    }
    sub paf {
        my $line = shift @_;
        if ($line =~ m/\n/) {
            error(_g("newlines prohibited in update-alternatives files (%s)"), $line);
        }
        print $fh "$line\n" || error(_g("while writing %s: %s"), $filename, $!);
    }
}

sub load {
    my ($self, $file, $must_not_die) = @_;
    return 0 unless -s $file;
    eval {
        open(my $fh, "<", $file) || error(_g("unable to read %s: %s"), $file, $!);
        config_helper($fh, $file);
	my $status = gl(_g("status"));
	badfmt(_g("invalid status")) unless $status =~ /^(?:auto|manual)$/;
	my $link = gl("link");
        my (%slaves, @slaves);
	while ((my $slave_name = gl(_g("slave name"))) ne '') {
	    my $slave_link = gl(_g("slave link"));
	    badfmt(_g("duplicate slave %s"), $slave_name)
                if exists $slaves{$slave_name};
	    badfmt(_g("slave link same as main link %s"), $link)
                if $slave_link eq $link;
            badfmt(_g("duplicate slave link %s"), $slave_link)
                if grep { $_ eq $slave_link } values %slaves;
            $slaves{$slave_name} = $slave_link;
            push @slaves, $slave_name;
	}
        my @filesets;
        my $modified = 0;
	while ((my $main_file = gl(_g("master file"))) ne '') {
	    badfmt(_g("duplicate path %s"), $main_file)
                if grep { $_->{master_file} eq $main_file } @filesets;
	    if (-e $main_file) {
		my $priority = gl(_g("priority"));
                badfmt(_g("priority of %s: %s"), $main_file, $priority)
                    unless $priority =~ m/^[-+]?\d+$/;
                my $group = FileSet->new($main_file, $priority);
                foreach my $slave (@slaves) {
                    $group->add_slave($slave, gl(_g("slave file")));
		}
                push @filesets, $group;
	    } else {
		# File not found - remove
		main::warning(_g("alternative %s (part of link group %s) " .
                                 "doesn't exist. Removing from list of ".
                                 "alternatives."),
                              $main_file, $self->name()) unless $must_not_die;
		gl(_g("priority"));
                foreach my $slave (@slaves) {
		    gl(_g("slave file"));
		}
                $modified = 1;
	    }
	}
        close($fh);
        # We parsed the file without trouble, load data into the object
        $self->{master_link} = $link;
        $self->{slaves} = \%slaves;
        $self->{status} = $status;
        $self->{modified} = $modified;
        $self->{choices} = {};
        foreach my $group (@filesets) {
            $self->{choices}{$group->master()} = $group;
        }
    };
    if ($@) {
        return 0 if $must_not_die;
        die $@;
    }
    return 1;
}

sub save {
    my ($self, $file) = @_;
    # Cleanup unused slaves before writing admin file
    foreach my $slave ($self->slaves()) {
        my $has_slave = 0;
        foreach my $choice ($self->choices()) {
            my $fileset = $self->fileset($choice);
            $has_slave++ if $fileset->has_slave($slave);
        }
        unless ($has_slave) {
            main::verbose(_g("discarding obsolete slave link %s (%s)."),
                          $slave, $self->slave_link($slave));
            delete $self->{"slaves"}{$slave};
        }
    }
    # Write admin file
    open(my $fh, ">", $file) || error(_g("unable to write %s: %s"), $file, $!);
    config_helper($fh, $file);
    paf($self->status());
    paf($self->link());
    foreach my $slave ($self->slaves()) {
        paf($slave);
        paf($self->slave_link($slave));
    }
    paf('');
    foreach my $choice ($self->choices()) {
        paf($choice);
        my $fileset = $self->fileset($choice);
        paf($fileset->priority());
        foreach my $slave ($self->slaves()) {
            if ($fileset->has_slave($slave)) {
                paf($fileset->slave($slave));
            } else {
                paf('');
            }
        }
    }
    paf('');
    close($fh) || error(_g("unable to close %s: %s"), $file, $!);
}

sub display_query {
    my ($self) = @_;
    pr("Link: %s", $self->name());
    pr("Status: %s", $self->status());
    my $best = $self->best();
    if (defined($best)) {
	pr("Best: %s", $best);
    }
    if ($self->has_current_link()) {
	pr("Value: %s", $self->current());
    } else {
	pr("Value: none");
    }

    foreach my $choice ($self->choices()) {
	pr("");
	pr("Alternative: %s", $choice);
        my $fileset = $self->fileset($choice);
	pr("Priority: %s", $fileset->priority());
	next unless scalar($self->slaves());
	pr("Slaves:");
        foreach my $slave ($self->slaves()) {
            if ($fileset->has_slave($slave)) {
	        pr(" %s %s", $slave, $fileset->slave($slave));
            }
        }
    }
}

sub display_user {
    my ($self) = @_;
    pr("%s - %s", $self->name(),
        ($self->status() eq "auto") ? _g("auto mode") : _g("manual mode"));

    if ($self->has_current_link()) {
	pr(_g(" link currently points to %s"), $self->current());
    } else {
	pr(_g(" link currently absent"));
    }
    foreach my $choice ($self->choices()) {
        my $fileset = $self->fileset($choice);
	pr(_g("%s - priority %s"), $choice, $fileset->priority());
        foreach my $slave ($self->slaves()) {
            if ($fileset->has_slave($slave)) {
                pr(_g(" slave %s: %s"), $slave, $fileset->slave($slave));
            }
	}
    }

    my $best = $self->best();
    if (defined($best) && $best) {
	pr(_g("Current \`best' version is %s."), $best);
    } else {
	pr(_g("No versions available."));
    }
}

sub display_list {
    my ($self) = @_;
    pr($_) foreach ($self->choices());
}

sub select_choice {
    my ($self) = @_;
    while (1) {
        my $current = $self->current() || "";
        my $best = $self->best();
        printf _g("There are %s choices for the alternative %s (providing %s).") . "\n\n",
               scalar($self->choices()), $self->name(), $self->link();
        my $length = 15;
        foreach ($self->choices()) {
            $length = (length($_) > $length) ? length($_) + 1 : $length;
        }
        printf "  %-12.12s %-${length}.${length}s %-10.10s %s\n", _g("Selection"),
               _g("Path"), _g("Priority"), _g("Status");
        print "-" x 60 . "\n";
        printf "%s %-12d %-${length}s % -10d %s\n",
               ($self->status() eq "auto" and $current eq $best) ? "*" : " ", 0,
               $best, $self->fileset($best)->priority(), _g("auto mode");
        my $index = 1;
        my %sel = ("0" => $best);
        foreach my $choice ($self->choices()) {
            $sel{$index} = $choice;
            $sel{$choice} = $choice;
            printf "%s %-12d %-${length}.${length}s % -10d %s\n",
                   ($self->status() eq "manual" and $current eq $choice) ?  "*" : " ",
                   $index, $choice, $self->fileset($choice)->priority(),
                   _g("manual mode");
            $index++;
        }
        print "\n";
        printf _g("Press enter to keep the current choice[*], or type selection number: ");
        my $selection = <STDIN>;
        return undef unless defined($selection);
        chomp($selection);
        return ($current || $best) if $selection eq "";
        if (exists $sel{$selection}) {
            $self->set_status(($selection eq "0") ? "auto" : "manual");
            return $sel{$selection};
        }
    }
}


sub best {
    my ($self) = @_;
    my @choices = sort { $self->fileset($b)->priority() <=>
                         $self->fileset($a)->priority()
                  } ($self->choices());
    if (scalar(@choices)) {
        return $choices[0];
    } else {
        return undef;
    }
}

sub has_current_link {
    my ($self) = @_;
    return -l "$altdir/$self->{master_name}";
}

sub current {
    my ($self) = @_;
    return undef unless $self->has_current_link();
    my $val = readlink("$altdir/$self->{master_name}");
    error(_g("readlink(%s) failed: %s"), "$altdir/$self->{master_name}", $!)
        unless defined $val;
    return $val;
}

sub add_commit_op {
    my ($self, $sub) = @_;
    push @{$self->{commit_ops}}, $sub;
}
sub prepare_install {
    my ($self, $choice) = @_;
    my ($link, $name) = ($self->link(), $self->name());
    my $fileset = $self->fileset($choice);
    main::error("can't install unknown choice %s", $choice)
        if not defined($choice);
    # Create link in /etc/alternatives
    main::checked_rm("$altdir/$name.dpkg-tmp");
    main::checked_symlink($choice, "$altdir/$name.dpkg-tmp");
    $self->add_commit_op(sub {
        main::checked_mv("$altdir/$name.dpkg-tmp", "$altdir/$name");
    });
    $! = 0; lstat($link);
    if (-l _ or $! == ENOENT or $force) {
        # Create alternative link
        main::checked_rm("$link.dpkg-tmp");
        main::checked_symlink("$altdir/$name", "$link.dpkg-tmp");
        $self->add_commit_op(sub {
            main::checked_mv("$link.dpkg-tmp", $link);
        });
    } else {
        main::warning(_g("not replacing %s with a link."), $link);
    }
    # Take care of slaves links
    foreach my $slave ($self->slaves()) {
        my ($slink, $spath) = ($self->slave_link($slave), $fileset->slave($slave));
        if ($fileset->has_slave($slave) and -e $spath) {
            # Create link in /etc/alternatives
            main::checked_rm("$altdir/$slave.dpkg-tmp");
            main::checked_symlink($spath, "$altdir/$slave.dpkg-tmp");
            $self->add_commit_op(sub {
                main::checked_mv("$altdir/$slave.dpkg-tmp", "$altdir/$slave");
            });
            $! = 0; lstat($slink);
            if (-l _ or $! == ENOENT or $force) {
                # Create alternative link
                main::checked_rm("$slink.dpkg-tmp");
                main::checked_symlink("$altdir/$slave", "$slink.dpkg-tmp");
                $self->add_commit_op(sub {
                    main::checked_mv("$slink.dpkg-tmp", $slink);
                });
            } else {
                main::warning(_g("not replacing %s with a link."), $slink);
            }
        } else {
            main::warning(_g("skip creation of %s because associated file " .
                             "%s (of link group %s) doesn't exist."),
                          $slink, $spath, $self->name())
                if $fileset->has_slave($slave);
            # Drop unused slave
            $self->add_commit_op(sub {
                main::checked_rm($slink);
                main::checked_rm("$altdir/$slave");
            });
        }
    }
}

sub remove {
    my ($self) = @_;
    my ($link, $name) = ($self->link(), $self->name());
    main::checked_rm("$link.dpkg-tmp");
    main::checked_rm($link) if -l $link;
    main::checked_rm("$altdir/$name.dpkg-tmp");
    main::checked_rm("$altdir/$name");
    foreach my $slave ($self->slaves()) {
        my $slink = $self->slave_link($slave);
        main::checked_rm("$slink.dpkg-tmp");
        main::checked_rm($slink) if -l $slink;
        main::checked_rm("$altdir/$slave.dpkg-tmp");
        main::checked_rm("$altdir/$slave");
    }
    # Drop admin file
    main::checked_rm("$admdir/$name");
}

sub commit {
    my ($self) = @_;
    foreach my $sub (@{$self->{commit_ops}}) {
        &$sub();
    }
    $self->{commit_ops} = [];
}

sub is_broken {
    my ($self) = @_;
    my $name = $self->name();
    return 1 if not $self->has_current_link();
    # Check master link
    my $file = readlink($self->link());
    return 1 if not defined($file);
    return 1 if $file ne "$altdir/$name";
    # Stop if we have an unmanaged alternative
    return 0 if not $self->has_choice($self->current());
    # Check slaves
    my $fileset = $self->fileset($self->current());
    foreach my $slave ($self->slaves()) {
        $file = readlink($self->slave_link($slave));
        if ($fileset->has_slave($slave) and -e $fileset->slave($slave)) {
            return 1 if not defined($file);
            return 1 if $file ne "$altdir/$slave";
            $file = readlink("$altdir/$slave");
            return 1 if not defined($file);
            return 1 if $file ne $fileset->slave($slave);
        } else {
            # Slave link must not exist
            return 1 if defined($file);
            $file = readlink("$altdir/$slave");
            return 1 if defined($file);
        }
    }
    return 0;
}
# vim: nowrap ts=8 sw=4
