#!/usr/bin/perl
open(FILES, "find -mindepth 1|");
sub myprint {
	print "@_\n";
}
while (<FILES>) {
	chomp;
	$file = $_;
	if( ! -l $file ) {
		print "$file\n" if(!$targets{$file});
	}
	$newfile = $file;
	$oldfile = $newfile;

	while (-l $newfile) {
		push @symlinks, $newfile;
		$oldfile = $newfile;
		$link = readlink($newfile);
		$newfile = $_;
		$newfile =~ s,.*/,,;
		$path = $_;
		$path =~ s,[^/]*$,,;
		$newfile = $path . $link;
		break if("$oldfile" == "$newfile");
	}
	if(-e $newfile) {
		push @symlinks, $newfile;
		while($file = pop @symlinks) {
			if(!$targets{$file}) {
				$targets{$file} = 1;
				print "$file\n";
			}
		}
	}
}
