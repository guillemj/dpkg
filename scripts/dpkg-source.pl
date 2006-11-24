#! /usr/bin/perl

my $dpkglibdir = ".";
my $version = "1.3.0"; # This line modified by Makefile

my @filesinarchive;
my %dirincluded;
my %notfileobject;
my $fn;

$diff_ignore_default_regexp = '
# Ignore general backup files
(?:^|/).*~$|
# Ignore emacs recovery files
(?:^|/)\.#.*$|
# Ignore vi swap files
(?:^|/)\..*\.swp$|
# Ignore baz-style junk files or directories
(?:^|/),,.*(?:$|/.*$)|
# File-names that should be ignored (never directories)
(?:^|/)(?:DEADJOE|\.cvsignore|\.arch-inventory|\.bzrignore)$|
# File or directory names that should be ignored
(?:^|/)(?:CVS|RCS|\.deps|\{arch\}|\.arch-ids|\.svn|_darcs|\.git|\.bzr(?:\.backup|tags)?)(?:$|/.*$)
';

# Take out comments and newlines
$diff_ignore_default_regexp =~ s/^#.*$//mg;
$diff_ignore_default_regexp =~ s/\n//sg;

$sourcestyle = 'X';
$min_dscformat = 1;
$max_dscformat = 2;
$def_dscformat = "1.0"; # default format for -b

use POSIX;
use Fcntl qw (:mode);
use File::Temp qw (tempfile);
use Cwd;

use strict 'refs';

push (@INC, $dpkglibdir);
require 'controllib.pl';

require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

# Make sure patch doesn't get any funny ideas
delete $ENV{'POSIXLY_CORRECT'};

my @exit_handlers = ();
sub exit_handler {
	&$_ foreach ( reverse @exit_handlers );
	exit(127);
}
$SIG{'INT'} = \&exit_handler;
$SIG{'HUP'} = \&exit_handler;
$SIG{'QUIT'} = \&exit_handler;

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson and Klee Dienes.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <command>

Commands:
  -x <filename>.dsc [<output-dir>]
                           extract source package.
  -b <dir> [<orig-dir>|<orig-targz>|\'\']
                           build source package.

Build options:
  -c<controlfile>          get control info from this file.
  -l<changelogfile>        get per-version info from this file.
  -F<changelogformat>      force change log format.
  -V<name>=<value>         set a substitution variable.
  -T<varlistfile>          read variables here, not debian/substvars.
  -D<field>=<value>        override or add a .dsc field and value.
  -U<field>                remove a field.
  -W                       turn certain errors into warnings.
  -E                       when -W is enabled, -E disables it.
  -q                       quiet operation, do not print warnings.
  -i[<regexp>]             filter out files to ignore diffs of
                             (defaults to: '%s').
  -I<filename>             filter out files when building tarballs.
  -sa                      auto select orig source (-sA is default).
  -sk                      use packed orig source (unpack & keep).
  -sp                      use packed orig source (unpack & remove).
  -su                      use unpacked orig source (pack & keep).
  -sr                      use unpacked orig source (pack & remove).
  -ss                      trust packed & unpacked orig src are same.
  -sn                      there is no diff, do main tarfile only.
  -sA,-sK,-sP,-sU,-sR      like -sa,-sk,-sp,-su,-sr but may overwrite.

Extract options:
  -sp (default)            leave orig source packed in current dir.
  -sn                      do not copy original source to current dir.
  -su                      unpack original source tree too.

General options:
  -h, --help               show this help message.
      --version            show the version.
"), $progname, $diff_ignore_default_regexp;
}

sub handleformat {
	my $fmt = shift;
	return unless $fmt =~ /^(\d+)/; # only check major version
	return $1 >= $min_dscformat && $1 <= $max_dscformat;
}


$i = 100;
grep ($fieldimps {$_} = $i--,
      qw (Format Source Version Binary Origin Maintainer Architecture
      Standards-Version Build-Depends Build-Depends-Indep Build-Conflicts
      Build-Conflicts-Indep));

while (@ARGV && $ARGV[0] =~ m/^-/) {
    $_=shift(@ARGV);
    if (m/^-b$/) {
        &setopmode('build');
    } elsif (m/^-x$/) {
        &setopmode('extract');
    } elsif (m/^-s([akpursnAKPUR])$/) {
	&warn( sprintf(_g("-s%s option overrides earlier -s%s option" ), $1, $sourcestyle))
	    if $sourcestyle ne 'X';
        $sourcestyle= $1;
    } elsif (m/^-c/) {
        $controlfile= $';
    } elsif (m/^-l/) {
        $changelogfile= $';
    } elsif (m/^-F([0-9a-z]+)$/) {
        $changelogformat=$1;
    } elsif (m/^-D([^\=:]+)[=:]/) {
        $override{$1}= "$'";
    } elsif (m/^-U([^\=:]+)$/) {
        $remove{$1}= 1;
    } elsif (m/^-i(.*)$/) {
        $diff_ignore_regexp = $1 ? $1 : $diff_ignore_default_regexp;
    } elsif (m/^-I(.+)$/) {
        push @tar_ignore, "--exclude=$1";
    } elsif (m/^-V(\w[-:0-9A-Za-z]*)[=:]/) {
        $substvar{$1}= "$'";
    } elsif (m/^-T/) {
        $varlistfile= "$'";
    } elsif (m/^-(h|-help)$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } elsif (m/^-W$/) {
        $warnable_error= 1;
    } elsif (m/^-E$/) {
        $warnable_error= 0;
    } elsif (m/^-q$/) {
        $quiet_warnings = 1;
    } elsif (m/^--$/) {
        last;
    } else {
        &usageerr(sprintf(_g("unknown option \`%s'"), $_));
    }
}

defined($opmode) || &usageerr(_g("need -x or -b"));

$SIG{'PIPE'} = 'DEFAULT';

if ($opmode eq 'build') {

    $sourcestyle =~ y/X/A/;
    $sourcestyle =~ m/[akpursnAKPUR]/ ||
        &usageerr(sprintf(_g("source handling style -s%s not allowed with -b"), $sourcestyle));

    @ARGV || &usageerr(_g("-b needs a directory"));
    @ARGV<=2 || &usageerr(_g("-b takes at most a directory and an orig source argument"));
    $dir= shift(@ARGV);
    $dir= "./$dir" unless $dir =~ m:^/:; $dir =~ s,/*$,,;
    stat($dir) || &error(sprintf(_g("cannot stat directory %s: %s"), $dir, $!));
    -d $dir || &error(sprintf(_g("directory argument %s is not a directory"), $dir));

    $changelogfile= "$dir/debian/changelog" unless defined($changelogfile);
    $controlfile= "$dir/debian/control" unless defined($controlfile);
    
    &parsechangelog;
    &parsecontrolfile;
    $f{"Format"}=$def_dscformat;
    &init_substvars;

    $archspecific=0;
    for $_ (keys %fi) {
        $v= $fi{$_};
        if (s/^C //) {
            if (m/^Source$/i) { &setsourcepackage; }
            elsif (m/^(Standards-Version|Origin|Maintainer)$/i) { $f{$_}= $v; }
	    elsif (m/^Uploaders$/i) { ($f{$_}= $v) =~ s/[\r\n]//g; }
	    elsif (m/^Build-(Depends|Conflicts)(-Indep)?$/i) {
		my $dep = parsedep(substvars($v),1);
		&error(sprintf(_g("error occurred while parsing %s"), $_)) unless defined $dep;
		$f{$_}= showdep($dep, 1);
	    }
            elsif (s/^X[BC]*S[BC]*-//i) { $f{$_}= $v; }
            elsif (m/^(Section|Priority|Files|Bugs)$/i || m/^X[BC]+-/i) { }
            else { &unknown(_g('general section of control info file')); }
        } elsif (s/^C(\d+) //) {
            $i=$1; $p=$fi{"C$i Package"};
            push(@binarypackages,$p) unless $packageadded{$p}++;
            if (m/^Architecture$/) {
                if (debian_arch_eq($v, 'any')) {
                    @sourcearch= ('any');
                } elsif (debian_arch_eq($v, 'all')) {
                    if (!@sourcearch || $sourcearch[0] eq 'all') {
                        @sourcearch= ('all');
                    } else {
                        @sourcearch= ('any');
                    }
                } else {
		    if (grep($sourcearch[0] eq $_, 'any','all'))  {
			@sourcearch= ('any');
		    } else {
			for $a (split(/\s+/, $v)) {
			    &error(sprintf(_g("`%s' is not a legal architecture string"), $a))
				unless $a =~ /^[\w-]+$/;
                            &error(sprintf(_g("architecture %s only allowed on its own".
                                   " (list for package %s is `%s')"), $a, $p, $a))
                                   if grep($a eq $_, 'any','all');
                            push(@sourcearch,$a) unless $archadded{$a}++;
                        }
                }
                }
                $f{'Architecture'}= join(' ',@sourcearch);
            } elsif (s/^X[BC]*S[BC]*-//i) {
                $f{$_}= $v;
            } elsif (m/^(Package|Essential|Pre-Depends|Depends|Provides)$/i ||
                     m/^(Recommends|Suggests|Optional|Conflicts|Replaces)$/i ||
                     m/^(Enhances|Description|Section|Priority)$/i ||
                     m/^X[BC]+-/i) {
            } else {
                &unknown(_g("package's section of control info file"));
            }
        } elsif (s/^L //) {
            if (m/^Source$/) {
                &setsourcepackage;
            } elsif (m/^Version$/) {
		checkversion( $v );
                $f{$_}= $v;
            } elsif (s/^X[BS]*C[BS]*-//i) {
                $f{$_}= $v;
            } elsif (m/^(Maintainer|Changes|Urgency|Distribution|Date|Closes)$/i ||
                     m/^X[BS]+-/i) {
            } else {
                &unknown(_g("parsed version of changelog"));
            }
        } elsif (m/^o:.*/) {
        } else {
            &internerr(sprintf(_g("value from nowhere, with key >%s< and value >%s<"), $_, $v));
        }
    }

    $f{'Binary'}= join(', ',@binarypackages);
    for $f (keys %override) { $f{&capit($f)}= $override{$f}; }

    for $f (qw(Version)) {
        defined($f{$f}) || &error(sprintf(_g("missing information for critical output field %s"), $f));
    }
    for $f (qw(Maintainer Architecture Standards-Version)) {
        defined($f{$f}) || &warn(sprintf(_g("missing information for output field %s"), $f));
    }
    defined($sourcepackage) || &error(_g("unable to determine source package name !"));
    $f{'Source'}= $sourcepackage;
    for $f (keys %remove) { delete $f{&capit($f)}; }

    $version= $f{'Version'};
    $version =~ s/^\d+://; $upstreamversion= $version; $upstreamversion =~ s/-[^-]*$//;
    $basenamerev= $sourcepackage.'_'.$version;
    $basename= $sourcepackage.'_'.$upstreamversion;
    $basedirname= $basename;
    $basedirname =~ s/_/-/;

    $origdir= "$dir.orig";
    $origtargz= "$basename.orig.tar.gz";
    if (@ARGV) {
        $origarg= shift(@ARGV);
        if (length($origarg)) {
            stat($origarg) || &error(sprintf(_g("cannot stat orig argument %s: %s"), $origarg, $!));
            if (-d _) {
                $origdir= $origarg;
                $origdir= "./$origdir" unless $origdir =~ m,^/,; $origdir =~ s,/*$,,;
                $sourcestyle =~ y/aA/rR/;
                $sourcestyle =~ m/[ursURS]/ ||
                    &error(sprintf(_g("orig argument is unpacked but source handling style".
                           " -s%s calls for packed (.orig.tar.gz)"), $sourcestyle));
            } elsif (-f _) {
                $origtargz= $origarg;
                $sourcestyle =~ y/aA/pP/;
                $sourcestyle =~ m/[kpsKPS]/ ||
                    &error(sprintf(_g("orig argument is packed but source handling style".
                           " -s%s calls for unpacked (.orig/)"), $sourcestyle));
            } else {
                &error("orig argument $origarg is not a plain file or directory");
            }
        } else {
            $sourcestyle =~ y/aA/nn/;
            $sourcestyle =~ m/n/ ||
                &error(sprintf(_g("orig argument is empty (means no orig, no diff)".
                       " but source handling style -s%s wants something"), $sourcestyle));
        }
    }

    if ($sourcestyle =~ m/[aA]/) {
        if (stat("$origtargz")) {
            -f _ || &error(sprintf(_g("packed orig `%s' exists but is not a plain file"), $origtargz));
            $sourcestyle =~ y/aA/pP/;
        } elsif ($! != ENOENT) {
            &syserr(sprintf(_g("unable to stat putative packed orig `%s'"), $origtargz));
        } elsif (stat("$origdir")) {
            -d _ || &error(sprintf(_g("unpacked orig `%s' exists but is not a directory"), $origdir));
            $sourcestyle =~ y/aA/rR/;
        } elsif ($! != ENOENT) {
            &syserr(sprintf(_g("unable to stat putative unpacked orig `%s'"), $origdir));
        } else {
            $sourcestyle =~ y/aA/nn/;
        }
    }
    $dirbase= $dir; $dirbase =~ s,/?$,,; $dirbase =~ s,[^/]+$,,; $dirname= $&;
    $dirname eq $basedirname || &warn(sprintf(_g("source directory `%s' is not <sourcepackage>".
                                      "-<upstreamversion> `%s'"), $dir, $basedirname));
    
    if ($sourcestyle ne 'n') {
        $origdirbase= $origdir; $origdirbase =~ s,/?$,,;
        $origdirbase =~ s,[^/]+$,,; $origdirname= $&;

        $origdirname eq "$basedirname.orig" ||
            &warn(sprintf(_g(".orig directory name %s is not <package>".
                             "-<upstreamversion> (wanted %s)"),
                          $origdirname, "$basedirname.orig"));
        $tardirbase= $origdirbase; $tardirname= $origdirname;

        $tarname= $origtargz;
        $tarname eq "$basename.orig.tar.gz" ||
            &warn(sprintf(_g(".orig.tar.gz name %s is not <package>_<upstreamversion>".
                  ".orig.tar.gz (wanted %s)"), $tarname, "$basename.orig.tar.gz"));
    } else {
        $tardirbase= $dirbase; $tardirname= $dirname;
        $tarname= "$basenamerev.tar.gz";
    }

    if ($sourcestyle =~ m/[nurUR]/) {

        if (stat($tarname)) {
            $sourcestyle =~ m/[nUR]/ ||
                &error(sprintf(_g("tarfile `%s' already exists, not overwriting,".
                       " giving up; use -sU or -sR to override"), $tarname));
        } elsif ($! != ENOENT) {
            &syserr(sprintf(_g("unable to check for existence of `%s'"), $tarname));
        }

        printf(_g("%s: building %s in %s")."\n",
               $progname, $sourcepackage, $tarname)
            || &syserr(_g("write building tar message"));
	my ($ntfh, $newtar) = tempfile( "$tarname.new.XXXXXX",
					DIR => &getcwd, UNLINK => 0 );
        &forkgzipwrite($newtar);
        defined($c2= fork) || &syserr(_g("fork for tar"));
        if (!$c2) {
            chdir($tardirbase) || &syserr(sprintf(_g("chdir to above (orig) source %s"), $tardirbase));
            open(STDOUT,">&GZIP") || &syserr(_g("reopen gzip for tar"));
            # FIXME: put `--' argument back when tar is fixed
            exec('tar',@tar_ignore,'-cf','-',$tardirname) or &syserr(_g("exec tar"));
        }
        close(GZIP);
        &reapgzip;
        $c2 == waitpid($c2,0) || &syserr(_g("wait for tar"));
        $? && !(WIFSIGNALED($c2) && WTERMSIG($c2) == SIGPIPE) && subprocerr("tar");
        rename($newtar,$tarname) ||
            &syserr(sprintf(_g("unable to rename `%s' (newly created) to `%s'"), $newtar, $tarname));
	chmod(0666 &~ umask(), $tarname) ||
	    &syserr(sprintf(_g("unable to change permission of `%s'"), $tarname));

    } else {
        
        printf(_g("%s: building %s using existing %s")."\n",
               $progname, $sourcepackage, $tarname)
            || &syserr(_g("write using existing tar message"));
        
    }
    
    addfile("$tarname");

    if ($sourcestyle =~ m/[kpKP]/) {

        if (stat($origdir)) {
            $sourcestyle =~ m/[KP]/ ||
                &error(sprintf(_g("orig dir `%s' already exists, not overwriting,".
                       " giving up; use -sA, -sK or -sP to override"), $origdir));
	    push @exit_handlers, sub { erasedir($origdir) };
            erasedir($origdir);
	    pop @exit_handlers;
        } elsif ($! != ENOENT) {
            &syserr(sprintf(_g("unable to check for existence of orig dir `%s'"), $origdir));
        }

        $expectprefix= $origdir; $expectprefix =~ s,^\./,,;
	$expectprefix_dirname = $origdirname;
# tar checking is disabled, there are too many broken tar archives out there
# which we can still handle anyway.
#        checktarsane($origtargz,$expectprefix);
        mkdir("$origtargz.tmp-nest",0755) ||
            &syserr(sprintf(_g("unable to create `%s'"), "$origtargz.tmp-nest"));
	push @exit_handlers, sub { erasedir("$origtargz.tmp-nest") };
        extracttar($origtargz,"$origtargz.tmp-nest",$expectprefix_dirname);
        rename("$origtargz.tmp-nest/$expectprefix_dirname",$expectprefix) ||
            &syserr(sprintf(_g("unable to rename `%s' to `%s'"),
                            "$origtargz.tmp-nest/$expectprefix_dirname",
                            $expectprefix));
        rmdir("$origtargz.tmp-nest") ||
            &syserr(sprintf(_g("unable to remove `%s'"), "$origtargz.tmp-nest"));
	    pop @exit_handlers;
    }
        
    if ($sourcestyle =~ m/[kpursKPUR]/) {
        
        printf(_g("%s: building %s in %s")."\n",
               $progname, $sourcepackage, "$basenamerev.diff.gz")
            || &syserr(_g("write building diff message"));
	my ($ndfh, $newdiffgz) = tempfile( "$basenamerev.diff.gz.new.XXXXXX",
					DIR => &getcwd, UNLINK => 0 );
        &forkgzipwrite($newdiffgz);

        defined($c2= open(FIND,"-|")) || &syserr(_g("fork for find"));
        if (!$c2) {
            chdir($dir) || &syserr(sprintf(_g("chdir to %s for find"), $dir));
            exec('find','.','-print0') or &syserr(_g("exec find"));
        }
        $/= "\0";

      file:
        while (defined($fn= <FIND>)) {
            $fn =~ s/\0$//;
            next file if $fn =~ m/$diff_ignore_regexp/o;
            $fn =~ s,^\./,,;
            lstat("$dir/$fn") || &syserr(sprintf(_g("cannot stat file %s"), "$dir/$fn"));
	    my $mode = S_IMODE((lstat(_))[2]);
            if (-l _) {
                $type{$fn}= 'symlink';
                &checktype('-l') || next;
                defined($n= readlink("$dir/$fn")) ||
                    &syserr(sprintf(_g("cannot read link %s"), "$dir/$fn"));
                defined($n2= readlink("$origdir/$fn")) ||
                    &syserr(sprintf(_g("cannot read orig link %s"), "$origdir/$fn"));
                $n eq $n2 || &unrepdiff2(sprintf(_g("symlink to %s"), $n2),
                                         sprintf(_g("symlink to %s"), $n));
            } elsif (-f _) {
                $type{$fn}= 'plain file';
                if (!lstat("$origdir/$fn")) {
                    $! == ENOENT || &syserr(sprintf(_g("cannot stat orig file %s"), "$origdir/$fn"));
                    $ofnread= '/dev/null';
		    if( $mode & ( S_IXUSR | S_IXGRP | S_IXOTH ) ) {
			&warn( sprintf( _g("executable mode %04o of `%s' will not be represented in diff"), $mode, $fn ) )
			    unless $fn eq 'debian/rules';
		    }
		    if( $mode & ( S_ISUID | S_ISGID | S_ISVTX ) ) {
			&warn( sprintf( _g("special mode %04o of `%s' will not be represented in diff"), $mode, $fn ) );
		    }
                } elsif (-f _) {
                    $ofnread= "$origdir/$fn";
                } else {
                    &unrepdiff2(_g("something else"),
                                _g("plain file"));
                    next;
                }
                defined($c3= open(DIFFGEN,"-|")) || &syserr(_g("fork for diff"));
                if (!$c3) {
		    $ENV{'LC_ALL'}= 'C';
		    $ENV{'LANG'}= 'C';
		    $ENV{'TZ'}= 'UTC0';
                    exec('diff','-u',
                         '-L',"$basedirname.orig/$fn",
                         '-L',"$basedirname/$fn",
                         '--',"$ofnread","$dir/$fn") or &syserr(_g("exec diff"));
                }
                $difflinefound= 0;
                $/= "\n";
                while (<DIFFGEN>) {
                    if (m/^binary/i) {
                        close(DIFFGEN); $/= "\0";
                        &unrepdiff(_g("binary file contents changed"));
                        next file;
                    } elsif (m/^[-+\@ ]/) {
                        $difflinefound=1;
                    } elsif (m/^\\ No newline at end of file$/) {
                        &warn(sprintf(_g("file %s has no final newline ".
                              "(either original or modified version)"), $fn));
                    } else {
                        s/\n$//;
                        &internerr(sprintf(_g("unknown line from diff -u on %s: `%s'"), $fn, $_));
                    }
                    print(GZIP $_) || &syserr(_g("failed to write to gzip"));
                }
                close(DIFFGEN); $/= "\0";
                if (WIFEXITED($?) && (($es=WEXITSTATUS($?))==0 || $es==1)) {
                    if ($es==1 && !$difflinefound) {
                        &unrepdiff(_g("diff gave 1 but no diff lines found"));
                    }
                } else {
                    subprocerr(sprintf(_g("diff on %s"), "$dir/$fn"));
                }
            } elsif (-p _) {
                $type{$fn}= 'pipe';
                &checktype('-p');
            } elsif (-b _ || -c _ || -S _) {
                &unrepdiff(_g("device or socket is not allowed"));
            } elsif (-d _) {
                $type{$fn}= 'directory';
		if (!lstat("$origdir/$fn")) {
		    $! == ENOENT
			|| &syserr(sprintf(_g("cannot stat orig file %s"), "$origdir/$fn"));
		} elsif (! -d _) {
		    &unrepdiff2(_g('not a directory'),
		                _g('directory'));
		}
            } else {
                &unrepdiff(sprintf(_g("unknown file type (%s)"), $!));
            }
        }
        close(FIND); $? && subprocerr("find on $dir");
        close(GZIP) || &syserr(_g("finish write to gzip pipe"));
        &reapgzip;
        rename($newdiffgz,"$basenamerev.diff.gz") ||
            &syserr(sprintf(_g("unable to rename `%s' (newly created) to `%s'"), $newdiffgz, "$basenamerev.diff.gz"));
	chmod(0666 &~ umask(), "$basenamerev.diff.gz") ||
	    &syserr(sprintf(_g("unable to change permission of `%s'"), "$basenamerev.diff.gz"));

        defined($c2= open(FIND,"-|")) || &syserr(_g("fork for 2nd find"));
        if (!$c2) {
            chdir($origdir) || &syserr(sprintf(_g("chdir to %s for 2nd find"), $origdir));
            exec('find','.','-print0') or &syserr(_g("exec 2nd find"));
        }
        $/= "\0";
        while (defined($fn= <FIND>)) {
            $fn =~ s/\0$//;
            next if $fn =~ m/$diff_ignore_regexp/o;
            $fn =~ s,^\./,,;
            next if defined($type{$fn});
            lstat("$origdir/$fn") || &syserr(sprintf(_g("cannot check orig file %s"), "$origdir/$fn"));
            if (-f _) {
                &warn(sprintf(_g("ignoring deletion of file %s"), $fn));
            } elsif (-d _) {
                &warn(sprintf(_g("ignoring deletion of directory %s"), $fn));
            } elsif (-l _) {
                &warn(sprintf(_g("ignoring deletion of symlink %s"), $fn));
            } else {
                &unrepdiff2(_g('not a file, directory or link'),
                            _g('nonexistent'));
            }
        }
        close(FIND); $? && subprocerr("find on $dirname");

        &addfile("$basenamerev.diff.gz");

    }

    if ($sourcestyle =~ m/[prPR]/) {
        erasedir($origdir);
    }

    printf(_g("%s: building %s in %s")."\n",
           $progname, $sourcepackage, "$basenamerev.dsc")
        || &syserr(_g("write building message"));
    open(STDOUT,"> $basenamerev.dsc") || &syserr(sprintf(_g("create %s"), "$basenamerev.dsc"));
    &outputclose(1);

    if ($ur) {
        printf(STDERR _g("%s: unrepresentable changes to source")."\n",
               $progname)
            || &syserr(sprintf(_g("write error msg: %s"), $!));
        exit(1);
    }
    exit(0);

} else { # -> opmode ne 'build'

    $sourcestyle =~ y/X/p/;
    $sourcestyle =~ m/[pun]/ ||
        &usageerr(sprintf(_g("source handling style -s%s not allowed with -x"), $sourcestyle));

    @ARGV>=1 || &usageerr(_g("-x needs at least one argument, the .dsc"));
    @ARGV<=2 || &usageerr(_g("-x takes no more than two arguments"));
    $dsc= shift(@ARGV);
    $dsc= "./$dsc" unless $dsc =~ m:^/:;
    ! -d $dsc
	|| &usageerr(_g("-x needs the .dsc file as first argument, not a directory"));
    $dscdir= $dsc; $dscdir= "./$dscdir" unless $dsc =~ m,^/|^\./,;
    $dscdir =~ s,/[^/]+$,,;
    if (@ARGV) {
	$newdirectory= shift(@ARGV);
	! -e $newdirectory || &error(sprintf(_g("unpack target exists: %s"), $newdirectory));
    }

    my $is_signed = 0;
    open(DSC,"< $dsc") || &error(sprintf(_g("cannot open .dsc file %s: %s"), $dsc, $!));
    while (<DSC>) {
	next if /^\s*$/o;
	$is_signed = 1 if /^-----BEGIN PGP SIGNED MESSAGE-----$/o;
	last;
    }
    close(DSC);

    if ($is_signed) {
	if (-x '/usr/bin/gpg') {
	    my $gpg_command = 'gpg -q --verify ';
	    if (-r '/usr/share/keyrings/debian-keyring.gpg') {
		$gpg_command = $gpg_command.'--keyring /usr/share/keyrings/debian-keyring.gpg ';
	    }
	    $gpg_command = $gpg_command.quotemeta($dsc).' 2>&1';

	    my @gpg_output = `$gpg_command`;
	    my $gpg_status = $? >> 8;
	    if ($gpg_status) {
		print STDERR join("",@gpg_output);
		&error(sprintf(_g("failed to verify signature on %s"), $dsc))
		    if ($gpg_status == 1);
	    }
	} else {
	    &warn(sprintf(_g("could not verify signature on %s since gpg isn't installed"), $dsc));
	}
    } else {
	&warn(sprintf(_g("extracting unsigned source package (%s)"), $dsc));
    }

    open(CDATA,"< $dsc") || &error(sprintf(_g("cannot open .dsc file %s: %s"), $dsc, $!));
    &parsecdata('S',-1,sprintf(_g("source control file %s"),$dsc));
    close(CDATA);

    for $f (qw(Source Version Files)) {
        defined($fi{"S $f"}) ||
            &error(sprintf(_g("missing critical source control field %s"), $f));
    }

    my $dscformat = $def_dscformat;
    if (defined $fi{'S Format'}) {
	if (not handleformat($fi{'S Format'})) {
	    &error(sprintf(_g("Unsupported format of .dsc file (%s)"), $fi{'S Format'}));
	}
        $dscformat=$fi{'S Format'};
    }

    $sourcepackage = $fi{'S Source'};
    checkpackagename( $sourcepackage );

    $version= $fi{'S Version'};
    checkversion( $version );
    $version =~ s/^\d+://;
    if ($version =~ m/-([^-]+)$/) {
        $baseversion= $`; $revision= $1;
    } else {
        $baseversion= $version; $revision= '';
    }

    $files = $fi{'S Files'};
    my @tarfiles;
    my $difffile;
    my $debianfile;
    my %seen;
    for $file (split(/\n /,$files)) {
        next if $file eq '';
        $file =~ m/^([0-9a-f]{32})[ \t]+(\d+)[ \t]+([0-9a-zA-Z][-+:.,=0-9a-zA-Z_~]+)$/
            || &error(sprintf(_g("Files field contains bad line `%s'"), $file));
        ($md5sum{$3},$size{$3},$file) = ($1,$2,$3);
	local $_ = $file;

	&error(sprintf(_g("Files field contains invalid filename `%s'"), $file))
	    unless s/^\Q$sourcepackage\E_\Q$baseversion\E(?=[.-])// and
		   s/\.(gz|bz2|lzma)$//;
	s/^-\Q$revision\E(?=\.)// if length $revision;

	&error(sprintf(_g("repeated file type - files `%s' and `%s'"), $seen{$_}, $file)) if $seen{$_};
	$seen{$_} = $file;

	checkstats($file);

	if (/^\.(?:orig(-\w+)?\.)?tar$/) {
	    if ($1) { push @tarfiles, $file; } # push orig-foo.tar.gz to the end
	    else    { unshift @tarfiles, $file; }
	} elsif (/^\.debian\.tar$/) {
	    $debianfile = $file;
	} elsif (/^\.diff$/) {
	    $difffile = $file;
	} else {
	    &error(sprintf(_g("unrecognised file type - `%s'"), $file));
	}
    }

    &error(_g("no tarfile in Files field")) unless @tarfiles;
    my $native = !($difffile || $debianfile);
    if ($native) {
	&warn(_g("multiple tarfiles in native package")) if @tarfiles > 1;
	&warn(_g("native package with .orig.tar"))
	    unless $seen{'.tar'} or $seen{"-$revision.tar"};
    } else {
	&warn(_g("no upstream tarfile in Files field")) unless $seen{'.orig.tar'};
	if ($dscformat =~ /^1\./) {
	    &warn(sprintf(_g("multiple upstream tarballs in %s format dsc"), $dscformat)) if @tarfiles > 1;
	    &warn(sprintf(_g("debian.tar in %s format dsc"), $dscformat)) if $debianfile;
	}
    }

    $newdirectory = $sourcepackage.'-'.$baseversion unless defined($newdirectory);
    $expectprefix = $newdirectory;
    $expectprefix .= '.orig' if $difffile || $debianfile;
    
    checkdiff("$dscdir/$difffile") if $difffile;
    printf(_g("%s: extracting %s in %s")."\n",
           $progname, $sourcepackage, $newdirectory)
        || &syserr(_g("write extracting message"));
    
    &erasedir($newdirectory);
    ! -e "$expectprefix"
	|| rename("$expectprefix","$newdirectory.tmp-keep")
	|| &syserr(sprintf(_g("unable to rename `%s' to `%s'"), $expectprefix, "$newdirectory.tmp-keep"));

    push @tarfiles, $debianfile if $debianfile;
    for my $tarfile (@tarfiles)
    {
	my $target;
	if ($tarfile =~ /\.orig-(\w+)\.tar/) {
	    my $sub = $1;
	    $sub =~ s/\d+$// if $sub =~ /\D/;
	    $target = "$expectprefix/$sub";
	} elsif ($tarfile =~ /\.debian.tar/) {
	    $target = "$expectprefix/debian";
	} else {
	    $target = $expectprefix;
	}

	my $tmp = "$target.tmp-nest";
	(my $t = $target) =~ s!.*/!!;

	mkdir($tmp,0700) || &syserr(sprintf(_g("unable to create `%s'"), $tmp));
	system "chmod", "g-s", $tmp;
	printf(_g("%s: unpacking %s")."\n", $progname, $tarfile);
	extracttar("$dscdir/$tarfile",$tmp,$t);
	system "chown", '-R', '-f', join(':',@fowner), "$tmp/$t";
	rename("$tmp/$t",$target)
	    || &syserr(sprintf(_g("unable to rename `%s' to `%s'"), "$tmp/$t", $target));
	rmdir($tmp)
	    || &syserr(sprintf(_g("unable to remove `%s'"), $tmp));

	# for the first tar file:
	if ($tarfile eq $tarfiles[0] and !$native)
	{
	    # -sp: copy the .orig.tar.gz if required
	    if ($sourcestyle =~ /p/) {
		stat("$dscdir/$tarfile") ||
		    &syserr(sprintf(_g("failed to stat `%s' to see if need to copy"), "$dscdir/$tarfile"));
		($dsctardev,$dsctarino) = stat _;
		if (!stat($tarfile)) {
		    $! == ENOENT || &syserr(sprintf(_g("failed to check destination `%s'".
					    " to see if need to copy"), $tarfile));
		} else {
		    ($dumptardev,$dumptarino) = stat _;
		}
		unless ($dumptardev == $dsctardev && $dumptarino == $dsctarino) {
		    system('cp','--',"$dscdir/$tarfile", $tarfile);
		    $? && subprocerr("cp $dscdir/$tarfile to $tarfile");
		}
	    }
	    # -su: keep .orig directory unpacked
	    elsif ($sourcestyle =~ /u/ and $expectprefix ne $newdirectory) {
		! -e "$newdirectory.tmp-keep"
		    || &error(_g("unable to keep orig directory (already exists)"));
		system('cp','-ar','--',$expectprefix,"$newdirectory.tmp-keep");
		$? && subprocerr("cp $expectprefix to $newdirectory.tmp-keep");
	    }
	}
    }

    my @patches;
    push @patches, "$dscdir/$difffile" if $difffile;

    if ($debianfile and -d (my $pd = "$expectprefix/debian/patches"))
    {
	my @p;

	opendir D, $pd;
	while (defined ($_ = readdir D))
	{
	    # patches match same rules as run-parts
	    next unless /^[\w-]+$/ and -f "$pd/$_";
	    my $p = $_;
	    checkdiff("$pd/$p");
	    push @p, $p;
	}

	closedir D;

	push @patches, map "$newdirectory/debian/patches/$_", sort @p;
    }

    for $dircreate (keys %dirtocreate) {
	$dircreatem= "";
	for $dircreatep (split("/",$dirc)) {
	    $dircreatem.= $dircreatep;
	    if (!lstat($dircreatem)) {
		$! == ENOENT || &syserr(sprintf(_g("cannot stat %s"), $dircreatem));
		mkdir($dircreatem,0777)
		    || &syserr(sprintf(_g("failed to create %s subdirectory"), $dircreatem));
	    }
	    else {
		-d _ || &error(sprintf(_g("diff patches file in directory `%s',"
			       ." but %s isn't a directory !"), $dircreate, $dircreatem));
	    }
	}
    }

    if ($newdirectory ne $expectprefix)
    {
	rename($expectprefix,$newdirectory) ||
	    &syserr(sprintf(_g("failed to rename newly-extracted %s to %s"), $expectprefix, $newdirectory));

	# rename the copied .orig directory
	! -e "$newdirectory.tmp-keep"
	    || rename("$newdirectory.tmp-keep",$expectprefix)
	    || &syserr(sprintf(_g("failed to rename saved %s to %s"), "$newdirectory.tmp-keep", $expectprefix));
    }

    for my $patch (@patches) {
	printf(_g("%s: applying %s")."\n", $progname, $patch);
	if ($patch =~ /\.(gz|bz2|lzma)$/) {
	    &forkgzipread($patch);
	    *DIFF = *GZIP;
	} else {
	    open DIFF, $patch or &error(sprintf(_g("can't open diff `%s'"), $patch));
	}

        defined($c2= fork) || &syserr(_g("fork for patch"));
        if (!$c2) {
            open(STDIN,"<&DIFF") || &syserr(_g("reopen gzip for patch"));
            chdir($newdirectory) || &syserr(sprintf(_g("chdir to %s for patch"), $newdirectory));
	    $ENV{'LC_ALL'}= 'C';
	    $ENV{'LANG'}= 'C';
            exec('patch','-s','-t','-F','0','-N','-p1','-u',
                 '-V','never','-g0','-b','-z','.dpkg-orig') or &syserr(_g("exec patch"));
        }
        close(DIFF);
        $c2 == waitpid($c2,0) || &syserr(_g("wait for patch"));
        $? && subprocerr("patch");

	&reapgzip if $patch =~ /\.(gz|bz2|lzma)$/;
    }

    my $now = time;
    for $fn (keys %filepatched) {
	$ftr= "$newdirectory/".substr($fn,length($expectprefix)+1);
	utime($now, $now, $ftr) || &syserr(sprintf(_g("cannot change timestamp for %s"), $ftr));
	$ftr.= ".dpkg-orig";
	unlink($ftr) || &syserr(sprintf(_g("remove patch backup file %s"), $ftr));
    }

    if (!(@s= lstat("$newdirectory/debian/rules"))) {
	$! == ENOENT || &syserr(sprintf(_g("cannot stat %s"), "$newdirectory/debian/rules"));
	&warn(sprintf(_g("%s does not exist"), "$newdirectory/debian/rules"));
    } elsif (-f _) {
	chmod($s[2] | 0111, "$newdirectory/debian/rules") ||
	    &syserr(sprintf(_g("cannot make %s executable"), "$newdirectory/debian/rules"));
    } else {
	&warn(sprintf(_g("%s is not a plain file"), "$newdirectory/debian/rules"));
    }

    $execmode= 0777 & ~umask;
    (@s= stat('.')) || &syserr(_g("cannot stat `.'"));
    $dirmode= $execmode | ($s[2] & 02000);
    $plainmode= $execmode & ~0111;
    $fifomode= ($plainmode & 0222) | (($plainmode & 0222) << 1);
    for $fn (@filesinarchive) {
	$fn=~ s,^$expectprefix,$newdirectory,;
        (@s= lstat($fn)) || &syserr(sprintf(_g("cannot stat extracted object `%s'"), $fn));
        $mode= $s[2];
        if (-d _) {
            $newmode= $dirmode;
        } elsif (-f _) {
            $newmode= ($mode & 0111) ? $execmode : $plainmode;
        } elsif (-p _) {
            $newmode= $fifomode;
        } elsif (!-l _) {
            &internerr(sprintf(_g("unknown object `%s' after extract (mode 0%o)"), $fn, $mode));
        } else { next; }
        next if ($mode & 07777) == $newmode;
        chmod($newmode,$fn) ||
            &syserr(sprintf(_g("cannot change mode of `%s' to 0%o from 0%o"),
                            $fn,$newmode,$mode));
    }
    exit(0);
}

sub checkstats {
    my ($f) = @_;
    my @s;
    my $m;
    open(STDIN,"< $dscdir/$f") || &syserr(sprintf(_g("cannot read %s"), "$dscdir/$f"));
    (@s= stat(STDIN)) || &syserr(sprintf(_g("cannot fstat %s"), "$dscdir/$f"));
    $s[7] == $size{$f} || &error(sprintf(_g("file %s has size %s instead of expected %s"), $f, $s[7], $size{$f}));
    $m= `md5sum`; $? && subprocerr("md5sum $f"); $m =~ s/\n$//;
    $m = readmd5sum( $m );
    $m eq $md5sum{$f} || &error(sprintf(_g("file %s has md5sum %s instead of expected %s"), $f, $m, $md5sum{$f}));
    open(STDIN,"</dev/null") || &syserr(_g("reopen stdin from /dev/null"));
}

sub erasedir {
    my ($dir) = @_;
    if (!lstat($dir)) {
        $! == ENOENT && return;
        &syserr(sprintf(_g("cannot stat directory %s (before removal)"), $dir));
    }
    system 'rm','-rf','--',$dir;
    $? && subprocerr("rm -rf $dir");
    if (!stat($dir)) {
        $! == ENOENT && return;
        &syserr(sprintf(_g("unable to check for removal of dir `%s'"), $dir));
    }
    &failure(sprintf(_g("rm -rf failed to remove `%s'"), $dir));
}

use strict 'vars';

sub checktarcpio {

    my ($tarfileread, $wpfx) = @_;
    my ($tarprefix, $c2);

    @filesinarchive = ();

    # make <CPIO> read from the uncompressed archive file
    &forkgzipread ("$tarfileread");
    if (! defined ($c2 = open (CPIO,"-|"))) { &syserr (_g("fork for cpio")); }
    if (!$c2) {
	$ENV{'LC_ALL'}= 'C';
	$ENV{'LANG'}= 'C';
        open (STDIN,"<&GZIP") || &syserr (_g("reopen gzip for cpio"));
        &cpiostderr;
        exec ('cpio','-0t') or &syserr (_g("exec cpio"));
    }
    close (GZIP);

    $/ = "\0";
    while (defined ($fn = <CPIO>)) {

        $fn =~ s/\0$//;

	# store printable name of file for error messages
	my $pname = $fn;
	$pname =~ y/ -~/?/c;

        if ($fn =~ m/\n/) {
	    &error (sprintf(_g("tarfile `%s' contains object with".
		    " newline in its name (%s)"), $tarfileread, $pname));
	}

	next if ($fn eq '././@LongLink');

	if (! $tarprefix) {
	    if ($fn =~ m/\n/) {
                &error(sprintf(_g("first output from cpio -0t (from `%s') ".
                       "contains newline - you probably have an out of ".
                       "date version of cpio.  GNU cpio 2.4.2-2 is known to work"), $tarfileread));
	    }
	    $tarprefix = ($fn =~ m,((\./)*[^/]*)[/],)[0];
	    # need to check for multiple dots on some operating systems
	    # empty tarprefix (due to regex failer) will match emptry string
	    if ($tarprefix =~ /^[.]*$/) {
		&error(sprintf(_g("tarfile `%s' does not extract into a ".
		           "directory off the current directory (%s from %s)"),
		               $tarfileread, $tarprefix, $pname));
	    }
	}

	my $fprefix = substr ($fn, 0, length ($tarprefix));
        my $slash = substr ($fn, length ($tarprefix), 1);
        if ((($slash ne '/') && ($slash ne '')) || ($fprefix ne $tarprefix)) {
	    &error (sprintf(_g("tarfile `%s' contains object (%s) ".
	                       "not in expected directory (%s)"),
	                    $tarfileread, $pname, $tarprefix));
	}

	# need to check for multiple dots on some operating systems
        if ($fn =~ m/[.]{2,}/) {
            &error (sprintf(_g("tarfile `%s' contains object with".
                               " /../ in its name (%s)"),
                            $tarfileread, $pname));
	}
        push (@filesinarchive, $fn);
    }
    close (CPIO);
    $? && subprocerr ("cpio");
    &reapgzip;
    $/= "\n";

    my $tarsubst = quotemeta ($tarprefix);

    return $tarprefix;
}

sub checktarsane {

    my ($tarfileread, $wpfx) = @_;
    my ($c2);

    %dirincluded = ();
    %notfileobject = ();

    my $tarprefix = &checktarcpio ($tarfileread, $wpfx);

    # make <TAR> read from the uncompressed archive file
    &forkgzipread ("$tarfileread");
    if (! defined ($c2 = open (TAR,"-|"))) { &syserr (_g("fork for tar -t")); }
    if (! $c2) {
	$ENV{'LC_ALL'}= 'C';
        $ENV{'LANG'}= 'C';
        open (STDIN, "<&GZIP") || &syserr (_g("reopen gzip for tar -t"));
        exec ('tar', '-vvtf', '-') or &syserr (_g("exec tar -vvtf -"));
    }
    close (GZIP);

    my $efix= 0;
    while (<TAR>) {

        chomp;

        if (! m,^(\S{10})\s,) {
            &error(sprintf(_g("tarfile `%s' contains unknown object ".
                              "listed by tar as `%s'"),
                           $tarfileread, $_));
	}
	my $mode = $1;

        $mode =~ s/^([-dpsl])// ||
            &error(sprintf(_g("tarfile `%s' contains object `%s' with ".
                              "unknown or forbidden type `%s'"),
                           $tarfileread, $fn, substr($_,0,1)));
        my $type = $&;

        if ($mode =~ /^l/) { $_ =~ s/ -> .*//; }
        s/ link to .+//;

	my @tarfields = split(' ', $_, 6);
	if (@tarfields < 6) { 
	    &error (sprintf(_g("tarfile `%s' contains incomplete entry `%s'"), $tarfileread, $_)."\n");
	}

	my $tarfn = deoctify ($tarfields[5]);

	# store printable name of file for error messages
	my $pname = $tarfn;
	$pname =~ y/ -~/?/c;

	# fetch name of file as given by cpio
        $fn = $filesinarchive[$efix++];

	my $l = length($fn);
	if (substr ($tarfn, 0, $l + 4) eq "$fn -> ") {
		# This is a symlink, as listed by tar.  cpio doesn't
		# give us the targets of the symlinks, so we ignore this.
		$tarfn = substr($tarfn, 0, $l);
	}
	if ($tarfn ne $fn) {
	    if ((length ($fn) == 99) && (length ($tarfn) >= 99)
		&& (substr ($fn, 0, 99) eq substr ($tarfn, 0, 99))) {
		# this file doesn't match because cpio truncated the name
		# to the first 100 characters.  let it slide for now.
		&warn (sprintf(_g("filename `%s' was truncated by cpio;" .
		                  " unable to check full pathname"), $pname));
		# Since it didn't match, later checks will not be able
		# to stat this file, so we replace it with the filename
		# fetched from tar.
		$filesinarchive[$efix-1] = $tarfn;
	    } else {
		&error (sprintf(_g("tarfile `%s' contains unexpected object".
			" listed by tar as `%s'; expected `%s'"), $tarfileread, $_, $pname));
	    }
	}

	# if cpio truncated the name above, 
	# we still can't allow files to expand into /../
	# need to check for multiple dots on some operating systems
        if ($tarfn =~ m/[.]{2,}/) {
            &error (sprintf(_g("tarfile `%s' contains object with".
                               "/../ in its name (%s)"), $tarfileread, $pname));
	}

        if ($tarfn =~ /\.dpkg-orig$/) {
            &error (sprintf(_g("tarfile `%s' contains file with name ending in .dpkg-orig"), $tarfileread));
	}

        if ($mode =~ /[sStT]/ && $type ne 'd') {
            &error (sprintf(_g("tarfile `%s' contains setuid, setgid".
		    " or sticky object `%s'"), $tarfileread, $pname));
	}

        if ($tarfn eq "$tarprefix/debian" && $type ne 'd') {
            &error (sprintf(_g("tarfile `%s' contains object `debian'".
                               " that isn't a directory"), $tarfileread));
	}

        if ($type eq 'd') { $tarfn =~ s,/$,,; }
        $tarfn =~ s,(\./)*,,;
        my $dirname = $tarfn;

        if (($dirname =~ s,/[^/]+$,,) && (! defined ($dirincluded{$dirname}))) {
            &warnerror (sprintf(_g("tarfile `%s' contains object `%s' but its containing ".
		    "directory `%s' does not precede it"), $tarfileread, $pname, $dirname));
	    $dirincluded{$dirname} = 1;
	}
	if ($type eq 'd') { $dirincluded{$tarfn} = 1; }
        if ($type ne '-') { $notfileobject{$tarfn} = 1; }
    }
    close (TAR);
    $? && subprocerr ("tar -vvtf");
    &reapgzip;

    my $tarsubst = quotemeta ($tarprefix);
    @filesinarchive = map { s/^$tarsubst/$wpfx/; $_ } @filesinarchive;
    %dirincluded = map { s/^$tarsubst/$wpfx/; $_=>1 } (keys %dirincluded);
    %notfileobject = map { s/^$tarsubst/$wpfx/; $_=>1 } (keys %notfileobject);
}

no strict 'vars';

# check diff for sanity, find directories to create as a side effect
sub checkdiff
{
    my $diff = shift;
    if ($diff =~ /\.(gz|bz2|lzma)$/) {
	&forkgzipread($diff);
	*DIFF = *GZIP;
    } else {
	open DIFF, $diff or &error(sprintf(_g("can't open diff `%s'"), $diff));
    }
    $/="\n";
    $_ = <DIFF>;

  HUNK:
    while (defined($_) || !eof(DIFF)) {
	# skip cruft leading up to patch (if any)
	until (/^--- /) {
	    last HUNK unless defined ($_ = <DIFF>);
	}
	# read file header (---/+++ pair)
	s/\n$// or &error(sprintf(_g("diff `%s' is missing trailing newline"), $diff));
	s/^--- // or &error(sprintf(_g("expected ^--- in line %d of diff `%s'"), $., $diff));
	s/\t.*//;
	$_ eq '/dev/null' or s!^(\./)?[^/]+/!$expectprefix/! or
	    &error(sprintf(_g("diff `%s' patches file with no subdirectory"), $diff));
	/\.dpkg-orig$/ and
	    &error(sprintf(_g("diff `%s' patches file with name ending .dpkg-orig"), $diff));
	$fn = $_;

	(defined($_= <DIFF>) and s/\n$//) or
	    &error(sprintf(_g("diff `%s' finishes in middle of ---/+++ (line %d)"), $diff, $.));

	s/\t.*//;
	(s/^\+\+\+ // and s!^(\./)?[^/]+/!!)
	    or &error(sprintf(_g("line after --- isn't as expected in diff `%s' (line %d)"), $diff, $.));

	if ($fn eq '/dev/null') {
	    $fn = "$expectprefix/$_";
	} else {
	    $_ eq substr($fn, length($expectprefix)+1)
		or &error(sprintf(_g("line after --- isn't as expected in diff `%s' (line %d)"), $diff, $.));
	}

	$dirname = $fn;
	if ($dirname =~ s,/[^/]+$,, && !defined($dirincluded{$dirname})) {
	    $dirtocreate{$dirname} = 1;
	}
	defined($notfileobject{$fn}) &&
	    &error(sprintf(_g("diff `%s' patches something which is not a plain file"), $diff));

	$filepatched{$fn} eq $diff && &error(sprintf(_g("diff patches file %s twice"), $fn));
	$filepatched{$fn} = $diff;

	# read hunks
	my $hunk = 0;
	while (defined($_ = <DIFF>) && !(/^--- / or /^Index:/)) {
	    # read hunk header (@@)
	    s/\n$// or &error(sprintf(_g("diff `%s' is missing trailing newline"), $diff));
	    next if /^\\ No newline/;
	    /^@@ -\d+(,(\d+))? \+\d+(,(\d+))? @\@( .*)?$/ or
		&error(sprintf(_g("Expected ^\@\@ in line %d of diff `%s'"), $., $diff));
	    my ($olines, $nlines) = ($1 ? $2 : 1, $3 ? $4 : 1);
	    ++$hunk;
	    # read hunk
	    while ($olines || $nlines) {
		defined($_ = <DIFF>) or &error(sprintf(_g("unexpected end of diff `%s'"), $diff));
		s/\n$// or &error(sprintf(_g("diff `%s' is missing trailing newline"), $diff));
		next if /^\\ No newline/;
		if (/^ /) { --$olines; --$nlines; }
		elsif (/^-/) { --$olines; }
		elsif (/^\+/) { --$nlines; }
		else { &error(sprintf(_g("expected [ +-] at start of line %d of diff `%s'"), $., $diff)); }
	    }
	}
	$hunk or &error(sprintf(_g("expected ^\@\@ at line %d of diff `%s'"), $., $diff));
    }
    close(DIFF);
    
    &reapgzip if $diff =~ /\.(gz|bz2|lzma)$/;
}

sub extracttar {
    my ($tarfileread,$dirchdir,$newtopdir) = @_;
    &forkgzipread("$tarfileread");
    defined($c2= fork) || &syserr(_g("fork for tar -xkf -"));
    if (!$c2) {
        open(STDIN,"<&GZIP") || &syserr(_g("reopen gzip for tar -xkf -"));
        &cpiostderr;
        chdir($dirchdir) || &syserr(sprintf(_g("cannot chdir to `%s' for tar extract"), $dirchdir));
        exec('tar','-xkf','-') or &syserr(_g("exec tar -xkf -"));
    }
    close(GZIP);
    $c2 == waitpid($c2,0) || &syserr(_g("wait for tar -xkf -"));
    $? && subprocerr("tar -xkf -");
    &reapgzip;

    opendir(D,"$dirchdir") || &syserr(sprintf(_g("Unable to open dir %s"), $dirchdir));
    @dirchdirfiles = grep($_ ne "." && $_ ne "..",readdir(D));
    closedir(D) || &syserr(sprintf(_g("Unable to close dir %s"), $dirchdir));
    if (@dirchdirfiles==1 && -d "$dirchdir/$dirchdirfiles[0]") {
	rename("$dirchdir/$dirchdirfiles[0]", "$dirchdir/$newtopdir") ||
	    &syserr(sprintf(_g("Unable to rename %s to %s"),
	                    "$dirchdir/$dirchdirfiles[0]",
	                    "$dirchdir/$newtopdir"));
    } else {
	mkdir("$dirchdir/$newtopdir.tmp", 0777) or
	    &syserr(sprintf(_g("Unable to mkdir %s"),
	                    "$dirchdir/$newtopdir.tmp"));
	for (@dirchdirfiles) {
	    rename("$dirchdir/$_", "$dirchdir/$newtopdir.tmp/$_") or
		&syserr(sprintf(_g("Unable to rename %s to %s"),
		                "$dirchdir/$_",
		                "$dirchdir/$newtopdir.tmp/$_"));
	}
	rename("$dirchdir/$newtopdir.tmp", "$dirchdir/$newtopdir") or
	    &syserr(sprintf(_g("Unable to rename %s to %s"),
	                    "$dirchdir/$newtopdir.tmp",
	                    "$dirchdir/$newtopdir"));
    }
}

sub cpiostderr {
    open(STDERR,"| grep -E -v '^[0-9]+ blocks\$' >&2") ||
        &syserr(_g("reopen stderr for tar to grep out blocks message"));
}

sub checktype {
    if (!lstat("$origdir/$fn")) {
        &unrepdiff2(_g("nonexistent"),$type{$fn});
    } else {
        $v= eval("$_[0] _ ? 2 : 1"); $v || &internerr(sprintf(_g("checktype %s (%s)"), "$@", $_[0]));
        return 1 if $v == 2;
        &unrepdiff2(_g("something else"),$type{$fn});
    }
    return 0;
}

sub setopmode {
    defined($opmode) && &usageerr(_g("only one of -x or -b allowed, and only once"));
    $opmode= $_[0];
}

sub unrepdiff {
    printf(STDERR _g("%s: cannot represent change to %s: %s")."\n",
                  $progname, $fn, $_[0])
        || &syserr(_g("write syserr unrep"));
    $ur++;
}

sub unrepdiff2 {
    printf(STDERR _g("%s: cannot represent change to %s:\n".
                     "%s:  new version is %s\n".
                     "%s:  old version is %s\n"),
                  $progname, $fn, $progname, $_[1], $progname, $_[0])
        || &syserr(_g("write syserr unrep"));
    $ur++;
}

sub forkgzipwrite {
    open(GZIPFILE,"> $_[0]") || &syserr(sprintf(_g("create file %s"), $_[0]));
    pipe(GZIPREAD,GZIP) || &syserr(_g("pipe for gzip"));
    defined($cgz= fork) || &syserr(_g("fork for gzip"));
    if (!$cgz) {
        open(STDIN,"<&GZIPREAD") || &syserr(_g("reopen gzip pipe")); close(GZIPREAD);
        close(GZIP); open(STDOUT,">&GZIPFILE") || &syserr(_g("reopen tar.gz"));
        exec('gzip','-9') or &syserr(_g("exec gzip"));
    }
    close(GZIPREAD);
    $gzipsigpipeok= 0;
}

sub forkgzipread {
    local $SIG{PIPE} = 'DEFAULT';
    my $prog;

    if ($_[0] =~ /\.gz$/) {
      $prog = 'gunzip';
    } elsif ($_[0] =~ /\.bz2$/) {
      $prog = 'bunzip2';
    } elsif ($_[0] =~ /\.lzma$/) {
      $prog = 'unlzma';
    } else {
      &error(sprintf(_g("unknown compression type on file %s"), $_[0]));
    }

    open(GZIPFILE,"< $_[0]") || &syserr(sprintf(_g("read file %s"), $_[0]));
    pipe(GZIP,GZIPWRITE) || &syserr(sprintf(_g("pipe for %s"), $prog));
    defined($cgz= fork) || &syserr(sprintf(_g("fork for %s"), $prog));
    if (!$cgz) {
        open(STDOUT,">&GZIPWRITE") || &syserr(sprintf(_g("reopen %s pipe"), $prog)); close(GZIPWRITE);
        close(GZIP); open(STDIN,"<&GZIPFILE") || &syserr(_g("reopen input file"));
        exec($prog) or &syserr(sprintf(_g("exec %s"), $prog));
    }
    close(GZIPWRITE);
    $gzipsigpipeok= 1;
}

sub reapgzip {
    $cgz == waitpid($cgz,0) || &syserr(_g("wait for gzip"));
    !$? || ($gzipsigpipeok && WIFSIGNALED($?) && WTERMSIG($?)==SIGPIPE) ||
        subprocerr("gzip");
    close(GZIPFILE);
}

my %added_files;
sub addfile {
    my ($filename)= @_;
    $added_files{$filename}++ &&
	&internerr( sprintf(_g("tried to add file `%s' twice"), $filename));
    stat($filename) || &syserr(sprintf(_g("could not stat output file `%s'"), $filename));
    $size= (stat _)[7];
    my $md5sum= `md5sum <$filename`;
    $? && &subprocerr("md5sum $filename");
    $md5sum = readmd5sum( $md5sum );
    $f{'Files'}.= "\n $md5sum $size $filename";
}

# replace \ddd with their corresponding character, refuse \ddd > \377
# modifies $_ (hs)
{
    my $backslash;
sub deoctify {
    my $fn= $_[0];
    $backslash= sprintf("\\%03o", unpack("C", "\\")) if !$backslash;

    s/\\{2}/$backslash/g;
    @_= split(/\\/, $fn);

    foreach (@_) {
        /^(\d{3})/ or next;
        &failure(sprintf(_g("bogus character `\\%s' in `%s'"), $1, $fn)."\n") if oct($1) > 255;
        $_= pack("c", oct($1)) . $';
    }
    return join("", @_);
} }

