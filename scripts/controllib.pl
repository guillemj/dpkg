$parsechangelog= 'dpkg-parsechangelog';

grep($capit{lc $_}=$_, qw(Pre-Depends Standards-Version));

$substvar{'Format'}= 1.5;
$substvar{'newline'}= "\n";
$substvar{'space'}= " ";
$substvar{'tab'}= "\t";

$progname= $0; $progname= $& if $progname =~ m,[^/]+$,;

sub capit {
    return defined($capit{lc $_[0]}) ? $capit{lc $_[0]} :
        (uc substr($_[0],0,1)).(lc substr($_[0],1));
}

sub findarch {
    $arch=`dpkg --print-architecture`;
    $? && &subprocerr("dpkg --print-archictecture");
    $arch =~ s/\n$//;
    $substvar{'arch'}= $arch;
}

sub substvars {
    my ($v) = @_;
    my $lhs,$vn,$rhs;
    while ($v =~ m/\$\{([-:0-9a-z]+)\}/i) {
        $lhs=$`; $vn=$1; $rhs=$';
        if (defined($substvar{$vn})) {
            $v= $lhs.$substvar{$vn}.$rhs;
        } else {
            &warn("unknown substitution variable \${$vn}");
            $v= $lhs.$rhs;
        }
    }
    return $v;
}

sub outputclose {
    for $f (keys %f) { $substvar{"f:$f"}= $f{$f}; }
    if (length($varlistfile)) {
        $varlistfile="./$varlistfile" if $varlistfile =~ m/\s/;
        if (open(SV,"< $varlistfile")) {
            while (<SV>) {
                next if m/^\#/;
                s/\s*\n$//;
                m/^(\w+)\=/ ||
                    &error("bad line in substvars file $varlistfile at line $.");
                $substvar{$1}= $';
            }
            close(SV);
        } elsif ($! !~ m/no such file or directory/i) {
            &error("unable to open substvars file $varlistvile: $!");
        }
    }
    for $f (sort { $fieldimps{$b} <=> $fieldimps{$a} } keys %f) {
        $v= $f{$f};
        $v= &substvars($v);
        $v =~ m/\n\S/ && &internerr("field $f has newline then non whitespace >$v<");
        $v =~ m/\n[ \t]*\n/ && &internerr("field $f has blank lines >$v<");
        $v =~ m/\n$/ && &internerr("field $f has trailing newline >$v<");
        $v =~ s/\$\{\}/\$/g;
        print("$f: $v\n") || &syserr("write error on control data");
    }

    close(STDOUT) || &syserr("write error on close control data");
}

sub parsecontrolfile {
    $controlfile="./$controlfile" if $controlfile =~ m/^\s/;

    open(CDATA,"< $controlfile") || &error("cannot read control file $controlfile: $!");
    $indices= &parsecdata('C',1,"control file $controlfile");
    $indices >= 2 || &error("control file must have at least one binary package part");

    for ($i=1;$i<$indices;$i++) {
        defined($fi{"C$i Package"}) ||
            &error("per-package paragraph $i in control info file is ".
                   "missing Package line");
    }
}

sub parsechangelog {
    defined($c=open(CDATA,"-|")) || &syserr("fork for parse changelog");
    if (!$c) {
        @al=($parsechangelog);
        push(@al,"-F$changelogformat") if length($changelogformat);
        push(@al,"-v$since") if length($since);
        push(@al,"-l$changelogfile");
        exec(@al) || &syserr("exec parsechangelog $parsechangelog");
    }
    &parsecdata('L',0,"parsed version of changelog");
    close(CDATA); $? && &subprocerr("parse changelog");
    $substvar{'sourceversion'}= $fi{"L Version"};
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
    local ($index,$cf);
    $index=''; $cf='';
    while (<CDATA>) {
        s/\s*\n$//;
        if (m/^(\S+)\s*:\s*(.*)$/) {
            $cf=$1; $v=$2;
            $cf= &capit($cf);
            $fi{"$source$index $cf"}= $v;
            if (lc $cf eq 'package') { $p2i{"$source $v"}= $index; }
        } elsif (m/^\s+\S/) {
            length($cf) || &syntax("continued value line not in field");
            $fi{"$source$index $cf"}.= "\n$_";
        } elsif (m/^-----BEGIN PGP/ && $many<0) {
            while (<CDATA>) { last if m/^$/; }
            $many= -2;
        } elsif (m/^$/) {
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
    &warn("unknown information field $_ in input data in $_[0]");
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
