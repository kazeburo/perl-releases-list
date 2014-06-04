#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use HTTP::Tiny;
use Getopt::Long;
use JSON;

Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    "force" => \my $force,
);

sub _by_version {
    my %v = map {
        my @v = split(qr/[-._]/, $_);
        $v[2] ||= 0;
        $v[2] =~ s/^0+/0/g;
        $v[3] ||= 'Z';
        $v[3] =~ s/^0+/0/g;
        ($_ => sprintf '%d.%03d%03d-%s', @v)
    } $a->{version}, $b->{version};
    $v{$b->{version}} cmp $v{$a->{version}};
}

my $tsv = $FindBin::Bin . '/htdocs/perl_versions.txt';
mkdir $FindBin::Bin . '/htdocs';

my $agent = HTTP::Tiny->new;
my $res = $agent->get('http://search.cpan.org/api/dist/perl');
die("Cannot get search.cpan.org/api/dist/perl $res->{status} $res->{reason}\n") unless $res->{success};
exit() if $res->{status} != 200;

my $versions = '';
eval {
    my $ref = JSON::decode_json($res->{content});
    foreach my $release ( sort _by_version grep { $_->{authorized} }  @{$ref->{releases}} ) {
        $versions .= $release->{version} . "\t"
            . join('/', substr( $release->{cpanid}, 0, 1 ), substr( $release->{cpanid}, 0, 2 ), $release->{cpanid}, $release->{archive} )
            . "\n";
    }
};
die("JSON parse error: $@") if $@;

#test
my @tests = ("5.18.1\tR/RJ/RJBS/perl-5.18.1.tar.",
            "5.17.3\tS/SH/SHAY/perl-5.17.3.tar.",
            "5.16.3\tR/RJ/RJBS/perl-5.16.3.tar.",
            "5.12.2\tJ/JE/JESSE/perl-5.12.2.tar.",
            "5.8.5\tN/NW/NWCLARK/perl-5.8.5.tar.",
            "5.6.1\tG/GS/GSAR/perl-5.6.1.tar.");
for my $test ( @tests ) {
    die "'$test' is not found" if $versions !~ m!^\Q$test\E!m;
}

open (my $fh, '>', $tsv) or die "$!";
print $fh $versions;
close($fh);

system('s3cmd','-v','-P','sync',$tsv,'s3://perl-releases/versions.txt');

