# -*- perl -*-
#
# dpkg library: Debian GNU/Linux package maintenance utility,
#  useful library functions.
#
# Copyright (C) 1994 Matt Welsh <mdw@sunsite.unc.edu>
# Copyright (C) 1994 Carl Streeter <streeter@cae.wisc.edu>
# Copyright (C) 1994 Ian Murdock <imurdock@debian.org>
# Copyright (C) 1994 Ian Jackson <ian.greenend.org.uk>
#
#   dpkg is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as
#   published by the Free Software Foundation; either version 2,
#   or (at your option) any later version.
#
#   dpkg is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with dpkg; if not, write to the Free Software
#   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

#   /var/lib/dpkg/ +---- status
#                  |---- updates/ +---- <id>
#                  |              |---- tmp.i
#                  |              \---- <id>.new
#                  |---- available
#                  |---- lock
#                  |---- info/ |---- <package>.{post,pre}{inst,rm}
#                  |---- tmp.$$
#                  \---- tmp.ci/ +---- control
#                                |---- conffiles
#                                |---- {post,pre}{inst,rm}
#                                |---- list
#                                \---- conffiles

$backend = "dpkg-deb";
$fpextract = "dpkg-deb";
$md5sum = "md5sum";
$dselect = "dselect";
$dpkg = "dpkg";

$status_mergeevery = 20;
$tmp = "/tmp";
$visiblecontroldir = "DEBIAN";

sub setadmindir {
    $dd = $_[0];
    $statusdb    = "$dd/status";
    $updatesdir  = "$dd/updates";
    $availabledb = "$dd/available";
    $scriptsdir  = "$dd/info";
    $listsdir    = "$dd/info";
    $lockfile    = "$dd/lock";
    $lockmine    = "$dd/tmp.$$";
    $controli    = "$dd/tmp.ci";
    $importantspace = "$updatesdir/tmp.i";
}
$orgadmindir= "/var/lib/dpkg";
&setadmindir($orgadmindir);

@nokeepfields= ('package','version','package_revision',
                'depends','recommended','optional','conflicts','part');
# Don't keep these fields in the Available database if a new record is
# merged which is missing values for any of them.
    
$packagere = '\w[-_a-zA-Z0-9+.@:=%]+';
$packageversionre= $packagere.'(\s*\([^()]+\))?';
$singledependencyre= "$packageversionre(\\s*\\|\\s*$packageversionre)*";

# Abbreviations for dpkg-deb options common to dpkg & dpkg-deb.
%debabbrevact= ('b','build', 'c','contents', 'e','control', 'i','info',
                'f','field', 'x','extract', 'X','vextract');

@keysortorder= ('package', 'status', 'version', 'package_revision',
                'maintainer', 'description',
                'depends', 'recommended', 'optional', 'conflicts',
                'list', 'conffiles');
    
#*** replacements for things in headers ***#

#require 'sys/errno.ph';
sub ENOENT		{ 2; }		# No such file or directory
sub EEXIST		{ 17; }		# File exists
sub EISDIR		{ 21; }		# Is a directory
sub ENOTEMPTY		{ 39; }		# Directory not empty

#require 'sys/stat.ph';
sub S_IFMT	{ 00170000; }
sub S_IFREG	{ 0100000; }
sub S_IFLNK	{ 0120000; }
sub S_ISREG	{ ($_[0] & &S_IFMT) == &S_IFREG; }
sub S_ISLNK	{ ($_[0] & &S_IFMT) == &S_IFLNK; }

#require 'sys/wait.ph';
sub WIFEXITED { ($_[0] & 0x0ff) == 0; }
sub WIFSTOPPED { ($_[0] & 0x0ff) == 0x07f; }
sub WIFSIGNALED { !&WIFEXITED && !&WIFSTOPPED; }
sub WCOREDUMP { ($_[0] & 0x080) != 0; }
sub WEXITSTATUS { ($_[0] & 0x0ff00) >> 8; }
sub WSTOPSIG { ($_[0] & 0x0ff00) >> 8; }
sub WTERMSIG { $_[0] & 0x07f; }

#require 'sys/signal.ph';
sub SIGPIPE		{ 13; }

#require 'sys/syscall.ph';
sub SYS_lseek		{ 19; }


#*** /var/lib/dpkg database management - `exported' routines ***#

sub database_start {
    # Lock the package management databases, amalgamate any
    # changes files, and leave the results in:
    #  From /var/lib/dpkg/status:
    #   %st_pk2v{ package_name, field_name } = field_value
    #   %st_p21{ package_name } = 1
    #  From /var/lib/dpkg/available:
    #   %av_pk2v{ package_name, field_name } = field_value
    #   %av_p21{ package_name } = 1
    #  From both:
    #   %all_k21{ field_name } = 1
    &lock_database;
    &read_status_mainfile;
    &read_status_extrafiles;
    &write_status_mainfile;
    &delete_status_extrafiles;
    &read_available_file;
    &prepare_important_database;
    &invent_status_availableonly_packages;
}

sub database_finish {
    # Tidy up and unlock the package management databases.
    &release_important_database;
    &write_available_file;
    &write_status_mainfile;
    &delete_status_extrafiles;
    &unlock_database;
}

sub amended_status {
    # Record amended status of package (in an `extra' file).
    local (@packages) = @_;
    local ($p);
    &debug("amended @packages");
    for $p (@packages) {
        $st_pk2v{$p,'status'}= "$st_p2w{$p} $st_p2h{$p} $st_p2s{$p}";
        $st_p21{$p}= 1;
    }
    $all_k21{'status'}= 1;
    local ($ef) = sprintf("%03d",$next_extrafile++);
    &write_database_file("$updatesdir/$ef",*st_pk2v,*st_p21,1,@packages);
    push(@status_extrafiles_done,$ef); &sync;
    if ($next_extrafile >= $status_mergeevery) {
        &write_status_mainfile;
        &delete_status_extrafiles;
    }
    $status_modified= 1;
    for $p (@packages) { delete $st_pk2v{$p,'status'}; }
    &prepare_important_database;
}

sub note_amended_status {
    # Note the fact that the status has been modified, but don't
    # commit yet.
    $status_modified= 1;
}

sub amended_available {
    # Record amended available information (in core for the moment -
    # noncritical, so we defer writing it out).
    $available_modified++;
    &invent_status_availableonly_packages(@_);
}

#*** internal routines ***#

sub invent_status_availableonly_packages {
    local ($p);
    for $p (@_ ? @_ : keys %av_p21) {
        next if defined($st_p2w{$p});
        $st_p2w{$p}= 'unknown';
        $st_p2h{$p}= 'ok';
        $st_p2s{$p}= 'not-installed';
    }
}

sub read_status_mainfile {
    local ($p, @p);
    &read_status_database_file($statusdb);
}

sub read_status_extrafiles {
    local ($fn);
    opendir(UPD,$updatesdir) || &bombout("cannot opendir updates $updatesdir: $!");
    for $_ (sort readdir(UPD)) {
        next if $_ eq '.' || $_ eq '..';
        if (m/\.new$/ || m/\.old$/ || $_ eq 'tmp.i') {
            unlink("$updatesdir/$_") ||
                &bombout("cannot unlink old update temp file $updatesdir/$_: $!");
        } elsif (m/^\d+$/) {
            $fn= $_;
            &read_status_database_file("$updatesdir/$fn");
            $status_modified= 1;  push(@status_extrafiles_done, $fn);
        } else {
            warn("$name: ignoring unexpected file in $updatesdir named \`$_'\n");
        }
    }
    closedir(UPD);
}

sub read_status_database_file {
    local ($filename) = @_;
    @p= &read_database_file($filename,*st_pk2v,*st_p21);
    for $p (@p) {
        if (defined($st_pk2v{$p,'status'})) {
            $v= $st_pk2v{$p,'status'};
            $v =~ y/A-Z/a-z/;
            $v =~
                m/^(unknown|install|deinstall|purge)\s+(ok|hold)\s+(not-installed|unpacked|postinst-failed|installed|removal-failed|config-files)$/
                    || &bombout("package \`$p' has bad status in $statusdb (\`$v')");
            $st_p2w{$p}= $1;
            $st_p2h{$p}= $2;
            $st_p2s{$p}= $3;
        }
        delete($st_pk2v{$p,'status'});
    }
    $status_modified= 0; @status_extrafiles_done= ();
}
    
sub write_status_mainfile {
    return unless $status_modified;
    local ($p);
    for $p (keys %st_p21) {
        $st_pk2v{$p,'status'}= "$st_p2w{$p} $st_p2h{$p} $st_p2s{$p}";
    }
    $all_k21{'status'}= 1;
    unlink("$statusdb.old") || $!==&ENOENT ||
        &bombout("unable to remove $statusdb.old: $!");
    link("$statusdb","$statusdb.old") ||
        &bombout("unable to back up $statusdb: $!");
    &write_database_file($statusdb,*st_pk2v,*st_p21,0);
    $status_modified= 0;
    &sync;
    for $p (keys %st_p21) { delete $st_pk2v{$p,'status'}; }
}

sub delete_status_extrafiles {
#print STDERR "delete @status_extrafiles_done> "; <STDIN>;
    for $_ (@status_extrafiles_done) {
        unlink("$updatesdir/$_") ||
            &bombout("cannot remove already-done update file $updatesdir/$_: $!");
    }
    $next_extrafile= 0;
    @status_extrafiles_done= ();
}

sub read_available_file {
    &read_database_file($availabledb,*av_pk2v,*av_p21);
    $available_modified= 0;
}

sub write_available_file {
    return unless $available_modified;
    &write_database_file($availabledb,*av_pk2v,*av_p21,0);
    $available_modified= 0;
}

#*** bottom level of read routines ***#

sub read_database_file {
    local ($filename, *xx_pk2v, *xx_p21) = @_;
    local ($quick,$cf,@cf,%cf_k2v,@cwarnings,@cerrors,$p,@p)= 1;
    &debug("reading database file $filename");
    open(DB,"<$filename") || &bombout("unable to open $filename for reading: $!");
    $/="";
    @p=();
    while (defined($cf=<DB>)) {
        chop($cf);
#       $cf =~ s/\n+$/\n/;
        $p= &parse_control_entry;
#        if (@cwarnings) {
#            warn("$name: warning, packaging database file $filename\n".
#                 " contains oddities in entry for package \`$p':\n  ".
#                 join(";\n  ",@cwarnings).
#                 ".\n This is probably a symptom of a bug.\n");
#        }
        if (@cerrors) {
            &bombout("packaging database corruption - please report:\n".
                     " file $filename has error(s) in entry for \`$p':\n  ".
                     join(";\n  ",@cerrors). ".");
        }
        $xx_p21{$p}= 1;
        for $k (keys %all_k21) { $xx_pk2v{$p,$k}= $cf_k2v{$k}; }
        push(@p,$p);
    }
    &debug("database file $filename read");
    $/="\n"; close(DB);
    return @p;
}

sub parse_control_entry {
    # Expects $cf to be a sequence of lines,
    # representing exactly one package's information.
    # Results are put in cf_k2v.
    # @warnings and @errors are made to contain warning and error
    # messages, respectively.
    local ($ln,$k,$v,$p,$l);
    @cwarnings= @cerrors= ();

    undef %cf_k2v;
#   &debug(">>>$cf<<<#\n");
    if (!$quick) {
        if ($cf =~ s/\n\n+/\n/g) { push(@cwarnings, "blank line(s) found and ignored"); }
        if ($cf =~ s/^\n+//) { push(@cwarnings, "blank line(s) at start ignored"); }
        if ($cf !~ m/\n$/) {
            $cf.= "\n"; push(@cwarnings, "missing newline after last line assumed");
        }    
        if ($cf =~ s/\0//g) {
            push(@cwarnings, "nul characters discarded");
        }
    }
    $cf =~ s/\n([ \t])/\0$1/g; # join lines
#   &debug(">>>$cf<<<*\n");
    $ln = 0;
    for $_ (split(/\n/,$cf)) {
        $ln++; s/\s+$//;
        next if m/^#/;
        m/^(\S+):[ \t]*/ || (push(@cerrors, "garbage at line $ln, \`$_'"), next);
        $k= $1; $v= $'; $k =~ y/A-Z/a-z/; $k='package_revision' if $k eq 'revision';
#	&debug("key=\`$k' value=\`$v' line=\`$_'\n");
        $ln += ($v =~ s/\0/\n/g);
        $cf_k2v{$k}= $v;
        $all_k21{$k}= 1;
#     while ($cf =~ s/^(\S+):[ \t]*(.*)\n//) {
    }
    return unless keys %cf_k2v;
    $p= $cf_k2v{'package'}; delete $cf_k2v{'package'}; delete $all_k21{'package'};
    $cf_k2v{'class'} =~ y/A-Z/a-z/ if defined($cf_k2v{'class'});
    $cf_k2v{'section'} =~ y/A-Z/a-z/ if defined($cf_k2v{'section'});
#    length($cf) &&
#        push(@cerrors, "garbage at line $ln, \`".($cf =~ m/\n/ ? $` : $cf)."'");
    if (!$quick) {
        defined($p) || push(@cerrors, "no \`package' line");
        $p =~ m/^$packagere$/o || &bad_control_field('package');
        defined($cf_k2v{'version'}) || push(@cerrors, "no Version field");
        for $f ('depends','recommended','optional','conflicts') {
            next unless defined($cf_k2v{$f}) && length($cf_k2v{$f});
            $cf_k2v{$f} =~ m/^$singledependencyre(\s*,\s*$singledependencyre)*$/o
                || &bad_control_field("$f");
        }
    }
    return $p;
}

sub bad_control_field {
    push(@cerrors, "bad \`$_[0]' line, contains \`$cf_k2v{$_[0]}'");
}

#*** bottom level of database writing code ***#

sub write_database_file {
    local ($filename, *xx_pk2v, *xx_p21, $important, @packages) = @_;
    local ($p,$tl,$k,$v);
    if (!@packages) { @packages= keys(%xx_p21); }

    &debug("called write_database_file $filename, important=$important, for @packages");
    if (!$important) {
        open(DB,">$filename.new") || &bombout("unable to create $filename.new: $!");
    }
    $tl= 0;
    for $p (@packages) {
        &write_database_string("\n") if $tl;
        &write_database_string("Package: $p\n");
        for $k (keys %all_k21) {
            next unless defined($xx_pk2v{$p,$k});
            $v= $xx_pk2v{$p,$k};
            $v =~ s/\n(\S)/\n $1/g;
            &write_database_string("$k: $v\n");
        }
    }
    if ($important) {
        if (!truncate(IMP,$tl)) {
            if (print(IMP "#")) {
                warn("$name: warning - unable to truncate $importantspace: $!;".
                     "\n commenting the rest out instead seems to have worked.\n");
            } else {
                &database_corrupted("unable to truncate $importantspace: $!");
            }
        }
        close(IMP) || &database_corrupted("unable to close $importantspace: $!");
        rename($importantspace,$filename) ||
            &database_corrupted("unable to install $importantspace as $filename: $!");
    } else {
        close(DB) || &bombout("unable to close $filename.new: $!");
        rename("$filename.new",$filename) ||
            &bombout("unable to install $filename.new as $filename: $!");
    }
}

sub write_database_string {
    $tl += length($_[0]);
    if ($important) {
        print(IMP $_[0]) ||
            &database_corrupted("failed write to update file $importantspace: $!");
    } else {
        print(DB $_[0]) ||
            &bombout("failed to write to $filename.new: $!");
    }
}
        
sub database_corrupted {
    &debug("corruptingstatus @_");
    print STDERR "$name - really horrible error:\n @_\n".
        "Package manager status data is now out of step with installed system.\n".
        "(Last action has not been recorded.  Please try re-installing \`@packages'\n".
        "to ensure system consistency, or seek assistance from an expert if\n".
        "problems persist.)\n";
    &cleanup; exit(2);
}

sub prepare_important_database {
    open(IMP,"+>$importantspace") || &bombout("unable to create $importantspace: $!");
    select((select(IMP),$|=1)[0]);
    print(IMP "#padding\n"x512) || &bombout("unable to pad $importantspace: $!");
    seek(IMP,0,0) || &bombout("unable to seek (rewind) $importantspace: $!");
    &debug("important database prepared");
}

sub release_important_database {
    close(IMP);
    unlink($importantspace) || &bombout("unable to delete $importantspace: $!");
    &debug("important database released");
}

#*** database lock management ***#

sub lock_database {
    # Lock the package management databases.  Stale locks will
    # be broken, but there is no concurrency checking on the lock-
    # breaking code.
    push(@cleanups,'unlink($lockmine)');
    open(PID,">$lockmine") || &bombout("failed to create new pid file $lockmine: $!");
    printf(PID "%010d\n",$$) || &bombout("failed to add pid to $lockmine: $!");
    close(PID) || &bombout("failed to close new pid file $lockmine: $!");
    unless (link($lockmine,$lockfile)) {
        $! == &EEXIST || &bombout("failed to create lock on packages database: $!");
        if (open(PID,"<$lockfile")) {
            undef $/; $opid= <PID>; $/="\n";
            $opid =~ m/^\d{10}\n$/ || &lockfailed(" (pid missing)");
            close(PID);
            -d '/proc/self' ||
                &bombout("/proc/self not found ($!) - /proc not mounted ?");
            -d sprintf("/proc/%d",$opid) && &lockfailed(" (in use by pid $opid)");
            if (open(PID,"<$lockfile")) {
                $opid eq <PID> || &lockfailed(' (pid changed)');
                close(PID);
                unlink($lockfile) ||
                    &bombout("failed to break stale lock on database: $!");
                print STDERR
                    "$name: stale lock found on packages database, lock forced\n";
            } else {
                $!==&ENOENT ||
                    &bombout("failed to confirm who owns lock on database: $!");
            }
        } else {
            $!==&ENOENT || &bombout("failed to determine who owns lock on database: $!");
        }
        link($lockmine,$lockfile) ||
            &bombout("failed to create lock on packages database: $!");
    }
    push(@cleanups, 'unlink($lockfile) ||
                     warn("$name: failed to unlock packages database: $!\n")');
    unlink($lockmine);
}

sub unlock_database {
    unlink($lockfile) || &bombout("failed to unlock packages database: $!");
    pop(@cleanups);
}

#*** error handling ***#

sub lockfailed  { &bombout("unable to lock packages database@_"); }
sub bombout     { print STDERR "$name - critical error: @_\n"; &cleanup; exit(2); }
sub badusage    { print STDERR "$name: @_\n\n"; &usage; &cleanup; exit(3); }

sub outerr {
    &bombout("failed write to stdout: $!");
}

sub cleanup {
    while (@cleanups) {
        eval(pop(@cleanups));
        $@ && print STDERR "error while cleaning up: $@";
    }
}

sub debug {
    return unless $debug;
    print "D: @_\n";
}

sub ecode {
    local ($w,$s) = ($?,$!);
    &debug("ecode $w syserr $s");
    return
#	(($w & 0x0ffff) == 0x0ff00 ? "problems running program - exit code -1" :
#	 ($w & 0x0ff) == 0 ? "exit status ".(($w & 0x0ff00) >> 8) :
#	 ($w & 0x0ff) == 0x07f ? "stopped by signal ".(($w & 0x0ff00) >> 8) : 
#	 "killed by signal ".($w & 0x07f).($w & 0x080 ? " (core dumped)" : '')).
        (&WIFEXITED($w) ? "exit status ".&WEXITSTATUS($w) :
         &WIFSIGNALED($w) ? "killed by signal ".&WTERMSIG($w).
         (&WCOREDUMP($w) ? " (core dumped)" : ""):
         &WIFSTOPPED($w) ? "stopped due to signal ".&WSTOPSIG($w) :
         "unknown status $w").
        ($s ? ", system error $s" : '');
}

#*** miscellaneous helpful routines ***#

sub readall {
    local ($fh) = @_;
    local ($r,$n,$this) = '';
    for (;;) {
        defined($n=read($fh,$this,4096)) || return undef;
        $n || last;
        $r.= $this;
    }
    return $r;
}

#sub debug_compare_verrevs {
#    local (@i)= @_;
#    local ($i)= &x_compare_verrevs(@i);
#    &debug("compare_verrevs >@i< = >$i<");
#    return $i;
#}

sub compare_verrevs {
    local ($av,$ar,$bv,$br,$c) = @_;
    $c = &compare_vnumbers($av,$bv);  return $c if $c;
    return &compare_vnumbers($ar,$br);
}

sub compare_vnumbers {
    local ($a, $b) = @_;
    do {
        $a =~ s/^\D*//; $ad= $&; $ad =~ s/\W/ /g;
        $b =~ s/^\D*//; $bd= $&; $bd =~ s/\W/ /g;
        $cm = $ad cmp $bd; return $cm if $cm;
        $a =~ s/^\d*//; $ad= $&;
        $b =~ s/^\d*//; $bd= $&;
        $cm = $ad <=> $bd; return $cm if $cm;
    } while (length ($a) && length ($b));
    return length ($a) cmp length ($b);
}

sub sync {
    system('sync');
}
