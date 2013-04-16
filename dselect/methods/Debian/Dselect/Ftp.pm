# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Debian::Dselect::Ftp;

use Net::FTP;
use Exporter;
use Data::Dumper;

use strict;
use warnings;

use vars qw(@EXPORT %config $VAR1);

@EXPORT = qw(yesno do_connect do_mdtm add_site edit_site
             edit_config read_config store_config view_mirrors nb);

sub nb {
  my $nb = shift;
  if ($nb > 1024**2) {
    return sprintf("%.2fM", $nb / 1024**2);
  } elsif ($nb > 1024) {
    return sprintf("%.2fk", $nb / 1024);
  } else {
    return sprintf("%.2fb", $nb);
  }

}

sub read_config {
  my $vars = shift;
  my ($code, $conf);

  local($/);
  open(VARS, $vars) || die "Couldn't open $vars : $!\nTry to relaunch the 'Access' step in dselect, thanks.\n";
  $code = <VARS>;
  close VARS;

  $conf = eval $code;
  die "Couldn't eval $vars content : $@\n" if ($@);
  if (ref($conf) =~ /HASH/) {
    foreach (keys %{$conf}) {
      $config{$_} = $conf->{$_};
    }
  } else {
    print "Bad $vars file : removing it.\n";
    print "Please relaunch the 'Access' step in dselect. Thanks.\n";
    unlink $vars;
    exit 0;
  }
}

sub store_config {
  my $vars = shift;

  # Check that config is completed
  return if not $config{'done'};

  open(VARS, ">$vars") || die "Couldn't open $vars in write mode : $!\n";
  print VARS Dumper(\%config);
  close VARS;
}

sub view_mirrors {
  if (-f '/usr/lib/dpkg/methods/ftp/README.mirrors.txt') {
    system('pager', '/usr/lib/dpkg/methods/ftp/README.mirrors.txt');
  } elsif (-f '/usr/lib/dpkg/methods/ftp/README.mirrors.txt.gz') {
    system('gzip -dc /usr/lib/dpkg/methods/ftp/README.mirrors.txt.gz | pager');
  } else {
    print "/usr/lib/dpkg/methods/ftp/README.mirrors.txt(.gz): file not found.\n";
  }
}

sub edit_config {
  my $methdir = shift;
  my $i;

  #Get a config for ftp sites
  while(1) {
    $i = 1;
    print "\n\nList of selected ftp sites :\n";
    foreach (@{$config{'site'}}) {
      print "$i. ftp://$_->[0]$_->[1] @{$_->[2]}\n";
      $i++;
    }
    print "\nEnter a command (a=add e=edit d=delete q=quit m=mirror list) \n";
    print "eventually followed by a site number : ";
    chomp($_ = <STDIN>);
    /q/i && last;
    /a/i && add_site();
    /d\s*(\d+)/i &&
    do { splice(@{$config{'site'}}, $1-1, 1) if ($1 <= @{$config{'site'}});
         next;};
    /e\s*(\d+)/i &&
    do { edit_site($config{'site'}[$1-1]) if ($1 <= @{$config{'site'}});
         next; };
    m#m#i && view_mirrors();
  }

  print "\n";
  $config{'use_auth_proxy'} = yesno($config{'use_auth_proxy'} ? "y" : "n",
                                      "Go through an authenticated proxy");

  if ($config{'use_auth_proxy'}) {
    print "\nEnter proxy hostname [$config{'proxyhost'}] : ";
    chomp($_ = <STDIN>);
    $config{'proxyhost'} = $_ || $config{'proxyhost'};

    print "\nEnter proxy log name [$config{'proxylogname'}] : ";
    chomp($_ = <STDIN>);
    $config{'proxylogname'} = $_ || $config{'proxylogname'};

    print "\nEnter proxy password [$config{'proxypassword'}] : ";
    chomp ($_ = <STDIN>);
    $config{'proxypassword'} = $_ || $config{'proxypassword'};
  }

  print "\nEnter directory to download binary package files to\n";
  print "(relative to $methdir)\n";
  while(1) {
    print "[$config{'dldir'}] : ";
    chomp($_ = <STDIN>);
    s{/$}{};
    $config{'dldir'} = $_ if ($_);
    last if -d "$methdir/$config{'dldir'}";
    print "$methdir/$config{'dldir'} is not a directory !\n";
  }
}

sub add_site {
  my $pas = 1;
  my $user = "anonymous";
  my $email = `whoami`;
  chomp $email;
  $email .= '@' . `cat /etc/mailname || dnsdomainname`;
  chomp $email;
  my $dir = "/debian";

  push (@{$config{'site'}}, [ "", $dir, [ "dists/stable/main",
                                          "dists/stable/contrib",
					  "dists/stable/non-free" ],
                               $pas, $user, $email ]);
  edit_site($config{'site'}[@{$config{'site'}} - 1]);
}

sub edit_site {
  my $site = shift;

  local($_);

  print "\nEnter ftp site [$site->[0]] : ";
  chomp($_ = <STDIN>);
  $site->[0] = $_ || $site->[0];

  print "\nUse passive mode [" . ($site->[3] ? "y" : "n") ."] : ";
  chomp($_ = <STDIN>);
  $site->[3] = (/y/i ? 1 : 0) if ($_);

  print "\nEnter username [$site->[4]] : ";
  chomp($_ = <STDIN>);
  $site->[4] = $_ || $site->[4];

  print <<'EOF';

If you're using anonymous ftp to retrieve files, enter your email
address for use as a password. Otherwise enter your password,
or "?" if you want dselect-ftp to prompt you each time.

EOF

  print "Enter password [$site->[5]] : ";
  chomp($_ = <STDIN>);
  $site->[5] = $_ || $site->[5];

  print "\nEnter debian directory [$site->[1]] : ";
  chomp($_ = <STDIN>);
  $site->[1] = $_ || $site->[1];

  print "\nEnter space separated list of distributions to get\n";
  print "[@{$site->[2]}] : ";
  chomp($_ = <STDIN>);
  $site->[2] = [ split(/\s+/) ] if $_;
}

sub yesno($$) {
  my ($d, $msg) = @_;

  my ($res, $r);
  $r = -1;
  $r = 0 if $d eq "n";
  $r = 1 if $d eq "y";
  die "Incorrect usage of yesno, stopped" if $r == -1;
  while (1) {
    print $msg, " [$d]: ";
    $res = <STDIN>;
    $res =~ /^[Yy]/ and return 1;
    $res =~ /^[Nn]/ and return 0;
    $res =~ /^[ \t]*$/ and return $r;
    print "Please enter one of the letters 'y' or 'n'\n";
  }
}

##############################

sub do_connect {
    my($ftpsite,$username,$pass,$ftpdir,$passive,
       $useproxy,$proxyhost,$proxylogname,$proxypassword) = @_;

    my($rpass,$remotehost,$remoteuser,$ftp);

  TRY_CONNECT:
    while(1) {
	my $exit = 0;

	if ($useproxy) {
	    $remotehost = $proxyhost;
	    $remoteuser = $username . "@" . $ftpsite;
	} else {
	    $remotehost = $ftpsite;
	    $remoteuser = $username;
	}
	print "Connecting to $ftpsite...\n";
	$ftp = Net::FTP->new($remotehost, Passive => $passive);
	if(!$ftp || !$ftp->ok) {
	  print "Failed to connect\n";
	  $exit=1;
	}
	if (!$exit) {
#    $ftp->debug(1);
	    if ($useproxy) {
		print "Login on $proxyhost...\n";
		$ftp->_USER($proxylogname);
		$ftp->_PASS($proxypassword);
	    }
	    print "Login as $username...\n";
	    if ($pass eq "?") {
		    print "Enter password for ftp: ";
		    system("stty", "-echo");
		    $rpass = <STDIN>;
		    chomp $rpass;
		    print "\n";
		    system("stty", "echo");
	    } else {
		    $rpass = $pass;
	    }
	    if(!$ftp->login($remoteuser, $rpass))
	    { print $ftp->message() . "\n"; $exit=1; }
	}
	if (!$exit) {
	    print "Setting transfer mode to binary...\n";
	    if(!$ftp->binary()) { print $ftp->message . "\n"; $exit=1; }
	}
	if (!$exit) {
	    print "Cd to '$ftpdir'...\n";
	    if(!$ftp->cwd($ftpdir)) { print $ftp->message . "\n"; $exit=1; }
	}

	if ($exit) {
	    if (yesno ("y", "Retry connection at once")) {
		next TRY_CONNECT;
	    } else {
		die "error";
	    }
	}

	last TRY_CONNECT;
    }

#    if(!$ftp->pasv()) { print $ftp->message . "\n"; die "error"; }

    return $ftp;
}

##############################

# assume server supports MDTM - will be adjusted if needed
my $has_mdtm = 1;

my %months = ('Jan', 0,
	      'Feb', 1,
	      'Mar', 2,
	      'Apr', 3,
	      'May', 4,
	      'Jun', 5,
	      'Jul', 6,
	      'Aug', 7,
	      'Sep', 8,
	      'Oct', 9,
	      'Nov', 10,
	      'Dec', 11);

sub do_mdtm {
    my ($ftp, $file) = @_;
    my ($time);

    #if ($has_mdtm) {
	$time = $ftp->mdtm($file);
#	my $code=$ftp->code();	my $message=$ftp->message();
#	print " [ $code: $message ] ";
	if ($ftp->code() == 502		      # MDTM not implemented
	    || $ftp->code() == 500	      # command not understood (SUN firewall)
	    ) {
	    $has_mdtm = 0;
	} elsif (!$ftp->ok()) {
	    return;
	}
    #}

    if (! $has_mdtm) {
	use Time::Local;

	my @files = $ftp->dir($file);
	if (($#files == -1) || ($ftp->code == 550)) { # No such file or directory
	    return;
	}

#	my $code=$ftp->code();	my $message=$ftp->message();
#	print " [ $code: $message ] ";

#	print "[$#files]";

	# get the date components from the output of "ls -l"
	if ($files[0] =~
	    /([^ ]+ *){5}[^ ]+ ([A-Z][a-z]{2}) ([ 0-9][0-9]) ([0-9 ][0-9][:0-9][0-9]{2})/) {

            my($month_name, $day, $yearOrTime, $month, $hours, $minutes,
	       $year);

	    # what we can read
	    $month_name = $2;
	    $day = 0 + $3;
	    $yearOrTime = $4;

	    # translate the month name into number
	    $month = $months{$month_name};

	    # recognize time or year, and compute missing one
	    if ($yearOrTime =~ /([0-9]{2}):([0-9]{2})/) {
		$hours = 0 + $1; $minutes = 0 + $2;
		my @this_date = gmtime(time());
		my $this_month = $this_date[4];
		my $this_year = $this_date[5];
		if ($month > $this_month) {
		    $year = $this_year - 1;
		} else {
		    $year = $this_year;
		}
	    } elsif ($yearOrTime =~ / [0-9]{4}/) {
		$hours = 0; $minutes = 0;
		$year = $yearOrTime - 1900;
	    } else {
		die "Cannot parse year-or-time";
	    }

	    # build a system time
	    $time = timegm (0, $minutes, $hours, $day, $month, $year);
	} else {
	    die "Regexp match failed on LIST output";
	}
    }

    return $time;
}

1;

__END__
