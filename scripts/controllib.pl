#!/usr/bin/perl

use English;

$dpkglibdir= "."; # This line modified by Makefile
push(@INC,$dpkglibdir);
require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

# Global variables:
# $v                - value parameter to function
# $sourcepackage    - name of sourcepackage
# %fi               - map of fields values. keys are of the form "S# key"
#                     where S is source (L is changelog, C is control)
#                     and # is an index
# %p2i              - map from datafile+packagename to index in controlfile
#                     (used if multiple packages can be listed). Key is
#                     "S key" where S is the source and key is the packagename
# %substvar         - map with substitution variables

$parsechangelog= 'dpkg-parsechangelog';

@pkg_dep_fields = qw(Replaces Provides Depends Pre-Depends Recommends Suggests
                     Conflicts Enhances);
@src_dep_fields = qw(Build-Depends Build-Depends-Indep
                     Build-Conflicts Build-Conflicts-Indep);

$substvar{'Format'}= 1.7;
$substvar{'Newline'}= "\n";
$substvar{'Space'}= " ";
$substvar{'Tab'}= "\t";
$maxsubsts=50;
$warnable_error= 1;
$quiet_warnings = 0;

$progname= $0; $progname= $& if $progname =~ m,[^/]+$,;

$getlogin = getlogin();
if(!defined($getlogin)) {
	open(SAVEIN, "<&STDIN");
	close(STDIN);
	open(STDIN, "<&STDERR");

	$getlogin = getlogin();

	close(STDIN);
	open(STDIN, "<&SAVEIN");
	close(SAVEIN);
}
if(!defined($getlogin)) {
	open(SAVEIN, "<&STDIN");
	close(STDIN);
	open(STDIN, "<&STDOUT");

	$getlogin = getlogin();

	close(STDIN);
	open(STDIN, "<&SAVEIN");
	close(SAVEIN);
}

if (defined ($ENV{'LOGNAME'})) {
    @fowner = getpwnam ($ENV{'LOGNAME'});
    if (! @fowner) { die (sprintf (_g('unable to get login information for username "%s"'), $ENV{'LOGNAME'})); }
} elsif (defined ($getlogin)) {
    @fowner = getpwnam ($getlogin);
    if (! @fowner) { die (sprintf (_g('unable to get login information for username "%s"'), $getlogin)); }
} else {
    &warn (sprintf (_g('no utmp entry available and LOGNAME not defined; using uid of process (%d)'), $<));
    @fowner = getpwuid ($<);
    if (! @fowner) { die (sprintf (_g('unable to get login information for uid %d'), $<)); }
}
@fowner = @fowner[2,3];

sub capit {
    my @pieces = map { ucfirst(lc) } split /-/, $_[0];
    return join '-', @pieces;
}

sub findarch {
    $arch=`dpkg-architecture -qDEB_HOST_ARCH`;
    $? && &subprocerr("dpkg-architecture -qDEB_HOST_ARCH");
    chomp $arch;
    $substvar{'Arch'}= $arch;
}

sub debian_arch_fix
{
    local ($os, $cpu) = @_;

    if ($os eq "linux") {
	return $cpu;
    } else {
	return "$os-$cpu";
    }
}

sub debian_arch_split {
    local ($_) = @_;

    if (/^([^-]*)-(.*)/) {
	return ($1, $2);
    } elsif (/any/ || /all/) {
	return ($_, $_);
    } else {
	return ("linux", $_);
    }
}

sub debian_arch_eq {
    my ($a, $b) = @_;
    my ($a_os, $a_cpu) = debian_arch_split($a);
    my ($b_os, $b_cpu) = debian_arch_split($b);

    return ("$a_os-$a_cpu" eq "$b_os-$b_cpu");
}

sub debian_arch_is {
    my ($real, $alias) = @_;
    my ($real_os, $real_cpu) = debian_arch_split($real);
    my ($alias_os, $alias_cpu) = debian_arch_split($alias);

    if ("$real_os-$real_cpu" eq "$alias_os-$alias_cpu") {
	return 1;
    } elsif ("$alias_os-$alias_cpu" eq "any-any") {
	return 1;
    } elsif ("$alias_os-$alias_cpu" eq "any-$real_cpu") {
	return 1;
    } elsif ("$alias_os-$alias_cpu" eq "$real_os-any") {
	return 1;
    }

    return 0;
}

sub substvars {
    my ($v) = @_;
    my ($lhs,$vn,$rhs,$count);
    $count=0;
    while ($v =~ m/\$\{([-:0-9a-z]+)\}/i) {
        # If we have consumed more from the leftover data, then
        # reset the recursive counter.
        $count= 0 if (length($POSTMATCH) < length($rhs));

        $count < $maxsubsts ||
            &error(sprintf(_g("too many substitutions - recursive ? - in \`%s'"), $v));
        $lhs=$`; $vn=$1; $rhs=$';
        if (defined($substvar{$vn})) {
            $v= $lhs.$substvar{$vn}.$rhs;
            $count++;
        } else {
            &warn(sprintf(_g("unknown substitution variable \${%s}"), $vn));
            $v= $lhs.$rhs;
        }
    }
    return $v;
}

sub outputclose {
    my ($dosubstvars) = @_;
    for $f (keys %f) { $substvar{"F:$f"}= $f{$f}; }
    &parsesubstvars if ($dosubstvars);
    for $f (sort { $fieldimps{$b} <=> $fieldimps{$a} } keys %f) {
        $v= $f{$f};
        if ($dosubstvars) {
	    $v= &substvars($v);
	}
        $v =~ m/\S/ || next; # delete whitespace-only fields
        $v =~ m/\n\S/ && &internerr(sprintf(_g("field %s has newline then non whitespace >%s<"), $f, $v));
        $v =~ m/\n[ \t]*\n/ && &internerr(sprintf(_g("field %s has blank lines >%s<"), $f, $v));
        $v =~ m/\n$/ && &internerr(sprintf(_g("field %s has trailing newline >%s<"), $f, $v));
	if ($dosubstvars) {
	   $v =~ s/,[\s,]*,/,/g;
	   $v =~ s/^\s*,\s*//;
	   $v =~ s/\s*,\s*$//;
	}
        $v =~ s/\$\{\}/\$/g;
        print("$f: $v\n") || &syserr(_g("write error on control data"));
    }

    close(STDOUT) || &syserr(_g("write error on close control data"));
}

sub parsecontrolfile {
    $controlfile="./$controlfile" if $controlfile =~ m/^\s/;

    open(CDATA,"< $controlfile") || &error(sprintf(_g("cannot read control file %s: %s"), $controlfile, $!));
    binmode(CDATA);
    $indices= &parsecdata('C',1,sprintf(_g("control file %s"),$controlfile));
    $indices >= 2 || &error(_g("control file must have at least one binary package part"));

    for ($i=1;$i<$indices;$i++) {
        defined($fi{"C$i Package"}) ||
            &error(sprintf(_g("per-package paragraph %d in control ".
                                   "info file is missing Package line"),
                           $i));
    }
    defined($fi{"C Source"}) ||
        &error(_g("source paragraph in control info file is ".
                       "missing Source line"));

}

my $substvarsparsed = 0;
sub parsesubstvars {
    if (length($varlistfile) && !$substvarsparsed) {
        $varlistfile="./$varlistfile" if $varlistfile =~ m/\s/;
        if (open(SV,"< $varlistfile")) {
            binmode(SV);
            while (<SV>) {
                next if m/^\#/ || !m/\S/;
                s/\s*\n$//;
                m/^(\w[-:0-9A-Za-z]*)\=/ ||
                    &error(sprintf(_g("bad line in substvars file %s at line %d"),
                                   $varlistfile, $.));
                $substvar{$1}= $';
            }
            close(SV);
        } elsif ($! != ENOENT ) {
            &error(sprintf(_g("unable to open substvars file %s: %s"),
                           $varlistfile, $!));
        }
        $substvarsparsed = 1;
    }
}

sub parsedep {
    my ($dep_line, $use_arch, $reduce_arch) = @_;
    my @dep_list;
    if (!$host_arch) {
        $host_arch = `dpkg-architecture -qDEB_HOST_ARCH`;
        chomp $host_arch;
    }
    foreach my $dep_and (split(/,\s*/m, $dep_line)) {
        my @or_list = ();
ALTERNATE:
        foreach my $dep_or (split(/\s*\|\s*/m, $dep_and)) {
            my ($package, $relation, $version);
            $package = $1 if ($dep_or =~ s/^([a-zA-Z0-9][a-zA-Z0-9+._-]*)\s*//m);
            ($relation, $version) = ($1, $2)
		if ($dep_or =~ s/^\(\s*(=|<=|>=|<<?|>>?)\s*([^)]+).*\)\s*//m);
	    my @arches;
	    @arches = split(/\s+/m, $1) if ($use_arch && $dep_or =~ s/^\[([^]]+)\]\s*//m);
            if ($reduce_arch && @arches) {

                my $seen_arch='';
                foreach my $arch (@arches) {
                    $arch=lc($arch);
                    if (debian_arch_is($host_arch, $arch)) {
                        $seen_arch=1;
                        next;
                    } elsif ($arch =~ /^!/) {
			($not_arch = $arch) =~ s/^!//;

			if (debian_arch_is($host_arch, $not_arch)) {
			    next ALTERNATE;
			} else {
			    # This is equivilant to
			    # having seen the current arch,
			    # unless the current arch
			    # is also listed..
			    $seen_arch=1;
			}
                    }
                }
                if (! $seen_arch) {
                    next;
                }
            }
            if (length($dep_or)) {
		&warn(sprintf(_g("can't parse dependency %s"),$dep_and));
		return undef;
	    }
	    push @or_list, [ $package, $relation, $version, \@arches ];
        }
        push @dep_list, \@or_list;
    }
    \@dep_list;
}

sub showdep {
    my ($dep_list, $show_arch) = @_;
    my @and_list;
    foreach my $dep_and (@$dep_list) {
        my @or_list = ();
        foreach my $dep_or (@$dep_and) {
            my ($package, $relation, $version, $arch_list) = @$dep_or; 
            push @or_list, $package . ($relation && $version ? " ($relation $version)" : '') . ($show_arch && @$arch_list ? " [@$arch_list]" : '');
        }
        push @and_list, join(' | ', @or_list);
    }
    join(', ', @and_list);
}

sub parsechangelog {
    defined($c=open(CDATA,"-|")) || &syserr(_g("fork for parse changelog"));
    binmode(CDATA);
    if (!$c) {
        @al=($parsechangelog);
        push(@al,"-F$changelogformat") if length($changelogformat);
        push(@al,"-v$since") if length($since);
        push(@al,"-l$changelogfile");
        exec(@al) || &syserr("exec parsechangelog $parsechangelog");
    }
    &parsecdata('L',0,_g("parsed version of changelog"));
    close(CDATA); $? && &subprocerr(_g("parse changelog"));
}

sub init_substvars
{
    # XXX: Source-Version is now deprecated, remove in the future.
    $substvar{'Source-Version'}= $fi{"L Version"};
    $substvar{'binary:Version'} = $fi{"L Version"};
    $substvar{'source:Version'} = $fi{"L Version"};
    $substvar{'source:Version'} =~ s/\+b[0-9]+$//;
    $substvar{'source:Upstream-Version'} = $fi{"L Version"};
    $substvar{'source:Upstream-Version'} =~ s/-[^-]*$//;

    # We expect the calling program to set $version.
    $substvar{"dpkg:Version"} = $version;
    $substvar{"dpkg:Upstream-Version"} = $version;
    $substvar{"dpkg:Upstream-Version"} =~ s/-[^-]+$//;
}

sub checkpackagename {
    my $name = shift || '';
    $name =~ m/[^-+.0-9a-z]/o &&
        &error(sprintf(_g("source package name `%s' contains illegal character `%s'"), $name, $&));
    $name =~ m/^[0-9a-z]/o ||
        &error(sprintf(_g("source package name `%s' starts with non-alphanum"), $name));
}

sub checkversion {
    my $version = shift || '';
    $version =~ m/[^-+:.0-9a-zA-Z~]/o &&
        &error(sprintf(_g("version number contains illegal character `%s'"), $&));
}

sub setsourcepackage {
    checkpackagename( $v );
    if (length($sourcepackage)) {
        $v eq $sourcepackage ||
            &error(sprintf(_g("source package has two conflicting values - %s and %s"), $sourcepackage, $v));
    } else {
        $sourcepackage= $v;
    }
}

sub readmd5sum {
    (my $md5sum = shift) or return;
    $md5sum =~ s/^([0-9a-f]{32})\s*\*?-?\s*\n?$/$1/o
	|| &failure(sprintf(_g("md5sum gave bogus output `%s'"), $md5sum));
    return $md5sum;
}

sub parsecdata {
    local ($source,$many,$whatmsg) = @_;
    # many=0: ordinary control data like output from dpkg-parsechangelog
    # many=1: many paragraphs like in source control file
    # many=-1: single paragraph of control data optionally signed
    local ($index,$cf,$paraborder);
    $index=''; $cf=''; $paraborder=1;
    while (<CDATA>) {
        s/\s*\n$//;
	next if (m/^$/ and $paraborder);
	next if (m/^#/);
	$paraborder=0;
        if (m/^(\S+)\s*:\s*(.*)$/) {
            $cf=$1; $v=$2;
            $cf= &capit($cf);
            $fi{"$source$index $cf"}= $v;
            $fi{"o:$source$index $cf"}= $1;
            if (lc $cf eq 'package') { $p2i{"$source $v"}= $index; }
        } elsif (m/^\s+\S/) {
            length($cf) || &syntax(_g("continued value line not in field"));
            $fi{"$source$index $cf"}.= "\n$_";
        } elsif (m/^-----BEGIN PGP/ && $many<0) {
            $many == -2 && syntax(_g("expected blank line before PGP signature"));
            while (<CDATA>) { last if m/^$/; }
            $many= -2;
        } elsif (m/^$/) {
	    $paraborder = 1;
            if ($many>0) {
                $index++; $cf='';
            } elsif ($many == -2) {
                $_= <CDATA> while defined($_) && $_ =~ /^\s*$/;
                length($_) ||
                    &syntax(_g("expected PGP signature, found EOF after blank line"));
                s/\n$//;
                m/^-----BEGIN PGP/ ||
                    &syntax(sprintf(_g("expected PGP signature, found something else \`%s'"), $_));
                $many= -3; last;
            } else {
		while (<CDATA>) {
		    /^\s*$/ ||
			&syntax(_g("found several \`paragraphs' where only one expected"));
		}
            }
        } else {
            &syntax(_g("line with unknown format (not field-colon-value)"));
        }
    }
    $many == -2 && &syntax(_g("found start of PGP body but no signature"));
    if (length($cf)) { $index++; }
    $index || &syntax(_g("empty file"));
    return $index;
}

sub unknown {
    my $field = $_;
    &warn(sprintf(_g("unknown information field \`%s\' in input data in %s"), $field, $_[0]));
}

sub syntax {
    &error(sprintf(_g("syntax error in %s at line %d: %s"), $whatmsg, $., $_[0]));
}

sub failure { die sprintf(_g("%s: failure: %s"), $progname, $_[0])."\n"; }
sub syserr { die sprintf(_g("%s: failure: %s: %s"), $progname, $_[0], $!)."\n"; }
sub error { die sprintf(_g("%s: error: %s"), $progname, $_[0])."\n"; }
sub internerr { die sprintf(_g("%s: internal error: %s"), $progname, $_[0])."\n"; }
sub warn { if (!$quiet_warnings) { warn sprintf(_g("%s: warning: %s"), $progname, $_[0])."\n"; } }
sub usageerr
{
    printf(STDERR "%s: %s\n\n", $progname, "@_");
    &usage;
    exit(2);
}
sub warnerror { if ($warnable_error) { &warn( @_ ); } else { &error( @_ ); } }

sub subprocerr {
    local ($p) = @_;
    require POSIX;
    if (POSIX::WIFEXITED($?)) {
        die sprintf(_g("%s: failure: %s gave error exit status %s"),
                    $progname, $p, POSIX::WEXITSTATUS($?))."\n";
    } elsif (POSIX::WIFSIGNALED($?)) {
        die sprintf(_g("%s: failure: %s died from signal %s"),
                    $progname, $p, POSIX::WTERMSIG($?))."\n";
    } else {
        die sprintf(_g("%s: failure: %s failed with unknown exit code %d"),
                    $progname, $p, $?)."\n";
    }
}

1;
