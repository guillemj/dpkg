#!/usr/bin/perl --

$version= '0.93.30'; # This line modified by Makefile
sub usageversion {
    print(STDERR <<END)
Debian GNU/Linux start-stop-daemon $version.  Copyright (C) 1995
Ian Jackson.  This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage: start-stop-daemon --start | --stop | --version|--help  options ...
Options:  --test  --oknodo    --exec <executable>  --pidfile <pid-file>
          --quiet|--verbose   --user <username>|<uid>  --name <process-name>
          --signal <signal>  --startas <pathname>
          -- <... all of the rest are arguments to daemon ...>
 Be careful - try not to call without --exec.  \`start-stop-daemon --stop'
 would send a SIGTERM to every process, if it weren't specially prevented.

Exit status:  0 = done  1 = nothing done (=> 0 if --oknodo)  2 = trouble
END
        || &quit("failed to write usage: $!");
}
sub quit { print STDERR "start-stop-daemon: @_\n"; exit(2); }
sub badusage { print STDERR "start-stop-daemon: @_\n\n"; &usageversion; exit(2); }

$exitnodo= 1;
$quietmode= 0;
$signal= 15;
undef $operation;
undef $exec;
undef $pidfile;
undef $user;
undef $name;
undef $startas;

while (@ARGV) {
    $_= shift(@ARGV);
    last if m/^--$/;
    if (!m/^--/) {
        &quit("unknown argument \`$_'");
    } elsif (m/^--(help|version)$/) {
        &usageversion; exit(0);
    } elsif (m/^--test$/) {
        $testmode= 1;
    } elsif (m/^--quiet$/) {
        $quietmode= 1;
    } elsif (m/^--verbose$/) {
        $quietmode= -1;
    } elsif (m/^--oknodo$/) {
        $exitnodo= 0;
    } elsif (m/^--(start|stop)$/) {
        $operation= $1; next;
    } elsif (m/^--signal$/) {
        $_= shift(@ARGV); m/^\d+$/ || &badusage("--signal takes a numeric argument");
        $signal= $_;
    } elsif (m/^--(exec|pidfile|name|startas)$/) {
        defined($_= shift(@ARGV)) || &badusage("--$1 takes an argument");
        eval("\$$1= \$_");
    } elsif (m/^--user$/) {
        defined($_= shift(@ARGV)) || &badusage("--user takes a username argument");
        if (m/^\d+$/) {
            $user= $_;
        } else {
            (@u= getpwnam($_)) || &quit("user \`$_' not found");
            $user= $u[2];
        }
        $userspec= $_;
    } else {
        &badusage("unknown option \`$_'");
    }
}

defined($operation) ||
    &badusage("need --start or --stop");
defined($exec) || defined($pidfile) || defined($user) ||
    &badusage("need at least one of --exec, --pidfile or --user");
$startas= $exec if !defined($startas);
$operation ne 'start' || defined($startas) ||
    &badusage("--start needs --exec or --startas");

if (defined($exec)) {
    $exec =~ s,^,./, unless $exec =~ m,^[./],;
    (@ve= stat("$exec")) || &quit("unable to stat executable \`$exec': $!");
}

@found= ();
if (defined($pidfile)) {
    $pidfile =~ s,^,./, unless $pidfile =~ m,^[./],;
    if (open(PID,"< $pidfile")) {
        $pid= <PID>;
        &check($1) if $pid =~ m/^\s*(\d+)\s*$/;
        close(PID);
    }
} else {
    opendir(PROC,"/proc") || &quit("failed to opendir /proc: $!");
    $foundany= 0;
    while (defined($pid= readdir(PROC))) {
        next unless $pid =~ m/^\d+$/;
        $foundany++; &check($pid);
    }
    $foundany || &quit("nothing in /proc - not mounted ?");
}

sub check {
    local ($p)= @_;
    if (defined($exec)) {
        return unless @vp= stat("/proc/$p/exe");
        return unless $vp[0] eq $ve[0] && $vp[1] eq $ve[1];
    } 
    open(C,"/proc/$p/stat");
    (@vs= stat(C)) || return;
    if (defined($user)) {
        (close(C), return) unless $vs[4] == $user;
    }
    if (defined($name)) {
        $c= <C>; close(C);
        return unless $c =~ m/^$p \(([^\)]*)\) / && $1 eq $name;
    }
    close(C);
    push(@found,$p);
}

if ($operation eq 'start') {
    if (@found) {
        print "$exec already running.\n" unless $quietmode>0;
        exit($exitnodo);
    }
    if ($testmode) {
        print "would start $startas @ARGV.\n";
        exit(0);
    }
    print "starting $exec ...\n" if $quietmode<0;
    exec($startas,@ARGV);
    &quit("unable to start $exec: $!");
}

$what= defined($name) ? $name :
       defined($exec) ? $exec :
       defined($pidfile) ? "process in pidfile \`$pidfile'" :
       defined($user) ? "process(es) owned by \`$userspec'" :
           &quit("internal error, this is a bug - please report:".
                 " no name,exec,pidfile,user");

if (!@found) {
    print "no $what found; none killed.\n" unless $quietmode>0;
    exit($exitnodo);
}

for $pid (@found) {
    if ($testmode) {
        print "would send signal $signal to $pid.\n";
    } else {
        if (kill($signal,$pid)) {
            push(@killed,$pid);
        } else {
            print "start-stop-daemon: warning: failed to kill $pid: $!\n"; #
        }
    }
}
print "stopped $what (pid @killed).\n" if $quietmode<0;
exit(0);
