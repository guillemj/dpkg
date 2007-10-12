#!/usr/bin/perl

use strict;
use warnings;

use English;
use POSIX qw(:errno_h);
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning error failure internerr syserr subprocerr);
use Dpkg::Arch qw(get_host_arch debarch_is);

textdomain("dpkg-dev");

our $sourcepackage; # - name of sourcepackage
our %f;             # - fields ???
our %fi;            # - map of fields values. keys are of the form "S# key"
                    #   where S is source (L is changelog, C is control)
                    #   and # is an index
our %p2i;           # - map from datafile+packagename to index in controlfile
                    #   (used if multiple packages can be listed). Key is
                    #   "S key" where S is the source and key is the packagename

my $maxsubsts = 50;
our %substvar;      # - map with substitution variables

my $parsechangelog = 'dpkg-parsechangelog';

our @pkg_dep_fields = qw(Pre-Depends Depends Recommends Suggests Enhances
                         Conflicts Breaks Replaces Provides);
our @src_dep_fields = qw(Build-Depends Build-Depends-Indep
                         Build-Conflicts Build-Conflicts-Indep);


sub getfowner
{
    my $getlogin = getlogin();
    if (!defined($getlogin)) {
	open(SAVEIN, "<&STDIN");
	open(STDIN, "<&STDERR");

	$getlogin = getlogin();

	close(STDIN);
	open(STDIN, "<&SAVEIN");
	close(SAVEIN);
    }
    if (!defined($getlogin)) {
	open(SAVEIN, "<&STDIN");
	open(STDIN, "<&STDOUT");

	$getlogin = getlogin();

	close(STDIN);
	open(STDIN, "<&SAVEIN");
	close(SAVEIN);
    }

    my @fowner;
    if (defined($ENV{'LOGNAME'})) {
	@fowner = getpwnam($ENV{'LOGNAME'});
	if (!@fowner) {
	    die(sprintf(_g('unable to get login information for username "%s"'), $ENV{'LOGNAME'}));
	}
    } elsif (defined($getlogin)) {
	@fowner = getpwnam($getlogin);
	if (!@fowner) {
	    die(sprintf(_g('unable to get login information for username "%s"'), $getlogin));
	}
    } else {
	warning(sprintf(_g('no utmp entry available and LOGNAME not defined; using uid of process (%d)'), $<));
	@fowner = getpwuid($<);
	if (!@fowner) {
	    die (sprintf(_g('unable to get login information for uid %d'), $<));
	}
    }
    @fowner = @fowner[2,3];

    return @fowner;
}

sub capit {
    my @pieces = map { ucfirst(lc) } split /-/, $_[0];
    return join '-', @pieces;
}

sub substvars {
    my ($v) = @_;
    my $lhs;
    my $vn;
    my $rhs = '';
    my $count = 0;

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
	    warning(sprintf(_g("unknown substitution variable \${%s}"), $vn));
            $v= $lhs.$rhs;
        }
    }
    return $v;
}

my %fieldimps;

sub set_field_importance(@)
{
    my @fields = @_;
    my $i = 1;

    grep($fieldimps{$_} = $i++, @fields);
}

sub sort_field_by_importance($$)
{
    my ($a, $b) = @_;

    if (defined $fieldimps{$a} && defined $fieldimps{$b}) {
	$fieldimps{$a} <=> $fieldimps{$b};
    } elsif (defined($fieldimps{$a})) {
	-1;
    } elsif (defined($fieldimps{$b})) {
	1;
    } else {
	$a cmp $b;
    }
}

sub outputclose {
    my ($varlistfile) = @_;

    for my $f (keys %f) {
	$substvar{"F:$f"} = $f{$f};
    }

    &parsesubstvars($varlistfile) if (defined($varlistfile));

    for my $f (sort sort_field_by_importance keys %f) {
	my $v = $f{$f};
	if (defined($varlistfile)) {
	    $v= &substvars($v);
	}
        $v =~ m/\S/ || next; # delete whitespace-only fields
        $v =~ m/\n\S/ && &internerr(sprintf(_g("field %s has newline then non whitespace >%s<"), $f, $v));
        $v =~ m/\n[ \t]*\n/ && &internerr(sprintf(_g("field %s has blank lines >%s<"), $f, $v));
        $v =~ m/\n$/ && &internerr(sprintf(_g("field %s has trailing newline >%s<"), $f, $v));
	if (defined($varlistfile)) {
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
    my $controlfile = shift;

    $controlfile="./$controlfile" if $controlfile =~ m/^\s/;

    open(CDATA,"< $controlfile") || &error(sprintf(_g("cannot read control file %s: %s"), $controlfile, $!));
    binmode(CDATA);
    my $indices = parsecdata(\*CDATA, 'C', 1,
			     sprintf(_g("control file %s"), $controlfile));
    $indices >= 2 || &error(_g("control file must have at least one binary package part"));

    for (my $i = 1; $i < $indices; $i++) {
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
    my $varlistfile = shift;

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
    my $host_arch = get_host_arch();

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

		    if ($arch =~ /^!/) {
			my $not_arch;
			($not_arch = $arch) =~ s/^!//;

			if (debarch_is($host_arch, $not_arch)) {
			    next ALTERNATE;
			} else {
			    # This is equivilant to
			    # having seen the current arch,
			    # unless the current arch
			    # is also listed..
			    $seen_arch=1;
			}
		    } elsif (debarch_is($host_arch, $arch)) {
			$seen_arch=1;
			next;
		    }

                }
                if (! $seen_arch) {
                    next;
                }
            }
            if (length($dep_or)) {
		warning(sprintf(_g("can't parse dependency %s"), $dep_and));
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
    my ($changelogfile, $changelogformat, $since) = @_;

    defined(my $c = open(CDATA, "-|")) || syserr(_g("fork for parse changelog"));
    if ($c) {
	binmode(CDATA);
	parsecdata(\*CDATA, 'L', 0, _g("parsed version of changelog"));
	close(CDATA);
	$? && subprocerr(_g("parse changelog"));
    } else {
	binmode(STDOUT);
	my @al = ($parsechangelog);
        push(@al,"-l$changelogfile");
        push(@al, "-F$changelogformat") if defined($changelogformat);
        push(@al, "-v$since") if defined($since);
        exec(@al) || &syserr("exec parsechangelog $parsechangelog");
    }
}

sub init_substvars
{
    $substvar{'Format'} = 1.7;
    $substvar{'Newline'} = "\n";
    $substvar{'Space'} = " ";
    $substvar{'Tab'} = "\t";

    # XXX: Source-Version is now deprecated, remove in the future.
    $substvar{'Source-Version'}= $fi{"L Version"};
    $substvar{'binary:Version'} = $fi{"L Version"};
    $substvar{'source:Version'} = $fi{"L Version"};
    $substvar{'source:Version'} =~ s/\+b[0-9]+$//;
    $substvar{'source:Upstream-Version'} = $fi{"L Version"};
    $substvar{'source:Upstream-Version'} =~ s/-[^-]*$//;

    $substvar{"dpkg:Version"} = $version;
    $substvar{"dpkg:Upstream-Version"} = $version;
    $substvar{"dpkg:Upstream-Version"} =~ s/-[^-]+$//;
}

sub init_substvar_arch()
{
    $substvar{'Arch'} = get_host_arch();
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
    my $v = shift;

    checkpackagename( $v );
    if (defined($sourcepackage)) {
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

# XXX: Should not be a global!!
my $whatmsg;

sub parsecdata {
    my ($cdata, $source, $many);
    ($cdata, $source, $many, $whatmsg) = @_;

    # many=0: ordinary control data like output from dpkg-parsechangelog
    # many=1: many paragraphs like in source control file
    # many=-1: single paragraph of control data optionally signed

    my $index = '';
    my $cf = '';
    my $paraborder = 1;

    while (<$cdata>) {
        s/\s*\n$//;
	next if (m/^$/ and $paraborder);
	next if (m/^#/);
	$paraborder=0;
        if (m/^(\S+)\s*:\s*(.*)$/) {
	    $cf = $1;
	    my $v = $2;
            $cf= &capit($cf);
            $fi{"$source$index $cf"}= $v;
            $fi{"o:$source$index $cf"}= $1;
            if (lc $cf eq 'package') { $p2i{"$source $v"}= $index; }
        } elsif (m/^\s+\S/) {
            length($cf) || &syntax(_g("continued value line not in field"));
            $fi{"$source$index $cf"}.= "\n$_";
        } elsif (m/^-----BEGIN PGP/ && $many<0) {
            $many == -2 && syntax(_g("expected blank line before PGP signature"));
	    while (<$cdata>) {
		last if m/^$/;
	    }
            $many= -2;
        } elsif (m/^$/) {
	    $paraborder = 1;
            if ($many>0) {
                $index++; $cf='';
            } elsif ($many == -2) {
		$_ = <$cdata> while defined($_) && $_ =~ /^\s*$/;
                length($_) ||
                    &syntax(_g("expected PGP signature, found EOF after blank line"));
                s/\n$//;
                m/^-----BEGIN PGP/ ||
                    &syntax(sprintf(_g("expected PGP signature, found something else \`%s'"), $_));
                $many= -3; last;
            } else {
		while (<$cdata>) {
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

sub syntax {
    &error(sprintf(_g("syntax error in %s at line %d: %s"), $whatmsg, $., $_[0]));
}

1;
