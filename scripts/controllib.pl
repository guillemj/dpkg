#!/usr/bin/perl

# Global variables:
# $v                - value parameter to function
# $sourcepackage    - name of sourcepackage
# %capit            - map to get properly capitilized version of fields
# %fi               - map of fields values. keys are of the form "S# key"
#                     where S is source (L is changelog, C is control)
#                     and # is an index
# %p2i              - map from datafile+packagename to index in controlfile
#                     (used if multiple packages can be listed). Key is
#                     "S key" where S is the source and key is the packagename
# %substvar         - map with substitution variables

$parsechangelog= 'dpkg-parsechangelog';

grep($capit{lc $_}=$_, qw(Pre-Depends Standards-Version Installed-Size
			  Build-Depends Build-Depends-Indep 
			  Build-Conflicts Build-Conflicts-Indep));
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
    if (! @fowner) { die (sprintf ('unable to get login information for username "%s"', $ENV{'LOGNAME'})); }
} elsif (defined ($getlogin)) {
    @fowner = getpwnam ($getlogin);
    if (! @fowner) { die (sprintf ('unable to get login information for username "%s"', $getlogin)); }
} else {
    &warn (sprintf ('no utmp entry available and LOGNAME not defined; using uid of process (%d)', $<));
    @fowner = getpwuid ($<);
    if (! @fowner) { die (sprintf ('unable to get login information for uid %d', $<)); }
}
@fowner = @fowner[2,3];

sub capit {
    return defined($capit{lc $_[0]}) ? $capit{lc $_[0]} :
        (uc substr($_[0],0,1)).(lc substr($_[0],1));
}

sub findarch {
    $arch=`dpkg-architecture -qDEB_HOST_ARCH`;
    $? && &subprocerr("dpkg-architecture -qDEB_HOST_ARCH");
    chomp $arch;
    $substvar{'Arch'}= $arch;
}

sub substvars {
    my ($v) = @_;
    my ($lhs,$vn,$rhs,$count);
    $count=0;
    while ($v =~ m/\$\{([-:0-9a-z]+)\}/i) {
        # If we have consumed more from the leftover data, then
        # reset the recursive counter.
        $count= 0 if (length($') < length($rhs));

        $count < $maxsubsts ||
            &error("too many substitutions - recursive ? - in \`$v'");
        $lhs=$`; $vn=$1; $rhs=$';
        if (defined($substvar{$vn})) {
            $v= $lhs.$substvar{$vn}.$rhs;
            $count++;
        } else {
            &warn("unknown substitution variable \${$vn}");
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
        $v =~ m/\n\S/ && &internerr("field $f has newline then non whitespace >$v<");
        $v =~ m/\n[ \t]*\n/ && &internerr("field $f has blank lines >$v<");
        $v =~ m/\n$/ && &internerr("field $f has trailing newline >$v<");
	if ($dosubstvars) {
	   $v =~ s/,[\s,]*,/,/g;
	   $v =~ s/^\s*,\s*//;
	   $v =~ s/\s*,\s*$//;
	}
        $v =~ s/\$\{\}/\$/g;
        print("$f: $v\n") || &syserr("write error on control data");
    }

    close(STDOUT) || &syserr("write error on close control data");
}

sub parsecontrolfile {
    $controlfile="./$controlfile" if $controlfile =~ m/^\s/;

    open(CDATA,"< $controlfile") || &error("cannot read control file $controlfile: $!");
    binmode(CDATA);
    $indices= &parsecdata('C',1,"control file $controlfile");
    $indices >= 2 || &error("control file must have at least one binary package part");

    for ($i=1;$i<$indices;$i++) {
        defined($fi{"C$i Package"}) ||
            &error("per-package paragraph $i in control info file is ".
                   "missing Package line");
    }
    defined($fi{"C Source"}) ||
        &error("source paragraph in control info file is ".
               "missing Source line");

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
                    &error("bad line in substvars file $varlistfile at line $.");
                $substvar{$1}= $';
            }
            close(SV);
        } elsif ($! != ENOENT ) {
            &error("unable to open substvars file $varlistfile: $!");
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
            ($relation, $version) = ($1, $2) if ($dep_or =~ s/^\((=|<=|>=|<<?|>>?)\s*([^)]+).*\)\s*//m);
            my @arches = split(/\s+/m, $1) if ($use_arch && $dep_or =~ s/^\[([^]]+)\]\s*//m);
            if ($reduce_arch && @arches) {

                my $seen_arch='';
                foreach my $arch (@arches) {
                    $arch=lc($arch);
                    if ($arch eq $host_arch) {
                        $seen_arch=1;
                        next;
                    } elsif ($arch eq "!$host_arch") {
                        next ALTERNATE;
                    } elsif ($arch =~ /!/) {
                        # This is equivilant to
                        # having seen the current arch,
                        # unless the current arch
                        # is also listed..
                        $seen_arch=1;
                    }
                }
                if (! $seen_arch) {
                    next;
                }
            }
            return undef if (length($dep_or));
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
    defined($c=open(CDATA,"-|")) || &syserr("fork for parse changelog");
    binmode(CDATA);
    if (!$c) {
        @al=($parsechangelog);
        push(@al,"-F$changelogformat") if length($changelogformat);
        push(@al,"-v$since") if length($since);
        push(@al,"-l$changelogfile");
        exec(@al) || &syserr("exec parsechangelog $parsechangelog");
    }
    &parsecdata('L',0,"parsed version of changelog");
    close(CDATA); $? && &subprocerr("parse changelog");
    $substvar{'Source-Version'}= $fi{"L Version"};
}


sub setsourcepackage {
    if (length($sourcepackage)) {
        $v eq $sourcepackage ||
            &error("source package has two conflicting values - $sourcepackage and $v");
    } else {
        $sourcepackage= $v;
    }
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
            length($cf) || &syntax("continued value line not in field");
            $fi{"$source$index $cf"}.= "\n$_";
        } elsif (m/^-----BEGIN PGP/ && $many<0) {
            $many == -2 && syntax("expected blank line before PGP signature");
            while (<CDATA>) { last if m/^$/; }
            $many= -2;
        } elsif (m/^$/) {
	    $paraborder = 1;
            if ($many>0) {
                $index++; $cf='';
            } elsif ($many == -2) {
                $_= <CDATA>;
                length($_) ||
                    &syntax("expected PGP signature, found EOF after blank line");
                s/\n$//;
                m/^-----BEGIN PGP/ ||
                    &syntax("expected PGP signature, found something else \`$_'");
                $many= -3; last;
            } else {
                &syntax("found several \`paragraphs' where only one expected");
            }
        } else {
            &syntax("line with unknown format (not field-colon-value)");
        }
    }
    $many == -2 && &syntax("found start of PGP body but no signature");
    if (length($cf)) { $index++; }
    $index || &syntax("empty file");
    return $index;
}

sub unknown {
    my $field = $_;
    &warn("unknown information field \`$field\' in input data in $_[0]");
}

sub syntax {
    &error("syntax error in $whatmsg at line $.: $_[0]");
}

sub failure { die "$progname: failure: $_[0]\n"; }
sub syserr { die "$progname: failure: $_[0]: $!\n"; }
sub error { die "$progname: error: $_[0]\n"; }
sub internerr { die "$progname: internal error: $_[0]\n"; }
sub warn { warn "$progname: warning: $_[0]\n"; }
sub usageerr { print(STDERR "$progname: @_\n\n"); &usageversion; exit(2); }
sub warnerror { if ($warnable_error) { &warn( @_ ); } else { &error( @_ ); } }

sub subprocerr {
    local ($p) = @_;
    if (WIFEXITED($?)) {
        die "$progname: failure: $p gave error exit status ".WEXITSTATUS($?)."\n";
    } elsif (WIFSIGNALED($?)) {
        die "$progname: failure: $p died from signal ".WTERMSIG($?)."\n";
    } else {
        die "$progname: failure: $p failed with unknown exit code $?\n";
    }
}

1;
