#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use HTTP::Tiny;
use Getopt::Long;
use JSON;
use CPAN::DistnameInfo;

Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    "force" => \my $force,
);

sub _by_version {
    my %v = map {
        my @v = split(qr/[-._]/, $_);
        $v[1] = substr($v[1],0,3);
        $v[2] ||= 0;
        $v[2] =~ s/^0+/0/g;
        $v[2] = 0 if $v[2] =~ m![^0-9]!;
        $v[3] ||= 'Z';
        $v[3] =~ s/^0+/0/g;
        ($_ => sprintf '%d.%03d%03d-%s', @v)
    } $a->version, $b->version;
    $v{$b->version} cmp $v{$a->version};
}

my $tsv = $FindBin::Bin . '/htdocs/perl_versions.txt';
mkdir $FindBin::Bin . '/htdocs';

my $req = <<'EOF';
{
    "size": 1000,
    "query": {
        "term": {
            "distribution": "perl"
        }
    },
    "sort": [
        { "version_numified": "desc" }
    ],
    "filter": {
        "and": [
            { "term": { "authorized": true } },
            { "term": { "status": "cpan" } }
        ]
    },
    "fields": ["download_url"]
}
EOF

my $agent = HTTP::Tiny->new;
my $res = $agent->request('GET', 'http://api.metacpan.org/v0/release/_search', { content => $req } );
die("Failed to request api.metacpan.org status:$res->{status} reason:$res->{reason}\n") unless $res->{success};
exit() if $res->{status} != 200;

my $versions = '';
eval {
    my $ref = JSON::decode_json($res->{content});
    my @releases;
    foreach my $rel ( @{$ref->{hits}->{hits}} ) {
        my $path = $rel->{fields}->{download_url};
        $path =~ s{\A.*/authors/id/}{}msx;
        push @releases, CPAN::DistnameInfo->new($path);
    }
    foreach my $r ( sort _by_version  @releases ) {
        $versions .= $r->version . "\t" . $r->pathname ."\n";

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

