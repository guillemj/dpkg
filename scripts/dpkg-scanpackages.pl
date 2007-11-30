#!/usr/bin/perl

use warnings;
use strict;

use IO::Handle;
use IO::File;
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(error syserr subprocerr);
use Dpkg::Deps qw(@pkg_dep_fields);
use Dpkg::Version qw(compare_versions);

textdomain("dpkg-dev");

my (@samemaint, @changedmaint);
my %packages;
my %overridden;

my %kmap= (optional         => 'suggests',
	   recommended      => 'recommends',
	   class            => 'priority',
	   package_revision => 'revision',
	  );

my @fieldpri = (qw(Package Package-Type Source Version Kernel-Version
                   Architecture Subarchitecture Essential Origin Bugs
                   Maintainer Installed-Size Installer-Menu-Item),
                @pkg_dep_fields, qw(Filename Size MD5sum Section Priority
                   Homepage Description Tag));

# This maps the fields into the proper case
my %field_case;
@field_case{map{lc($_)} @fieldpri} = @fieldpri;

use Getopt::Long qw(:config bundling);

my %options = (help            => sub { &usage; exit 0; },
	       version         => \&version,
	       type            => undef,
	       udeb            => 0,
	       arch            => undef,
	       multiversion    => 0,
	      );

my $result = GetOptions(\%options,
                        'help|h|?', 'version', 'type|t=s', 'udeb|u!',
                        'arch|a=s', 'multiversion|m!');

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;
    exit;
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <binarypath> [<overridefile> [<pathprefix>]] > Packages

Options:
  -t, --type <type>        scan for <type> packages (default is 'deb').
  -u, --udeb               scan for udebs (obsolete alias for -tudeb).
  -a, --arch <arch>        architecture to scan for.
  -m, --multiversion       allow multiple versions of a single package.
  -h, --help               show this help message.
      --version            show the version.
"), $progname;
}

sub load_override
{
    my $override = shift;
    my $override_fh = new IO::File $override, 'r' or
        syserr(_g("Couldn't open override file %s"), $override);

    while (<$override_fh>) {
	s/\#.*//;
	s/\s+$//;
	next unless $_;

	my ($p, $priority, $section, $maintainer) = split(/\s+/, $_, 4);

	next unless defined($packages{$p});

	for my $package (@{$packages{$p}}) {
	    if ($maintainer) {
		if ($maintainer =~ m/(.+?)\s*=\>\s*(.+)/) {
		    my $oldmaint = $1;
		    my $newmaint = $2;
		    my $debmaint = $$package{Maintainer};
		    if (!grep($debmaint eq $_, split(m:\s*//\s*:, $oldmaint))) {
			push(@changedmaint,
			     "  $p (package says $$package{Maintainer}, not $oldmaint)\n");
		    } else {
			$$package{Maintainer} = $newmaint;
		    }
		} elsif ($$package{Maintainer} eq $maintainer) {
		    push(@samemaint, "  $p ($maintainer)\n");
		} else {
		    printf(STDERR _g(" * Unconditional maintainer override for %s *")."\n", $p) || die $!;
		    $$package{Maintainer} = $maintainer;
		}
	    }
	    $$package{Priority} = $priority;
	    $$package{Section} = $section;
	}
	$overridden{$p} = 1;
    }

    close($override_fh);
}

usage() and exit 1 if not $result;

if (not @ARGV >= 1 && @ARGV <= 3) {
    warn _g("1 to 3 args expected\n");
    usage();
    exit 1;
}

my $type = defined($options{type}) ? $options{type} :
				     $options{udeb} ? 'udeb' : 'deb';
my $arch = $options{arch};

my @find_args;
if ($options{arch}) {
     @find_args = ('(', '-name', "*_all.$type", '-o',
			'-name', "*_${arch}.$type", ')');
}
else {
     @find_args = ('-name', "*.$type");
}
push @find_args, '-follow';

#push @ARGV, undef	if @ARGV < 2;
#push @ARGV, ''		if @ARGV < 3;
my ($binarydir, $override, $pathprefix) = @ARGV;

-d $binarydir or error(_g("Binary dir %s not found"), $binarydir);
defined($override) and (-e $override or
    error(_g("Override file %s not found"), $override));

$pathprefix = '' if not defined $pathprefix;

my %vercache;
sub vercmp {
     my ($a,$b)=@_;
     return $vercache{$a}{$b} if exists $vercache{$a}{$b};
     $vercache{$a}{$b} = compare_versions($a, 'gt', $b);
     return $vercache{$a}{$b};
}

my $find_h = new IO::Handle;
open($find_h,'-|','find',"$binarydir/",@find_args,'-print')
     or syserr(_g("Couldn't open %s for reading"), $binarydir);
FILE:
    while (<$find_h>) {
	chomp;
	my $fn = $_;
	my $control = `dpkg-deb -I $fn control`;
	if ($control eq "") {
	    warn sprintf(_g("Couldn't call dpkg-deb on %s: %s, skipping package"), $fn, $!)."\n";
	    next;
	}
	if ($?) {
	    warn sprintf(_g("\`dpkg-deb -I %s control' exited with %d, skipping package"), $fn, $?)."\n";
	    next;
	}
	
	my %tv = ();
	my $temp = $control;
	while ($temp =~ s/^\n*(\S+):[ \t]*(.*(\n[ \t].*)*)\n//) {
	    my ($key,$value)= (lc $1,$2);
	    if (defined($kmap{$key})) { $key= $kmap{$key}; }
	    if (defined($field_case{$key})) { $key= $field_case{$key}; }
	    $value =~ s/\s+$//;
	    $tv{$key}= $value;
	}
	$temp =~ /^\n*$/
	    or error(_g("Unprocessed text from %s control file; info:\n%s / %s"),
	             $fn, $control, $temp);
	
	defined($tv{'Package'})
	    or error(_g("No Package field in control file of %s"), $fn);
	my $p= $tv{'Package'}; delete $tv{'Package'};
	
	if (defined($packages{$p}) and not $options{multiversion}) {
	    foreach (@{$packages{$p}}) {
		if (&vercmp($tv{'Version'}, $_->{'Version'})) {
		    printf(STDERR _g(
			  " ! Package %s (filename %s) is repeat but newer version;\n".
			  "   used that one and ignored data from %s !\n"), $p, $fn, $_->{Filename})
			|| die $!;
		    $packages{$p} = [];
		} else {
		    printf(STDERR _g(
			  " ! Package %s (filename %s) is repeat;\n".
			  "   ignored that one and using data from %s !\n"), $p, $fn, $_->{Filename})
			or die $!;
		    next FILE;
		}
	    }
	}
	printf(STDERR _g(" ! Package %s (filename %s) has Filename field!\n"), $p, $fn) || die $!
	    if defined($tv{'Filename'});
	
	$tv{'Filename'}= "$pathprefix$fn";
	
	open(C,"md5sum <$fn |") || die "$fn $!";
	chop($_ = <C>);
	close(C);
	$? and subprocerr("'md5sum < %s'", $fn);;
	/^([0-9a-f]{32})\s*-?\s*$/ or
	    error(_g("Strange text from 'md5sum < %s': '%s'"), $fn, $_);
	$tv{'MD5sum'}= $1;
	
	my @stat = stat($fn) or syserr(_g("Couldn't stat %s"), $fn);
	$stat[7] or error(_g("file %s is empty"), $fn);
	$tv{'Size'}= $stat[7];
	
	if (defined $tv{Revision} and length($tv{Revision})) {
	    $tv{Version}.= '-'.$tv{Revision};
	    delete $tv{Revision};
	}
	
	push @{$packages{$p}}, {%tv};
    }
close($find_h);

select(STDERR); $= = 1000; select(STDOUT);

sub writelist {
    my $title= shift(@_);
    return unless @_;

    print(STDERR " $title\n") || die $!;
    my $packages= join(' ',sort @_);

format STDERR =
  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$packages
.
    while (length($packages)) { write(STDERR) || die $!; }
    print(STDERR "\n") || die $!;
}

load_override($override) if defined $override;

my @missingover=();

my $records_written = 0;
for my $p (sort keys %packages) {
    if (not defined($overridden{$p})) {
        push(@missingover,$p);
    }
    for my $package (@{$packages{$p}}) {
	 my $record= "Package: $p\n";
	 for my $key (@fieldpri) {
	      next unless defined $$package{$key};
	      $record .= "$key: $$package{$key}\n";
	 }
	 $record .= "\n";
	 $records_written++;
	 print(STDOUT $record) or syserr(_g("Failed when writing stdout"));
    }
}
close(STDOUT) or syserr(_g("Couldn't close stdout"));

my @spuriousover= grep(!defined($packages{$_}),sort keys %overridden);

&writelist(_g("** Packages in archive but missing from override file: **"),
           @missingover);
if (@changedmaint) {
    print(STDERR
          _g(" ++ Packages in override file with incorrect old maintainer value: ++")."\n",
          @changedmaint,
          "\n") || die $!;
}
if (@samemaint) {
    print(STDERR
          _g(" -- Packages specifying same maintainer as override file: --")."\n",
          @samemaint,
          "\n") || die $!;
}
if (@spuriousover) {
    print(STDERR
          _g(" -- Packages in override file but not in archive: --")."\n",
          @spuriousover,
          "\n") || die $!;
}

printf(STDERR _g(" Wrote %s entries to output Packages file.")."\n", $records_written) || die $!;
