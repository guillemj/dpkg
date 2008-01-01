#!/usr/bin/perl

use strict;
use warnings;

use English;
use POSIX qw(:errno_h);
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning error failure internerr syserr subprocerr);
use Dpkg::Fields qw(capit sort_field_by_importance);

textdomain("dpkg-dev");

our %fi;            # - map of fields values. keys are of the form "S# key"
                    #   where S is source (L is changelog, C is control)
                    #   and # is an index
our %p2i;           # - map from datafile+packagename to index in controlfile
                    #   (used if multiple packages can be listed). Key is
                    #   "S key" where S is the source and key is the packagename

my $parsechangelog = 'dpkg-parsechangelog';

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

sub readmd5sum {
    (my $md5sum = shift) or return;
    $md5sum =~ s/^([0-9a-f]{32})\s*\*?-?\s*\n?$/$1/o
        || failure(_g("md5sum gave bogus output `%s'"), $md5sum);
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
        if (m/^(\S+?)\s*:\s*(.*)$/) {
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
    error(_g("syntax error in %s at line %d: %s"), $whatmsg, $., $_[0]);
}

1;
