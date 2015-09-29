package App::qid;
use v5.14;

use HTTP::Tiny;       # libhttp-tiny-perl
use JSON;             # libjson-perl
use Term::ANSIColor;  # core
use Getopt::Long qw(GetOptionsFromArray);  # core  

# require Getopt::Complete; # libgetopt-complete-perl

my $VERSION='0.1.0';

sub run {
    my $argv = $_[1] // \@ARGV;
    my $self = bless { argv => $argv }, shift; 

    binmode STDOUT, ':encoding(UTF-8)';

    my $complete = defined $ENV{COMP_CWORD};

    Getopt::Long::Configure('bundling');
    Getopt::Long::Configure('pass_through') if $complete;

    my @query = @$argv;
    GetOptionsFromArray( \@query, $self, 
        'help|h|?',
        'version',
        'suggest|s',
        'description|d!',
        'qid|q!',
        'aliases|a!',
        'unique|u!',
        'color|c!',
        'api=s',
        'language=s',
    ) or return 1;

    # use color by default if output is terminal
    $self->{color} //= -t STDOUT ? 1 : 0; 

    # default values
    $self->{api} //= 'https://www.wikidata.org/w/api.php';
    $self->{language} //=  do { my $l=$ENV{LANG}; $l =~ s/_.*//; $l };
    
    # check whether first argument is double dash
    $self->{doubledash} = $argv->[-(@query+1)] eq '--';
    $self->{nonqids} = (grep { $_ !~ /^q[0-9]+$/i && $_ ne '' } @query);

    if ($complete) {
        return $self->complete($ENV{COMP_CWORD}, @query);
    } elsif ($self->{version}) {
        return $self->version;
    } elsif ($self->{help} or !@query) {
        return $self->usage;
    } 

    # ignore empty argument
    @query = grep { $_ ne '' } @query;

    if ($self->{doubledash} || $self->{nonqids}) {
        return $self->lookup_by_label(@query);
    } else {
        return $self->lookup_by_qid(@query);
    }
}

sub complete {
    my ($self, $cword, @query) = @_;

    $cword //= $ENV{COMP_CWORD} // return 0;
    my $argv = $self->{argv};

    open my $fh, '>>', 'log';

    # no qid or label arguments
    if (!@query) {
        # no options or cursor after options
        if ($cword > @$argv && !$self->{doubledash}) { 
            say "--";
        }
        return 0;
    }

    shift @query if $query[0] eq '--';
    return 0 unless @query;

    # TODO: complete qids with 0-9
    if ($self->{doubledash} || $self->{nonqids}) {
        my $label = $query[$cword - @$argv + @query - 1];
        return 0 if $label eq '';

        my $res = $self->suggest_item($label);
        foreach my $item (@$res) { 
            say $item->{label};
        }
        say $fh $label." ".encode_json([$cword,\@query,$self->{argv}]);
    }

    return 0;
}
   
sub get {
    my ($self, %params) = @_; 
    $params{format} = 'json';

    state $http = HTTP::Tiny->new(
        default_headers => {
            Accept => "application/json",
            agent  => "qid/$VERSION",
        },
    );

    my $url = $self->{api}."?".$http->www_form_urlencode(\%params);
    # say $url;

    my $res = $http->get($url);

    if ($res->{success}) {
        $res = decode_json($res->{content});
        return $res;
    } else {
        # TODO: show error
        return;
    }
};

sub lookup_by_qid {
    my $self = shift;
    my @qids = map { uc($_) } @_;
    
    # Look up item by Wikidata identifier
    # Print its label (may be the empty string) if found.
    # Exit with return code 1 otherwise.

    my $lang = $self->{language};
    my @props = qw(labels);
    push @props, 'descriptions' if $self->{description};
    push @props, 'aliases' if $self->{aliases};

    my $res = $self->get(
        action    => 'wbgetentities',
        props     => join('|', @props),
        ids       => join('|', @qids),
        languages => $lang,
    );

    # say encode_json($res);

    foreach my $qid (@qids) {
        my $entity = $res->{entities}->{$qid};

        return 1 if exists $entity->{missing};

        my $item = {};
        $item->{id} = $qid if $self->{qid};

        my $v = $entity->{labels}->{$lang};
        $item->{label} = $v ? $v->{value} : ''; 

        $v = $entity->{descriptions}->{$lang};
        $item->{description} = $v ? $v->{value} : ''; 

        $self->print_item($item);
    }

    return 0;
}

sub lookup_by_label {
    my $self = shift;
    my @labels = @_;

    my $lang = $self->{language};
    my @props = qw(labels);
    push @props, 'descriptions' if $self->{description};
    push @props, 'aliases' if $self->{aliases};

    # TODO: actually lookup instead of suggest
    foreach my $label (@labels) {
        my $res = $self->suggest_item($label);
        foreach my $item (@$res) { 
            #say encode_json($item);
            delete $item->{id} unless $self->{qid};
            delete $item->{description} unless $self->{description};
            delete $item->{aliases} unless $self->{aliases};
            $self->print_item($item);
        }
    }

    return 0;
}

sub suggest_item {
    my ($self, $label) = @_;
    my $res = $self->get(
        action => 'wbsearchentities',
        search => $label,
        language => $self->{language},
        # get results in same language as query
        uselang  => $self->{language}, 
        type => 'item',
        continue => 0,
    );
    $res ? $res->{search} : [];
}


sub print {
    my ($self, $str, $color) = @_;
    print $self->{color} && $color ? colored($str, $color) : $str;
}

sub print_item {
    my ($self, $item) = @_;

    if (defined $item->{id}) {
        $self->print($item->{id}) ;
        print " " if defined $item->{label};
    }
    if (defined $item->{label}) {
        $self->print($item->{label}, 'white');
    }
    if (defined $item->{description}) {
        print "  ";
        $self->print($item->{description});
    }
    print "\n";

}

sub usage {
    say "qid [OPTIONS] QID ...";
    say "qid [OPTIONS] [--] 'LABEL' ...";
    return 0;
}

sub version {
    say "qid $VERSION";
    return 0;
}

1;
__END__
