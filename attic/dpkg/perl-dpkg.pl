#!/usr/bin/perl --
#
# dpkg: Debian GNU/Linux package maintenance utility
#
# Copyright (C) 1994 Matt Welsh <mdw@sunsite.unc.edu>
# Copyright (C) 1994 Carl Streeter <streeter@cae.wisc.edu>
# Copyright (C) 1994 Ian Murdock <imurdock@debian.org>
# Copyright (C) 1994 Ian Jackson <ian@chiark.greenend.org.uk>
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
#

$version= '0.93.15'; # This line modified by Makefile

sub version {
    print STDERR <<END;
Debian GNU/Linux \`dpkg\' package handling tool version $version.
Copyright (C)1994 Matt Welsh, Carl Streeter, Ian Murdock, Ian Jackson.
This is free software; see the GNU General Public Licence version 2
or later for copying conditions.  There is NO warranty.
END
}

sub usage {
    print STDERR <<END;
Usage: dpkg -i|--install <opts> <.deb file name> ... | -a|--auto <dir> ...
       dpkg --unpack     <opts> <.deb file name> ... | -a|--auto <dir> ...
       dpkg -A|--avail   <opts> <.deb file name> ... | -a|--auto <dir> ...
       dpkg --configure  <opts> <package name> ... | -a|--auto
       dpkg -r|--remove  <opts> <package name> ... | -a|--auto
       dpkg -l|--list   <status select> [<regexp> ...]
       dpkg -s|--status <status select> [<package-name> ...]
       dpkg -S|--search  <glob pattern> ...
       dpkg -b|--build|-c|--contents|-e|--control|--info|-f|--field|
            -x|--extract|-X|--vextract ...   (see dpkg-deb --help)
Options:  --purge  --control-quiet --control-verbose  --version  --help
          -R|--root=<directory>  --admindir=<directory>  --instdir=<directory>
          --no-keep-old-conf  --no-keep-new-conf  -N|--no-also-select
          --ignore-depends=<package name>,...
          --conf-(same|diff|all)-(new|old|promptnew|promptold)
          --force-<thing>,<thing>,...  --no-force-...|--refuse-...
Status selections:   --isok-[o][h]        (OK, Hold; alternatives are y, n)
                     --want-[u][i][d][p]  (Unknown, Install, Deinstall, Purge)
 --stat-[nupircNO] (Not, Unpacked, Postinst-failed, Installed, Removal-failed,
                    Config-files, Not/Config-files, Not/Config-files/Installed)
Force things:  conflicts, depends, downgrade, depends-version, prermfail,
               configure-any, hold, extractfail
    (default is --no-force everything, except --force-downgrade)
Use \`$dselect\' for user-friendly package management.
END
}

$instroot= '';
$controlwarn = 1;
$estatus = 0;
$filename_pattern = "*.deb";
%force= ( 'conflicts',0, 'depends',0, 'depends-version',0, 'downgrade',1,
          'prermfail',0, 'postrmfail',0, 'hold',0, 'configure-any',0,
          'extractfail',0 );

%selectmap_h= ('o','ok', 'h','hold', 'y','ok', 'n','hold');
%selectmap_w= ('u', 'unknown', 'i', 'install', 'd', 'deinstall', 'p', 'purge');
%selectmap_s= ('n', 'not-installed',
               'u', 'unpacked',
               'p', 'postinst-failed',
               'i', 'installed',
               'r', 'removal-failed',
               'c', 'config-files',
               'n', 'not-installed,config-files',
               'o', 'not-installed,config-files,installed');
%selectthings= ('isok','h', 'want','w', 'stat','s');

require 'lib.pl'; # This line modified by Makefile
$0 =~ m|[^/]+$|; $name = $dpkg;
$|=1;
umask(022);

$action= 'none';

%myabbrevact= ('i','install', 'r','remove', 'A','avail',
               'S','search', 'l','list', 's','status');

# $conf...[0] corresponds to `same', 1 to diff
$confusenew[0]= 0;  $confprompt[0]= 0;
$confusenew[1]= 1;  $confprompt[1]= 1;
# Ie, default is to prompt only when hashes differ,
# and to use new when hashes differ

while ($ARGV[0] =~ m/^-/) {
    $_= shift(@ARGV);
    $noptsdone++;
    if (m/^--$/) {
        $noptsdone--; last;
    } elsif (m/^--(install|remove|unpack|configure|avail|list|status)$/) {
        &setaction($1);
    } elsif (m/^--(build|contents|control|info|field|extract|vextract)$/) {
        $noptsdone--; &backend($1);
    } elsif (m/^--ignore-depends=($packagere(,$packagere)*)$/o) {
        grep($ignore_depends{$_}=1, split(/,/,$1));
    } elsif (m/^--(force|no-force|refuse)-/) {
        $fvalue= ($1 eq 'force');
        for $fv (split(/,/,$')) {
            defined($force{$fv}) || &badusage("unknown --force option \`$fv'");
            $force{$fv}= $fvalue;
        }
    } elsif (m/^--conf-(same|diff|all)-(new|old|promptnew|promptold)$/) {
        $new= $2 eq 'new' || $2 eq 'promptnew';
        $prompt= $2 eq 'promptnew' || $2 eq 'promptold';
        if ($1 ne 'same') { $confusenew[1]= $new; $confprompt[1]= $prompt; }
        if ($1 ne 'diff') { $confusenew[0]= $new; $confprompt[0]= $prompt; }
    } elsif (m/^--(\w+)-(\w+)$/ && defined($selectthings{$1})) {
        $thisname= $1;
        $thisthing= $selectthings{$thisname};
        $_=$2;
        eval '%thismap= %selectmap_'.$thisthing;
        while (s/^.//) {
            if (!defined($thismap{$&})) {
                &badusage("unknown status letter $& for status field $thisname");
            }
            $thiscodes= $thismap{$&};
            $selectdo.= "undef \$select_$thisthing;";
            for $v (split(m/,/, $thiscodes)) {
                $selectdo .= "\$select_$thisthing{'$v'}=1;";
            }
        }
    } elsif (m/^--root=/) {
        $instroot=$'; &setadmindir("$instroot/$orgadmindir");
    } elsif (m/^--admindir=/) {
        &setadmindir("$'");
    } elsif (m/^--instdir=/) {
        $instroot=$';
    } elsif (m/^--auto$/) {
        $auto= 1;
    } elsif (m/^--purge$/) {
        $purge= 1;
    } elsif (m/^--skip-same-version$/) {
        print STDERR
            "Warning: dpkg --skip-same-version not implemented, will process\n".
            " process even packages the same version of which is installed.\n";
    } elsif (m/^--no-also-select$/) {
        $noalsoselect= 1;
    } elsif (m/^--control-verbose$/) {
        $controlwarn= 1;
    } elsif (m/^--control-quiet$/) {
        $controlwarn= 0;
    } elsif (m/^--no-keep-old-conf$/) {
        $nokeepold= 1;
    } elsif (m/^--no-keep-new-conf$/) {
        $nokeepnew= 1;
    } elsif (m/^--succinct-prompts$/) {
        $succinct= 1;
    } elsif (m/^--debug$/) {
        $debug= 1;
    } elsif (m/^--help$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } elsif (m/^--/) {
        &badusage("unknown option \`$_'");
    } else {
        s/^-//; $noptsdone--;
        while (s/^.//) {
            $noptsdone++;
            if (defined($myabbrevact{$&})) {
                &setaction($myabbrevact{$&});
            } elsif (defined($debabbrevact{$&})) {
                $noptsdone--; &backend($debabbrevact{$&});
            } elsif ($& eq 'a') {
                $auto= 1;
	    } elsif ($& eq 'D') {
		$debug= 1;
	    } elsif ($& eq 'N') {
		$noautoselect= 1;
            } elsif ($& eq 'R') {
                s/^=// || &badusage("missing value for -R=<dir> option");
                $instroot= $_; &setadmindir("$instroot/$orgadmindir"); $_='';
            } else {
                &badusage("unknown option \`-$&'");
            }
        }
    }
}

$action eq 'none' && &badusage("an action must be specified");

&debug("arguments parsed");

#*** list, status or search - the nonactive operations ***#

if ($action eq 'list' || $action eq 'status') {
    &database_start;
    if ($action eq 'list' || !@ARGV) {
        &selectall(*selectmap_h,*select_h);
        &selectall(*selectmap_w,*select_w);
        &selectall(*selectmap_s,*select_s);
        if (@ARGV) { $select_s{'not-installed'}=0; }
    }
    $ecode= 0;
    if ($action eq 'status') {
        for ($i=0;$i<=$#keysortorder;$i++) {
            $keysortorder{$keysortorder[$i]}= sprintf("%6d ",$i);
#           &debug("set $i: $keysortorder[$i], sortorder ".
#                  "\`$keysortorder{$keysortorder[$i]}'");
        }
        @ARGV= &applyselcrit(sort keys %st_p21) unless @ARGV;
        for $p (@ARGV) {
            if (!$st_p21{$p}) {
                print(STDERR "$name: no information available about package $p\n")
                    || &bombout("writing to stderr: $!");
                $ecode= 1;
            }
            print("Package: $p\n",
                  "Status: $st_p2w{$p} $st_p2h{$p} $st_p2s{$p}\n") || &outerr;
            for $k (sort { $keysortorder{$a}.$a cmp $keysortorder{$b}.$b; }
                    keys %all_k21) {
#               &debug("field $k, sortorder \`$keysortorder{$k}'");
                next unless defined($st_pk2v{$p,$k});
                $v= $st_pk2v{$p,$k}; next unless length($v);
                if ($k eq 'conffiles' || $k eq 'list') {
                    $v= sprintf("(%d files, not listed)",
                                scalar(grep(m/\S/, split(/\n/,$v))));
                }
                print("$k: $v\n") || &outerr;
            }
            if (defined($av_p21{$p})) {
                print("\n\`Available' version of package $p, where different:\n")
                    || &outerr;
                for $k (keys %all_k21) {
                    next unless defined($av_pk2v{$p,$k});
                    $v= $st_pk2v{$p,$k}; next unless length($v);
                    $u= $st_pk2v{$p,$k}; next if $u eq $v;
                    print("$k: $v\n") || &outerr;
                }
                print("\n") || &outerr;
            }
        }
    } else { # $action eq 'list'
        $listhead=0;
        if (@ARGV) {
            for $r (@ARGV) {
                &listinfo(&applyselcrit(sort grep(m/$r/,keys %st_p21)));
            }
        } else {
            undef $r;
            &listinfo(&applyselcrit(sort keys %st_p21));
        }
    }
    &database_finish;
    exit($ecode);
}

sub listinfo {
    if (!@_) {
        print(STDERR
              defined($r) ?
              "No selected packages found matching regexp \`$r'.\n" :
              "No packages matched selection criteria.\n") ||
                  &bombout("writing to stderr: $!");
        return;
    }

    if (!$listhead) {
        print <<END
Err?  Name       Version    Rev Description
| Status=Not/Unpacked/Postinst-failed/Installed/Removal-failed/Config-files
|/ Desired=Unknown/Install/Deinstall/Purge
||/   |          |          |   |
+++-============-==========-===-===============================================
END
            || &outerr;
        $listhead= 1;
    }
    for $p (@_) {
        $des= $st_pk2v{$p,'description'};
        $des= $` if $des =~ m/\n/;
        printf("%s%.1s%.1s %-12.12s %-10.10s %-3.3s %-47.47s\n",
               $st_p2h{$p} eq 'hold' ? 'x' : ' ', $st_p2s{$p}, $st_p2w{$p},
               $p, $st_pk2v{$p,'version'}, $st_pk2v{$p,'package_revision'},
               $des);
    }
}

sub applyselcrit {
    &debug("sel from @_");
    for $f (@_) { &debug("$f :$st_p2s{$f},$select_s{$st_p2s{$f}}:$st_p2w{$f},$select_w{$st_p2w{$f}}:$st_p2h{$f},$select_h{$st_p2h{$f}}:"); }
    @ascr= grep($select_s{$st_p2s{$_}} &&
                $select_w{$st_p2w{$_}} &&
                $select_h{$st_p2h{$_}},
                @_);
    &debug("sel gave @ascr");
    @ascr;
}

sub selectall {
    local (*map, *sel) = @_;
    local ($v);
    for $v (values %map) {
        next if m/,/;
        $sel{$v}=1;
    }
}

if ($action eq 'search') {
    @ARGV || &badusage("need at least one glob pattern for --$action");
    &database_start;
    while (@ARGV) {
        $orgpat= $_= shift(@ARGV);
        s/\W/\\$&/g;
        s|\\\*\\\*|.*|g;
        s|\\\*|[^/]*|g;
        s|\\\?|[^/]|g;
        $pat= $_; $f=0;
        for $p (sort keys %st_p21) {
            $s= $st_p2s{$p};
            next if $s eq 'not-installed' || $s eq 'config-files';
            &filesinpackage($arg, $package);
            @ilist= grep(m/^$pat$/,@ilist);
            next unless @ilist;
            $f=1;
            for $_ (@ilist) { print("$p: $_\n") || &outerr; }
        }
        if (!$f) {
            print(STDERR "No packages found containing \`$orgpat'.\n")
                || &bombout("writing to stderr: $!");
            $ecode= 1;
        }
    }
    &database_finish;
    exit($ecode);
}

#*** lock and read in databases ***#

&database_start;
&debug("databases read");

#*** derive argument list for --auto ***#

if ($auto) {
    if ($action eq 'install' || $action eq 'unpack' || $action eq 'avail') {
        @ARGV || &badusage("need at least one directory for --$action --auto");
        pipe(RP,WP) || &bombout("create pipe for \`find': $!");
        defined($c= fork) || &bombout("fork for \`find': $!");
        if (!$c) {
            close(RP); open(STDOUT,">& WP"); close(WP);
            exec('find',@ARGV,'-name',$filename_pattern,'-type','f','-print0');
            die "$name: could not exec \`find': $!";
        }
        close(WP);
        $/="\0"; @ARGV= <RP>; $/="\n";
        eof || &bombout("read filenames from \`find': $!");
        close(RP);
        $!=0; waitpid($c,0) eq $c || &bombout("wait for \`find' failed: $!");
        $? && &bombout("\`find' process returned error code ".&ecode);
        @ARGV || &bombout("no packages found to $action");
    } else {
        @ARGV && &badusage("no package names may be specified with --$action --auto");
        if ($action eq 'remove') {
            eval 'sub condition {
                $wants eq "deinstall" || $wants eq "purge" || return 0;
                $cstatus eq "not-installed" && return 0;
                $cstatus eq "config-files" && $wants eq "deinstall" && return 0;
                return 1;
            } 1;' || &internalerr("sub condition: $@");
        } elsif ($action eq 'configure') {
            eval 'sub condition {
                $wants eq "install" || return 0;
                $cstatus eq "unpacked" || $cstatus eq "postinst-failed" || return 0;
                return 1;
            } 1;' || &internalerr("sub condition: $@");
        } else {
            &internalerr("unknown auto nonames action $action");
        }
        for $p (keys %st_p21) {
            next if $st_p2h{$p} eq 'hold';
            $wants= $st_p2w{$p}; $cstatus= $st_p2s{$p};
            next unless &condition;
            push(@ARGV,$p);
        }
    }
    &debug("auto: arglist @ARGV");
} else {
    @ARGV || &badusage("need a list of packages or filenames");
}

if ($action eq 'install' || $action eq 'unpack') {
    grep(s:^[^/.]:./$&:, @ARGV); # Sanitise filenames
}

&debug("action: $action; arglist @ARGV");

#*** actually do things ***#

for $arg (@ARGV) {
    $package= ''; @undo=();
    &debug("&do_$action($arg)");
    if (!eval "&do_$action(\$arg); 1;") { &handleerror || last; }
    &checkpointstatus;
}
&checkpointstatus;

if (!$abort) {
    &debug("&middle_$action($arg)");
    if (!eval "&middle_$action; 1;") { print STDERR $@; $abort=1; }
}
&checkpointstatus;

if (!$abort) {
    while (@deferred) {
        $arg= shift(@deferred); $package= ''; @undo=();
	&debug("&deferred_$action($arg) ($dependtry: $sincenothing)");
        if (!eval "&deferred_$action(\$arg); 1;") { &handleerror || last; }
        &checkpointstatus;
    }
    &checkpointstatus;
}

if ($errors) {
    print STDERR "$name: $errors errors occurred.\n";
    $estatus= 1;
}

&database_finish;
&cleanup;

exit($estatus);

#*** useful subroutines for main control section ***#

sub handleerror {
    print STDERR $@;
    if (length($package) && defined($st_p21{$package})) {
        $st_p2h{$package}='hold'; &amended_status($package);
    }
    $errors++;
    if ($errors >20) { print STDERR "$name: too many errors, halting\n"; return 0; }
    return !$abort;
}

sub checkpointstatus {
    return unless keys %statusupdated;
    &amended_status(keys %statusupdated);
    undef %statusupdated;
}

sub backend {
    &setaction('');
    ($noptsdone) && &badusage("action \`$_[0]' must be first argument");
    &debug("backend --$_[0]");
    exec($backend, "--$_[0]", @ARGV);
    &bombout("unable to run $backend: $!");
}

sub setaction {
    $action eq 'none' || &badusage("conflicting actions \`$action' and \`$1'");
    $action= $_[0];
}

#*** error handlers for use in actions ***#

sub warn        { warn "$name - warning: @_\n"; }
sub subcriterr  { warn "$name - subcritical error: @_\n"; $estatus=1; }
sub error       { &acleanup; die "$name - error: @_\n"; }
sub internalerr { &acleanup; die "$name - internal error, please report: @_\n"; }
sub fatalerr    { &acleanup; die "$name - fatal error, halting: @_\n"; $abort=1; }

sub corruptingerr {
    local ($corruptingerr)= @_;
    &acleanup;
    die "$name - horrible error: $corruptingerr;\n".
        "Package manager data is now out of step with installed system.\n".
        "Please re-install \`$package' to ensure system consistency!\n".
        "(Seek assistance from an expert if problems persist.)\n";
    $abort=1;
}

sub forcibleerr {
    local ($msg,@forces) = @_;
    if (@forces= grep($force{$_},@forces)) {
        &warn("$msg (proceeding due to --force-$forces[0])");
    } else {
        &error("$msg (skipping this package)");
    }
}

sub acleanup {
    while (@undo) {
        eval(pop(@undo));
        $@ && print STDERR "error while cleaning up: $@";
    }
}

#*** --install ***#

sub do_install {
    &do_unpack($arg);
    $arg= $package;
    &do_configure($arg);
}

sub deferred_install { &deferred_configure; }

sub middle_install { &middle_configure }

#*** --avail ***#

sub do_avail {
    unlink($controli);
    if ($! != &ENOENT) {
        system('rm','-rf',$controli);
        unlink($controli);
        $! == &ENOENT || &fatalerr("unable to get rid of $controli: $!");
    }
    &debug("extract control $backend --control $arg $controli");
    $!=0; system($backend,"--control",$arg,$controli);
    $? && &error("$arg: could not extract control information (".&ecode.")");
    open(CONTROL,"$controli/control") ||
        &error("$arg: corrupt - unable to read control file: $!");
    &parse_control("$arg");
    for $k (keys %cf_k2v) {
        $av_pk2v{$p,$k}= $cf_k2v{$k};
    }
    for $k (@nokeepfields) {
        delete $av_pk2v{$p,$k} unless defined($cf_k2v{$k});
    }
    &amended_available($p);
    $package=$p;
}

sub deferred_avail { }
sub middle_avail { }

#*** --unpack ***#

sub middle_unpack { }

sub do_unpack {
    &do_avail;
    $cstatus= $st_p2s{$package};
    if ($st_p2w{$package} ne 'install') {
        if (!$noalsoselect) {
            $st_p2w{$package}= 'install'; $statusupdated{$package}= 1;
            print STDOUT "Selecting previously deselected package $package.\n";
        } else {
            print STDOUT "Skipping deselected package $package.\n";
            return;
        }
    }
    for $tp (split(/,/, $av_pk2v{$package,'conflicts'})) {
	$tp =~ s/^\s*//; $tp =~ s/\s+$//;
        ($tps, $rightver, $inst, $want, $tpp)= &installationstatus($tp);
        unless ($tps eq 'not-installed' || $tps eq 'config-files' || !$rightver) {
            &forcibleerr("$arg: conflicts with package $tpp ($want),".
                         " found $inst on system",
                         'conflicts');
        }
    }
    if ($cstatus eq 'installed') {
        if (&compare_verrevs($av_pk2v{$package,'version'},
                             $av_pk2v{$package,'package_revision'},
                             $st_k2v{'version'},$st_k2v{'package_revision'}) <0) {
            &forcibleerr("$arg: downgrading installed $package version ".
                         "$st_k2v{'version'}, ".
                         "package revision $st_k2v{'package_revision'} ".
                         "to older version ".
                         "$av_pk2v{$package,'version'}, ".
                         "package revision $av_pk2v{$package,'package_revision'}",
                         'downgrade');
        }
    }
    if (open(CONF,"$controli/conffiles")) {
        @configf= <CONF>;
        eof || &error("$arg: unable to read $controli/conffiles: $!");
        close(CONF);
        grep((chop, m,^/, || s,^,/,), @configf);
    } elsif ($! != &ENOENT) {
        &error("$arg: cannot get config files list: $!");
    } else {
        @configf= ();
    }

    if ($cstatus eq 'installed' || $cstatus eq 'unpacked' ||
        $cstatus eq 'postinst-failed' || $cstatus eq 'removal-failed') {
        &filesinpackage($arg,$package);
        print STDOUT "Preparing to replace $package ...\n";
    }
    if ($cstatus eq 'installed') {
        if (!eval {
            &run_script_ne("$scriptsdir/$package.prerm", 'old pre-removal script',
			   'upgrade',
                           $av_pk2v{$package,'version'}.'-'.
                           $av_pk2v{$package,'package_revision'});
            1;
        }) {
            &warn("$@... trying script from new package instead.");
            &run_script("$controli/prerm", 'new prerm script',
			'failed-upgrade',
                        $st_k2v{'version'}.'-'.$st_k2v{'package_revision'});
        }
        push(@undo,
             '$st_p2s{$package}= "postinst-failed"; $statusupdated{$package}=1;
             &run_script_ne("$scriptsdir/$package.postinst",
                            "old post-installation script",
                            "abort-upgrade",
                            $av_pk2v{$package,"version"}."-".
                            $av_pk2v{$package,"package_revision"});
             $st_p2s{$package}= "installed"; $statusupdated{$package}=1;');
    }
    @fbackups=();
    if ($cstatus eq 'installed' || $cstatus eq 'unpacked' ||
        $cstatus eq 'postinst-failed' || $cstatus eq 'removal-failed') {
        for ($i=0; $i<=$#ilist; $i++) {
            next if grep($_ eq $ilist[$i], @configf);
            $_= $ilist[$i];
            unless (lstat("$instroot/$_")) {
                $! == &ENOENT || &error("old file $_ unstattable: $!");
                next;
            }
            next if -d _;
            rename("$instroot/$_","$instroot/$_.dpkg-tmp") ||
                &error("couldn't rename old file $_ to $_.dpkg-tmp: $!");
            push(@undo,
                 '$_=pop(@fbackups); rename("$instroot/$_.dpkg-tmp","$instroot/$_") ||
                  die "unable to undo rename of $_ to $_.dpkg-tmp: $!"');
            push(@fbackups, $_);
        }
        if (!eval {
            &run_script_ne("$scriptsdir/$package.postrm", 'old post-removal script',
			   'upgrade',
                           $av_pk2v{$package,'version'}.'-'.
                           $av_pk2v{$package,'package_revision'});
            1;
        }) {
            &warn("$@... trying script from new package instead.");
            &run_script("$controli/postrm", 'new post-removal script',
			'failed-upgrade',
                        $st_k2v{'version'}.'-'.$st_k2v{'package_revision'});
        }
        push(@undo,
             '&run_script_ne("$scriptsdir/$package.preinst",
                             "old pre-installation script",
                             "abort-upgrade",
                             $av_pk2v{$package,"version"}.
                             "-".$av_pk2v{$package,"package_revision"})');
    }
    $shortarg= $arg; $shortarg =~ s:.{15,}/:.../:;
    print STDOUT "Unpacking $arg, containing $package ...\n";
    &run_script("$controli/preinst", 'pre-installation script',
		'upgrade', $st_k2v{'version'}.'-'.$st_k2v{'package_revision'});
    push(@undo,'&run_script_ne("$controli/postrm", "post-removal script",
                               "abort-upgrade",
                               $st_k2v{"version"}."-".$st_k2v{"package_revision"})');
    if ($cstatus ne 'not-installed') {
        for $_ (split(/\n/,$st_pk2v{$package,'conffiles'})) {
            s/^ //; next unless length($_);
            if (!m/^(\S+) (-|newconffile|nonexistent|[0-9a-f]{32})$/) {
                &warn("$arg: ignoring bad stuff in old conffiles field \`$_'");
                next;
            }
            $oldhash{$1}= $2;
        }
    }
    for $f (@configf) {
        $drf= &conffderef($f); if (!defined($drf)) { next; }
        if (lstat("$instroot/$drf.dpkg-tmp")) {
            $undo=1;
        } else {
            $! == &ENOENT || &error("unable to stat backup config file $_.dpkg-tmp: $!");
            if (lstat("$instroot/$drf")) {
                rename("$instroot/$drf","$instroot/$drf.dpkg-tmp") ||
                    &error("couldn't back up config file $f (= $drf): $!");
                $undo=1;
            } elsif ($! == &ENOENT) {
                $undo=0;
            } else {
                &error("unable to stat config file $drf: $!");
            }
        }
        if ($undo) {
            push(@undo,
                 '$_=pop(@undof); rename("$instroot/$_.dpkg-tmp","$instroot/$_") ||
                 die "unable to undo backup of config file $_: $!"');
            push(@undof, $drf);
        }
    }

    open(NL,">$listsdir/$package.list.new") ||
        &error("$package: cannot create $listsdir/$package.list.new: $!");
    defined($c= fork) || &error("$package: cannot pipe/fork for $backend --vextract");
    if (!$c) {
        if (!open(STDOUT,">&NL")) {
            print STDERR "$name: cannot redirect stdout: $!\n"; exit(1);
        }
        $vexroot= length($instroot) ? $instroot : '/';
        exec($backend,"--vextract",$arg,$vexroot);
        print STDERR "$name: cannot exec $backend --vextract $arg $vexroot: $!\n";
        exit(1);
    }
    $!=0; waitpid($c,0) == $c || &error("could not wait for $backend: $!");
    $? && &forcibleerr("$package: failed to install (".&ecode.")", 'extractfail');

    rename("$listsdir/$package.list.new","$listsdir/$package.list") ||
        &error("$package: failed to install new $listsdir/$package.list: $!");
    
    $newconff='';
    for $f (@configf) {
        $h= $oldhash{$f};
        $h='newconffile' unless length($h);
        $newconff.= "\n $f $h";
        &debug("new hash, after unpack, of $f, is $h");
    }

    for $k (keys %all_k21) {
        next if $k eq 'binary' || $k eq 'source' || $k eq 'section';
        $st_pk2v{$package,$k}= $av_pk2v{$package,$k};
    }
    $st_pk2v{$package,'conffiles'}= $newconff; $all_k21{'conffiles'}= 1;
    $st_p2s{$package}= 'unpacked'; $st_p2h{$package}= 'ok'; $st_p21{$package}= 1;
    $statusupdated{$package}= 1;
    @undo=(); @undof=();

    for $f (@fbackups) {
        unlink("$instroot/$f.dpkg-tmp") || $! == &ENOENT ||
            &subcriterr("$package: unable to delete saved old file $f.dpkg-tmp: $!\n");
    }

    undef %fordeletion;
    opendir(PI,"$scriptsdir") ||
        &corruptingerr("$package: unable to read $scriptsdir directory ($!)");
    while(defined($_=readdir(PI))) {
        next unless substr($_,0,length($package)+1) eq $package.'.';
        $fordeletion{$_}= 1;
    }
    closedir(PI);
    opendir(PI,"$controli") ||
        &corruptingerr("$package: unable to read $controli".
                       " new package control information directory ($!)");
    $fordeletion{"$package.list"}= 0;
    while(defined($_=readdir(PI))) {
        next if m/^\.\.?$/ || m/^conffiles$/ || m/^control$/;
        rename("$controli/$_","$scriptsdir/$package.$_") ||
            &corruptingerr("$package: unable to install new package control".
                           " information file $scriptsdir/$package.$_ ($!)");
        $fordeletion{"$package.$_"}= 0;
    }
    closedir(PI);
    for $_ (keys %fordeletion) {
        next unless $fordeletion{$_};
        unlink("$scriptsdir/$_") ||
            &corruptingerr("$package: unable to remove old package script".
                           " $scriptsdir/$_ ($!)");
    }
}

#*** --configure ***#

sub do_configure {
    $package=$arg; $cstatus= $st_p2s{$package};
    if (!defined($st_p21{$package})) { $cstatus= 'not-installed'; }
    unless ($cstatus eq 'unpacked' || $cstatus eq 'postinst-failed') {
        if ($cstatus eq 'not-installed') {
            &error("no package named \`$package' is installed, cannot configure");
        } else {
            &error("$package: is currently in state \`$cstatus', cannot configure");
        }
    }
    push(@deferred,$package);
}

sub middle_configure {
    $sincenothing=0; $dependtry=1;
}

sub deferred_configure {
    # The algorithm for deciding what to configure first is as follows:
    # Loop through all packages doing a `try 1' until we've been round
    # and nothing has been done, then do `try 2' and `try 3' likewise.
    # Try 1:
    #  Are all dependencies of this package done ?  If so, do it.
    #  Are any of the dependencies missing or the wrong version ?
    #   If so, abort (unless --force-depends, in which case defer)
    #  Will we need to configure a package we weren't given as an
    #   argument ?  If so, abort - except if --force-configure-any,
    #   in which case we add the package to the argument list.
    #  If none of the above, defer the package.
    # Try 2:
    #  Find a cycle and break it (see above).
    #  Do as for try 1.
    # Try 3 (only if --force-depends-version).
    #  Same as for try 2, but don't mind version number in dependencies.
    # Try 4 (only if --force-depends).
    #  Do anyway.
    $package= $arg;
    if ($sincenothing++ > $#deferred*2+2) {
        $dependtry++; $sincenothing=0;
        &internalerr("$package: nothing configured, but try was already 4 !")
            if $dependtry > 4;
    }
    if ($dependtry > 1) { &findbreakcycle($package); }
    ($ok, @aemsgs) = &dependencies_ok($package,'');
    if ($ok == 1) {
        push(@deferred,$package); return;
    } elsif ($ok == 0) {
        $sincenothing= 0;
        &error("$arg: dependency problems - not configuring this package:\n ".
               join("\n ",@aemsgs));
    } elsif (@aemsgs) {
        &warn("$arg: dependency problems, configuring anyway as you request:\n ".
              join("\n ",@aemsgs));
    }
    $sincenothing= 0;
    print STDOUT "Setting up $package ...\n";
    if ($st_p2s{$package} eq 'unpacked') {
        &debug("conffiles updating >$st_pk2v{$package,'conffiles'}<");
        undef %oldhash; @configf=();
        for $_ (split(/\n/,$st_pk2v{$package,'conffiles'})) {
            s/^ //; next unless length($_);
            if (!m/^(\S+) (-|newconffile|nonexistent|[0-9a-f]{32})$/) {
                &warn("$arg: ignoring bad stuff in old conffiles field \`$_'");
                next;
            }
            $oldhash{$1}= $2; push(@configf,$1);
            &debug("old hash of $1 is $2");
        }
        undef %newhash;
        for $file (@configf) {
            $drf= &conffderef($file);
            if (!defined($drf)) { $newhash{$file}= '-'; next; }
            $newhash{$file}= &hash("$instroot/$drf");
            &debug("new hash of $file is $newhash{$file} (old $oldhash{$file})");
            if ($oldhash{$file} eq 'newconffile') {
                $usenew= 1;
            } else {
                if (!&files_not_identical("$instroot/$drf",
                                          "$instroot/$drf.dpkg-tmp")) {
                    rename("$instroot/$drf.dpkg-tmp",$drf) || $!==&ENOENT ||
                        &error("$package: unable to reinstall ".
                               "existing conffile $drf.dpkg-tmp: $!");
                    &debug("files identical $file");
                } else {
                    $diff= $newhash{$file} ne $oldhash{$file};
                    $usenew= $confusenew[$diff];
                    &debug("the decision - diff $diff;".
                           " usenew $usenew prompt $confpromt[$diff]");
                    if ($confprompt[$diff]) {
                        $symlinked = $drf eq $file ? '' :
                            $succinct ? " (-> $drf)" :
                                " (which is a symlink to $drf)";
                        for (;;) {
                            print
                                $succinct ? "
Package $package, file $file$symlinked, ".($diff ? "CHANGED": "not changed")
                                  : $diff ? "
In package $package, distributed version of configuration
file $file$symlinked has changed
since the last time it was installed.  You may:
 * Install the new version and edit it later to reflect your wishes.
   ". ($nokeepold ?
  "(Your old version will not be saved.)" :
  "(Your old version will be saved in $drf.dpkg-old.)") . "
 * Leave your old version in place, and perhaps check later that
   you don't want to update it to take account of new features.
   ". ($nokeepnew ?
  "(The new version be discarded.)" :
  "(The new version will be placed in $drf.dpkg-new.)")
                                          : "
Package $package contains the same distributed version of
configuration file $file$symlinked
as the last time it was installed.  You may:
 * Install the distributed version, overwriting your changes.
   ". ($nokeepold ?
  "(Your changed version will not be saved.)" :
  "(Your changed version will be saved in $drf.dpkg-old.)") . "
 * Leave your own version in place.
   ". ($nokeepnew ?
  "(The distributed version be discarded.)" :
  "(The distributed version will be placed in $drf.dpkg-new.)");

                            print "
$file: install new version ? (y/n, default=". ($usenew?'y':'n'). ")  ";

                            $!=0; defined($iread= <STDIN>) ||
                                &error("$package: prompting, EOF/error on stdin: $!");
                            $_= $iread; s/^\s*//; s/\s+$//;
                            ($usenew=0, last) if m/^n(o)?$/i;
                            ($usenew=1, last) if m/^y(es)?$/i;
                            last if m/^$/;
                            print "\nPlease answer \`y' or \`n'.\n";
                        }
                    }
                    &debug("decided, usenew $usenew");
                    if ($usenew) {
                        &copyperm("$drf.dpkg-tmp",$drf,$drf);
                        if ($nokeepold) {
                            unlink("$instroot/$drf.dpkg-tmp") || $!==&ENOENT ||
                                &error("$package: unable to delete old conffile ".
                                       "$drf.dpkg-tmp: $!");
                            unlink("$instroot/$drf.dpkg-old") || $!==&ENOENT ||
                                &error("$package: unable to delete very old ".
                                       "conffile $drf.dpkg-old: $!");
                        } else {
                            rename("$instroot/$drf.dpkg-tmp","$instroot/$drf.dpkg-old")
                                || $!==&ENOENT ||
                                    &error("$package: unable to back up old conffile ".
                                           "$drf.dpkg-tmp as $drf.dpkg-old: $!");
                        }
                    } else {
                        unlink("$instroot/$drf.dpkg-new") || $!==&ENOENT ||
                            &error("$package: unable to delete old new conffile ".
                                   "$drf.dpkg-new: $!");
                        if (!$nokeepnew) {
                            link("$instroot/$drf","$instroot/$drf.dpkg-new")
                                || $!==&ENOENT ||
                                    &error("$package: unable save new conffile ".
                                           "$drf as $drf.dpkg-new: $!");
                        }
                        if (!rename("$instroot/$drf.dpkg-tmp","$instroot/$drf")) {
                            $!==&ENOENT || &error("$package: unable reinstall old ".
                                                  "conffile $drf.dpkg-tmp as $drf: $!");
                            unlink("$instroot/$drf");
                        }
                    }
                }
            }
        }
        $newconff='';
        for $f (@configf) {
            $h= $newhash{$f}; $newconff.= "\n $f $h";
        }
        $st_pk2v{$package,'conffiles'}= $newconff; $all_k21{'conffiles'}= 1;
    }
    $st_p2s{$package}= 'postinst-failed'; $statusupdated{$package}= 1;
    &run_script("$scriptsdir/$package.postinst",
                'post-installation script', 'configure');
    $st_p2s{$package}= 'installed';
    $st_p2h{$package}= 'ok'; $statusupdated{$package}= 1;
}

#*** --remove ***#

sub do_remove {
    $package=$arg; $cstatus= $st_p2s{$package};
    if (!defined($st_p21{$package}) ||
        $cstatus eq 'not-installed' ||
        !$purge && $cstatus eq 'config-files') {
        &error("$package: is not installed, cannot remove");
    }
    push(@deferred,$package);
    if (!$auto) {
        $ns= $purge ? 'purge' : 'deinstall';
        if ($st_p2w{$package} ne $ns) {
            $st_p2w{$package}= $ns; $statusupdated{$package}= 1;
        }
    }
}

sub middle_remove {
    $sincenothing=0; $dependtry=1;
    for $p (keys %st_p2s) {
        $cstatus= $st_p2s{$p};
        next unless $cstatus eq 'installed';
        for $tp (split(/[\|,]/, $st_pk2v{$p,'depends'})) {
            $tp =~ s/\s*\(.+\)\s*$//; $tp =~ s/^\s*//; $tp =~ s/\s+$//;
            $tp =~ m/^$packagere$/o ||
                &internalerr("package $p dependency $tp didn't match re");
            $depended{$tp}.= "$p ";
        }
    }
}

sub deferred_remove {
    $package= $arg;
    if ($sincenothing++ > $#deferred*2+2) {
        $dependtry++; $sincenothing=0;
        &internalerr("$package: nothing configured, but try was already 4 !")
            if $dependtry > 4;
    }
    @raemsgs= (); $rok= 2;
    &debug("$package may be depended on by any of >$depended{$package}<");
    for $fp (split(/ /, $depended{$package})) {
        next if $fp eq '' || $ignore_depends{$tp};
	$is= $st_p2s{$fp};
	next if $is eq 'not-installed' || $is eq 'unpacked' ||
     	        $is eq 'removal-failed' || $is eq 'config-files';
	if ($dependtry > 1) { &findbreakcycle($fp); }
        ($ok, @aemsgs) = &dependencies_ok($fp,$package);
        if ($rok != 1) { push(@raemsgs,@aemsgs); }
        $rok= $ok if $ok < $rok;
    }
    if ($rok == 1) {
        push(@deferred,$package); return;
    } elsif ($rok == 0) {
        $sincenothing= 0;
        &error("$arg: dependency problems - not removing this package:\n ".
               join("\n ",@raemsgs));
    } elsif (@raemsgs) {
        &warn("$arg: dependency problems, removing anyway as you request:\n ".
              join("\n ",@raemsgs));
    }
    $sincenothing= 0;
    &filesinpackage($arg,$package);

    undef %hash; @configfr= @configf= ();
    for $_ (split(/\n/,$st_pk2v{$package,'conffiles'})) {
        s/^ //; next unless length($_);
        if (!m/^(\S+) (-|newconffile|nonexistent|[0-9a-f]{32})$/) {
            &warn("$arg: ignoring bad stuff in old conffiles field \`$_'");
            next;
        }
        unshift(@configfr,$1); push(@configf,$1);
        $hash{$1}= $2;
    }
    
    if ($st_p2s{$package} ne 'config-files') {
	print STDOUT "Removing $package ...\n";
        &run_script("$scriptsdir/$package.prerm", 'pre-removal script', 'remove');
        $st_p2s{$package}= 'removal-failed'; $statusupdated{$package}= 1;
        for $file (reverse @ilist) {
            next if grep($_ eq $file, @configf);
            unlink("$instroot/$file.dpkg-tmp") || $! == &ENOENT ||
                &error("$arg: cannot remove supposed old temp file $file: $!");
            next if unlink("$instroot/$file");
            next if $! == &ENOENT;
            &error("$arg: cannot remove file $file: $!") unless $! == &EISDIR;
            next if rmdir("$instroot/$file");
            &error("$arg: cannot remove directory $file: $!") unless $! == &ENOTEMPTY;
        }
        &run_script("$scriptsdir/$package.postrm", 'post-removal script', 'remove');
        opendir(DSD,"$scriptsdir") ||
            &error("$arg: cannot read directory $scriptsdir: $!");
        for $_ (readdir(DSD)) {
            next unless m/\.[^.]$/;
            next if $& eq '.postrm' || $& eq '.list';
            # need postrm for --purge, and list has to go last in case it
            # goes wrong
            next unless $` eq $package;
            unlink("$scriptsdir/$_") ||
                &error("$arg: unable to delete control information $scriptsdir/$_: $!");
        }
        closedir(DSD);
        $st_p2s{$package}= 'config-files';
        $statusupdated{$package}= 1;
    }
    if ($purge) {
	print STDOUT "Purging configuration files for $package ...\n";
        push(@undo,
             '$newconff="";
             for $f (@configf) { $newconff.= "\n $f $hash{$f}"; }
             $st_pk2v{$package,"conffiles"}= $newconff; $all_k21{"conffiles"}= 1;');
        for $file (@configfr) {
            $drf= &conffderef($file); if (!defined($drf)) { next; }
            unlink("$instroot/$drf") || $! == &ENOENT ||
                &error("$arg: cannot remove old config file $file (= $drf): $!");
            $hash{$file}= 'newconffile';
            unlink("$instroot/$file") || $! == &ENOENT ||
                &error("$arg: cannot remove old config file $file: $!")
                    if $file ne $drf;
            for $ext ('.dpkg-tmp', '.dpkg-old', '.dpkg-new', '~', '.bak', '%') {
                unlink("$instroot/$drf$ext") || $! == &ENOENT ||
                    &error("$arg: cannot remove old config file $drf$ext: $!");
            }
            unlink("#$instroot/$drf#") || $! == &ENOENT ||
                &error("$arg: cannot remove old auto-save file #$drf#: $!");
            $drf =~ m,^(.*)/, || next; $dir= $1; $base= $';
            if (opendir(CFD,"$instroot/$dir")) {
                for $_ (readdir(CFD)) {
                    next unless m/\.~\d+~$/;
                    next unless $` eq $base;
                    unlink("$instroot/$dir/$_") || $! == &ENOENT ||
                        &error("$arg: cannot remove old emacs backup file $dir/$_: $!");
                }
                closedir(CFD);
                if (grep($_ eq $dir, @ilist)) {
                    rmdir("$instroot/$dir") || $! == &ENOTEMPTY ||
                        &error("$arg: cannot remove config file directory $dir: $!");
                }
            } elsif ($! != &ENOENT) {
                &error("$arg: cannot read config file dir $dir: $!");
            }
        }
	&run_script("$scriptsdir/$package.postrm", 'post-removal script for purge',
                    'purge');
        unlink("$scriptsdir/$package.postrm") || $! == &ENOENT ||
            &error("$arg: cannot remove old postrm script: $!");
        &setnotinstalled;
        @undo= ();
    } elsif (!@configf && !stat("$scripts/$package.postrm")) {
        # If there are no config files and no postrm script then we
        # go straight into `purge'.  However, perhaps the stat didn't
        # fail with ENOENT ...
        $! == &ENOENT || &error("$package: stat failed on postrm script: $!");
        $st_p2w{$package}= 'purge';
        &setnotinstalled;
    }
    $st_p2h{$package}= 'ok'; $statusupdated{$package}= 1;
}

sub setnotinstalled {             
    unlink("$listsdir/$package.list") ||
        &error("$arg: unable to delete old file list: $!");
    $st_p2s{$package}= 'not-installed';
    for $k (keys %all_k21) { delete $st_pk2v{$package,$k}; }
}

#*** dependency processing - common to --configure and --remove ***#

# The algorithm for deciding what to configure or remove first is as
# follows:
#
# Loop through all packages doing a `try 1' until we've been round and
# nothing has been done, then do `try 2' and `try 3' likewise.
#
# When configuring, in each try we check to see whether all
# dependencies of this package are done.  If so we do it.  If some of
# the dependencies aren't done yet but will be later we defer the
# package, otherwise it is an error.
#
# When removing, in each try we check to see whether there are any
# packages that would have dependencies missing if we removed this
# one.  If not we remove it now.  If some of these packages are
# themselves scheduled for removal we defer the package until they
# have been done.
#
# The criteria for satisfying a dependency vary with the various
# tries.  In try 1 we treat the dependencies as absolute.  In try 2 we
# check break any cycles in the dependency graph involving the package
# we are trying to process before trying to process the package
# normally.  In try 3 (which should only be reached if
# --force-depends-version is set) we ignore version number clauses in
# Depends lines.  In try 4 (only reached if --force-depends is set) we
# say "ok" regardless.
#
# If we are configuring and one of the packages we depend on is
# awaiting configuration but wasn't specified in the argument list we
# will add it to the argument list if --configure-any is specified.
# In this case we note this as having "done something" so that we
# don't needlessly escalate to higher levels of dependency checking
# and breaking.

sub dependencies_ok {
    local ($dp, $removingp) = @_;
    local ($tpo, $however_t, $ok, $found, @aemsgs, @oemsgs);
    local ($tp, $rightver, $inst, $want, $thisf, $matched, $tpp);
    $ok= 2; # 2=ok, 1=defer, 0=halt
    &debug("checking dependencies of $dp (- $removingp)");
    for $tpo (split(/,/, $st_pk2v{$dp,'depends'})) {
	$tpo =~ s/^\s*//; $tpo =~ s/\s+$//;
	&debug("  checking group $dp -> $tpo");
        $matched= 0; @oemsgs=();
        $found=0; # 0=none, 1=defer, 2=withwarning, 3=ok
        for $tp (split(/\|/, $tpo)) {
	    $tp =~ s/^\s*//; $tp =~ s/\s+$//;
	    &debug("  checking possibility $dp -> $tp");
            if ($ignore_depends{$tp}) { &debug("ignoring so ok"); $found=3; last; }
            if (defined($cyclebreak{$dp,$tp})) { &debug("break cycle"); $found=3; last; }
            if ($tp eq $removingp) {
                ($tps, $rightver, $inst, $want, $tpp)= ('removing-now', 1, '','', $tp);
                $matched= 1;
            } else {
                ($tps, $rightver, $inst, $want, $tpp)= &installationstatus($tp);
                &debug("installationstatus($tp) -> !$tps!$rightver!$inst!$want!$tps|");
            }
            if (($tps eq 'installed' || $tps eq 'unpacked' || $tps eq 'postinst-failed')
                && !$rightver) {
                push(@oemsgs,"version of $tpp on system is $inst (wanted $want)");
                if ($force{'depends'}) { $thisf= $dependtry >= 3 ? 2 : 1; }
            } elsif ($tps eq 'unpacked' || $tps eq 'postinst-failed') {
                if (grep($_ eq $tpp, @deferred)) {
                    $thisf=1;
                } elsif (!length($removingp) && $force{'configure-any'}) {
                    &warn("will also configure $tpp");
                    push(@deferred,$tpp); $sincenothing=0; $thisf=1;
                } else {
                    push(@oemsgs,"package $tpp is not configured yet");
                    if ($force{'depends'}) { $thisf= $dependtry >= 4 ? 2 : 1; }
                }
            } elsif ($tps eq 'installed') {
                $found=3; last;
            } elsif ($tps eq 'removing-now') {
                push(@oemsgs,"$tpp is to be removed");
                if ($force{'depends'}) { $thisf= $dependtry >= 4 ? 2 : 1; }
            } else {
                push(@oemsgs,"$tpp ($want) is not installed");
                if ($force{'depends'}) { $thisf= $dependtry >= 4 ? 2 : 1; }
            }
	    &debug(" found $found");
            $found=$thisf if $thisf>$found;
        }
	&debug(" found $found matched $matched");
        next if length($removingp) && !$matched;
        if (length($removingp) && $tpo !~ m/\|/) {
            $however_t= '';
        } elsif (@oemsgs > 1) {
            $however_t= "\n  However, ". join(",\n   ", @oemsgs[0..($#oemsgs-1)]).
                      " and\n   ". $oemsgs[$#oemsgs]. ".";
        } else {
            $however_t= "\n  However, @oemsgs.";
        }
        if ($found == 0) {
            push(@aemsgs, "$dp depends on $tpo.$however_t");
            $ok=0;
        } elsif ($found == 1) {
            $ok=1 if $ok>1;
        } elsif ($found == 2) {
            push(@aemsgs, "$dp depends on $tpo.$however_t");
        } elsif ($found != 3) {
            &internalerr("found value in deferred_configure $found not known");
        }
    }
    &debug("ok $ok msgs >>@aemsgs<<");
    return ($ok, @aemsgs);
}

sub findbreakcycle {
    # Cycle breaking works recursively down the package dependency
    # tree.  @sofar is the list of packages we've descended down
    # already - if we encounter any of its packages again in a
    # dependency we have found a cycle.
    #
    # Cycles are preferentially broken by ignoring a dependency from
    # a package which doesn't have a postinst script.  If there isn't
    # such a dependency in the cycle we break at the `start' of the
    # cycle from the point of view of our package.
    #
    local ($package,@sofar) = @_;
    local ($tp,$tpp,$tps,$rightver,$inst,$want,$i,$dr,$de,@sf);
    &debug("findbreakcycle($package; @sofar)");
    push(@sofar,$package);
    for $tp (split(/[,|]/, $st_pk2v{$package,'depends'})) {
	$tp =~ s/^\s*//; $tp =~ s/\s+$//;
        ($tps, $rightver, $inst, $want, $tpp)= &installationstatus($tp);
        next unless $tps eq 'config-files' || $tps eq 'unpacked';
        next if $cyclebreak{$package,$tpp};
        if (grep($_ eq $tpp, @sofar)) {
            &debug("found cycle $package, $tpp (@sofar)");
            @sf= (@sofar,$tpp);
            for ($i=0;
                 $i<$#sf;
                 $i++) {
                next if stat("$scriptsdir/$sf[$i].postinst");
                last if $! == &ENOENT;
                &error("$arg: unable to stat $scriptsdir/$sf[$i].postinst: $!");
            }
            $i=0 if $i>=$#sf;
            ($dr,$de)= @sf[$i..$i+1];
	    if (!defined($cyclebreak{$dr,$de})) {
		$sincenothing=0; $cyclebreak{$dr,$de}= 1;
		&debug("broken cycle $i (@sf) at $dr -> $de");
                return 1;
	    }
        } else {
            return if &findbreakcycle($tpp,@sofar);
        }
    }
    return 0;
}

#*** useful subroutines for actions ***#

sub filesinpackage {
    # Returns the list in @ilist.
    # If error, calls &error("$epfx: ...");
    local ($epfx, $package) = @_;
    open(LIST,"$listsdir/$package.list") ||
        &error("$epfx: database broken for $package - ".
               "can't get installed files list: $!");
    @ilist= <LIST>;
    eof || &error("$epfx: cannot read $listsdir/$package.list: $!");
    close(LIST);
    @ilist= grep((chop,
                  s|/$||,
                  m|^/| || s|^|/|,
                  m/./),
                 @ilist);
}

sub installationstatus {
    local ($controlstring) = @_;
    local ($lversion,$lpackage,$lstatus,$lrevision,$cmp) = @_;
    local ($cc);
    $lversion= $controlstring;
    $lversion =~ s/^($packagere)\s*// ||
        &internalerr("needed installation status of bogus thing \`$lversion'");
    $lpackage= $1;
    $lstatus= defined($st_p2s{$lpackage}) ? $st_p2s{$lpackage} : 'not-installed';
    if ($lstatus ne 'not-installed') {
	if (length($lversion)) {
	    $lversion =~ s/^\s*\(\s*// && $lversion =~ s/\s*\)\s*$// ||
		&internalerr("failed to strip version \`$lversion'");
            if ($lversion =~ s/^[><=]//) { $cc= $&; } else { $cc= '='; }
	    $lrevision = ($lversion =~ s/-([^-]+)$//) ? $1 : '';
	    $wantedstring= "version $lversion";
            $wantedstring .= ", package revision $lrevision" if length($lrevision);
            $cmp= &compare_verrevs($st_pk2v{$lpackage,'version'},
                                   $st_pk2v{$lpackage,'package_revision'},
                                   $lversion,
                                   $lrevision);
            $installedstring= "version $st_pk2v{$lpackage,'version'}";
            $installedstring .=
                ", package revision $st_pk2v{$lpackage,'package_revision'}"
                    if length($st_pk2v{$lpackage,'package_revision'});
            if ($cc eq '>') {
                $rightver= $cmp>=0; $wantedstring.= ' or later';
            } elsif ($cc eq '<') {
                $rightver= $cmp<=0; $wantedstring.= ' or earlier';
            } else {
                s/^=//;
                $rightver= !$cmp; $wantedstring= "exactly $wantedstring";
            }
	} else {
	    $rightver= 1;
	    $wantedstring= "any version";
	    $installedstring= $st_pk2v{$lpackage,'version'}.'-'.
                              $st_pk2v{$lpackage,'package_revision'};
	}
    } else {
	$rightver= -1;
	$installedstring= "not installed";
    }
    return ($lstatus,$rightver,$installedstring,$wantedstring,$lpackage);
}

sub parse_control {
    # reads from fh CONTROL
    local ($fn) = @_;
    local ($cf,$ln,$l,$k,$v);
    defined($cf= &readall('CONTROL')) || &error("read control file $fn: $!");
    close(CONTROL);
    $p= &parse_control_entry;
    if (@cwarnings) {
        &warn("$fn: control file contains oddities: ".join("; ",@cwarnings))
            unless $controlwarn;
    }
    if (@cerrors) {
        &error("$fn: control file contains errors: ".join("; ",@cerrors));
    }
}

sub run_script_ne {
    local ($script,$describe,@args) = @_;
    local ($extranewlines) = $script =~ m/postinst/;
    &debug("running $describe = $script @args");
    if (!stat("$script")) {
        return if $! == &ENOENT;
        die "couldn't stat $script: $!\n";
    }
    if (! -x _) {
        chmod(0755, "$script") || die "couldn't make $script executable: $!\n";
    }
    print "\n" if $extranewlines;
    &debug("forking now");
    defined($rsc= fork) || die "couldn't fork for running $script: $!\n";
    if (!$rsc) {
        if ($instroot !~ m|^/*$| && !chroot($instroot)) {
            print STDERR "$name: failed to chroot to $instroot for $describe: $!\n";
            exit(1);
        }
        exec($script,@args);
        print STDERR "$name: failed to exec $script: $!\n";
        exit(1);
    }
    $!=0; waitpid($rsc,0) == $rsc || die "couldn't wait for $describe: $!\n";
    $? && die "$describe failed (".&ecode.")\n";
    &debug("script done");
    print "\n" if $extranewlines;
}

sub run_script {
    return if eval { &run_script_ne; 1; };
    $rse= $@; chop($rse); &error("$package: $rse");
}

sub hash {
    local ($file) = @_; # NB: filename must already have $instroot here
    local ($c);
    if (open(HF,"<$file")) {
        defined($c= open(MDP,"-|")) || &error("fork/pipe for hash: $!");
        if (!$c) {
            if (!open(STDIN,"<&HF")) {
                print STDERR "$name: unable to redirect stdin for hash: $!\n"; exit(1);
            }
            exec($md5sum); print STDERR "$name: unable to exec $md5sum: $!\n"; exit(1);
        }
        defined($hash= &readall('MDP')) || &error("unable to read from $md5sum: $!\n");
        $!=0; close(MDP); $? && &error("$md5sum returned error (".&ecode.")");
        $hash =~ s/\n+$//;
        $hash =~ m/^[0-9a-f]{32}$/i || &error("$md5sum returned bogus output \`$hash'");
        return $hash;
    } elsif ($! == &ENOENT) {
        return 'nonexistent';
    } else {
        &warn("$arg: unable to open conffile $file for hash: $!");
        return '-';
    }
}

sub files_not_identical {
    local ($file1,$file2) = @_; # NB: filenames must already have $instroot here
    if (stat($file1)) {
        if (stat($file2)) {
            system("cmp","-s",$file1,$file2);
            if (&WIFEXITED($?)) {
                $es= &WEXITSTATUS($?);
                return $es if $es == 0 || $es == 1;
            }
            &error("cmp $file1 $file2 returned error (".&ecode.")");
        } elsif ($! == &ENOENT) {
            return 1;
        } else {
            &error("failed to stat conffile $file2: $!");
        }
    } elsif ($! == &ENOENT) {
        if (stat($file2)) {
            return 1;
        } elsif ($! == &ENOENT) {
            return 0;
        } else {
            &error("failed to stat conffile $file2: $!");
        }
    } else {
        &error("failed to stat conffile $file1: $!");
    }
}

sub copyperm {
    local ($from,$to,$name) = @_;
    if (@statv= stat("$instroot/$from")) {
        chown($statv[4],$statv[5],"$instroot/$to") ||
            $!==&ENOENT ||
                &warn("$package: unable to preserve ownership of $name");
        chmod($statv[2],"$instroot/$to") ||
            $!==&ENOENT ||
                &warn("$package: unable to preserve permissions of $name");
    } elsif ($! != &ENOENT) {
        &warn("$package: unable to check permissions and ownership of".
              " $name in order to preserve them");
    }
}

sub conffderef {
    local ($file) = @_;
    local ($drf, $warning);
    $drf= $file; $warning='';
    for (;;) {
        if (!lstat("$instroot/$drf")) {
            last if $! == &ENOENT; $warning= "unable to lstat: $!"; last;
        } elsif (-f _) {
            last;
        } elsif (-l _) {
            if (!defined($lv= readlink("$instroot/$drf"))) {
                $warning= "unable to readlink: $!"; last;
            }
            if ($lv =~ m|^/|) {
                $drf= $lv;
            } else {
                $drf =~ s|/[^/]+$|/$lv|;
            }
        } else {
            $warning= "not a plain file or symlink"; last;
        }
    }
    &debug("conffile $file drf $drf warns \`$warning'");
    if ($warning) {
        &warn("$arg: possible problem with configuration file $file (= $drf):\n".
              " $warning");
        return undef;
    } else {
        return $drf;
    }
}
