#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use HTTP::Tiny;
use Getopt::Long;

Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    "force" => \my $force,
);

my $mirror = $FindBin::Bin . '/mirror/Releases.pm';
my $tsv = $FindBin::Bin . '/htdocs/perl_versions.txt';
mkdir $FindBin::Bin . '/mirror';
mkdir $FindBin::Bin . '/htdocs';
unlink $mirror if $force;
my $agent = HTTP::Tiny->new;
my $res = $agent->mirror('https://raw.githubusercontent.com/bingos/cpan-perl-releases/master/lib/CPAN/Perl/Releases.pm',$mirror);
die("Cannot get content from github: $res->{status} $res->{reason}\n") unless $res->{success};

exit() if $res->{status} != 200;

eval {
    do "$mirror";
};
die "Cannot load CPAN/Perl/Releases.pm: $@" if $@;

my $versions = '';
for my $version ( reverse CPAN::Perl::Releases::perl_versions() ) {
   my $tarballs = CPAN::Perl::Releases::perl_tarballs($version);
   my ($x) = sort values %$tarballs;
   $versions .= "$version\t$x\n";
}
open (my $fh, '>', $tsv) or die "$!";
print $fh $versions;
close($fh);

system('s3cmd','-v','-P','put',$tsv,'s3://perl-releases/versions.txt');

