#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Proclet;
use Plack::Loader;
use Plack::Builder;
use Getopt::Long;
use HTTP::Tiny;
use JSON;
use CPAN::DistnameInfo;

my $port = 5000;
Getopt::Long::Configure ("no_ignore_case");
GetOptions(
    "p|port=s" => \$port,
);

chdir($FindBin::Bin);

my $tsv = $FindBin::Bin . '/tmp/htdocs/perl_versions.txt';
mkdir $FindBin::Bin . '/tmp';
mkdir $FindBin::Bin . '/tmp/htdocs';

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
            { "terms": { "status": ["cpan","latest"] } }
        ]
    },
    "fields": ["download_url"]
}
EOF

sub cap_cmd {
    my ($cmdref) = @_;
    pipe my $logrh, my $logwh
        or die "Died: failed to create pipe:$!";
    my $pid = fork;
    if ( ! defined $pid ) {
        die "Died: fork failed: $!";
    } 

    elsif ( $pid == 0 ) {
        #child
        close $logrh;
        open STDERR, '>&', $logwh
            or die "Died: failed to redirect STDERR";
        open STDOUT, '>&', $logwh
            or die "Died: failed to redirect STDOUT";
        close $logwh;
        exec @$cmdref;
        die "Died: exec failed: $!";
    }
    close $logwh;
    my $result;
    while(<$logrh>){
        warn $cmdref->[0]." : ".$_;
        $result .= $_;
    }
    close $logrh;
    while (wait == -1) {}
    my $exit_code = $?;
    $exit_code = $exit_code >> 8;
    return ($result, $exit_code);
}

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

sub fetch_version_list {
    my $agent = HTTP::Tiny->new(timeout=>20);
    my $res = $agent->request('GET', 'http://api.metacpan.org/v0/release/_search', { content => $req } );
    die "Failed to request api.metacpan.org status:$res->{status} reason:$res->{reason}\n" unless $res->{success};

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
    die "JSON parse error: $@\n" if $@;

    #test
    my @tests = ("5.20.0\tR/RJ/RJBS/perl-5.20.0.tar.",
                 "5.18.1\tR/RJ/RJBS/perl-5.18.1.tar.",
                 "5.17.3\tS/SH/SHAY/perl-5.17.3.tar.",
                 "5.16.3\tR/RJ/RJBS/perl-5.16.3.tar.",
                 "5.12.2\tJ/JE/JESSE/perl-5.12.2.tar.",
                 "5.8.5\tN/NW/NWCLARK/perl-5.8.5.tar.",
                 "5.6.1\tG/GS/GSAR/perl-5.6.1.tar.");
    for my $test ( @tests ) {
        die "'$test' is not found\n" if $versions !~ m!^\Q$test\E!m;
    }

    open (my $fh, '>', $tsv) or die "$!";
    print $fh $versions;
    close($fh);

    cap_cmd(['s3cmd',
#             '--access_key='.$ENV{AWS_ACCESS_KEY},
#             '--secret_key='.$ENV{AWS_SECRET_ACCESS_KEY},
             '-v','-P','sync',$tsv,'s3://perl-releases/versions_test.txt'])
}

eval {
    fetch_version_list();
};
warn $@ if $@;

my $proclet = Proclet->new;

$proclet->service(
    every => '4,19,34,49 * * * *',
    tag => 'cron',
    code => sub {
        eval {
            fetch_version_list();
        };
        warn $@ if $@;
    },
);

my $app = builder {
    enable 'Lint';
    enable 'StackTrace';
    sub {
        my $env = shift;
        open(my $fh, '<', $tsv) or die "$!";
        return [200,['Content-Type'=>'text/plain'],$fh];
    }
};

$proclet->service(
    code => sub {
        my $loader = Plack::Loader->load(
            'Starlet',
            port => $port,
            host => 0,
            max_workers => 5,
        );
        $loader->run($app);
    },
    tag => 'web',
);

$proclet->run;

