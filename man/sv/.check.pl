#!/usr/bin/perl -w

# Source file directories
my %source = (
	'deb.5'					=> 'man/en',
	'deb-old.5'				=> 'man/en',
	'deb-control.5'			=> 'man/en',
	'dpkg.cfg.5'			=> 'man/en',
	'dselect.cfg.5'			=> 'man/en',
	'dpkg-query.8'			=> 'main',
	'dpkg.8'				=> 'main',
	'dpkg-split.8'			=> 'split',
	'md5sum.1'				=> 'utils',
	'start-stop-daemon.8'	=> 'utils',
	'dpkg-deb.1'			=> 'dpkg-deb',
	'822-date.1'			=> 'scripts',
	'dpkg-checkbuilddeps.1'	=> 'scripts',
	'dpkg-source.1'			=> 'scripts',
	'dpkg-statoverride.8'	=> 'scripts',
	'dpkg-divert.8'			=> 'scripts',
	'dpkg-architecture.1'	=> 'scripts',
	'dpkg-scanpackages.8'	=> 'scripts',
	'update-alternatives.8'	=> 'scripts',
	'install-info.8'		=> 'scripts',
	'dpkg-name.1'			=> 'scripts',
	'cleanup-info.8'		=> 'scripts',
	'dselect.8'				=> 'dselect',
);

# Read directory to find translated files
opendir CURDIR, '.' or die "Cannot read directory: $!\n";
FILE: foreach $file (readdir(CURDIR))
{
	next FILE unless $file =~ /\.[1-8]$/;

	# Locate revision number
	my $revision = undef;
	open DOC, "$file" or die "Cannot read file: $!\n";
	LINE: while (<DOC>)
	{
		if (/Translation of CVS revision ([0-9\.]*)$/)
		{
			$revision = $1;
			last LINE;
		}
	}
	close DOC;

	die "Unable to find translated revision in $file\n"
		unless defined $revision;

	# Check revision number against that in the CVS
	my $original = undef;
	open ENTRIES, "../../$source{$file}/CVS/Entries"
		or die "Cannot open ../../$source{$file}/CVS/Entries: $!\n";
	ENTRY: while (<ENTRIES>)
	{
		if (m"^/$file/([0-9\.]+)/")
		{
			$original = $1;
			last ENTRY;
		}
	}
	close ENTRIES;

	die "Unable to find original revision for $file\n"
		unless defined $original;

	# Check if version is up-to-date
	if ($revision eq $original)
	{
		print "$file is up to date\n";
	}
	else
	{
		print "$file translates $revision, current $source{$file}/$file is $original\n";
	}
}

closedir CURDIR;
