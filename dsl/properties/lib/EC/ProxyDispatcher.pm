package EC::ProxyDispatcher;

use strict;
use warnings;
use Data::Dumper;
use Carp;

use EC::ProxyDriver;

sub new {
    my ($class, $params) = @_;

    croak "No params hash given to EC::ProxyDispatcher->new()" unless ($params && ref $params eq 'HASH');

    my $self = { };
    bless $self, $class;
    
    $self->init($params);
    
    return $self;
}


sub init {
    my ( $self, $params ) = @_;

    # Can read config values from params or get from config
    if ($params) {
        $self->{http_proxy} = $params->{http_proxy};

        if ($self->is_proxy_defined) {
            $self->{proxy_username} = $params->{username};
            $self->{proxy_password} = $params->{password}
        }
        else {
            print "No proxy settings found.\n";
        }
    }

    return $self;
}

sub get_proxy_dispatcher {
    my ($self) = @_;

    return undef unless $self->is_proxy_defined();

    if (!$self->{_proxy_dispatcher}) {
        my $proxy = EC::ProxyDriver->new({
            url      => $self->{http_proxy},
            username => $self->{proxy_username},
            password => $self->{proxy_password},
            debug    => 1
        });
        $self->{_proxy_dispatcher} = $proxy;
    }

    return $self->{_proxy_dispatcher};
}


sub is_proxy_defined {
    my ($self) = @_;
    return (defined $self->{http_proxy} && $self->{http_proxy} ne '');
}

1;
