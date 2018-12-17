package EC::Plugin::MicroRest;

use strict;
use warnings;

use LWP::UserAgent;
use Data::Dumper;
use Carp;
use JSON;
use HTTP::Request;
use URI::Escape;

# use EC::ProxyDriver;
# use EC::ProxyDispatcher;

use subs qw/allowed_methods ignore_errors/;

my $ignore_errors = 0;

my @ALLOWED_METHODS = ('GET', 'POST', 'PUT', 'PATCH', 'OPTIONS', 'DELETE');


sub ignore_errors {
    my (undef, $flag) = @_;

    print "Ignore errors: $ignore_errors\n";

    unless (defined $flag) {
        return $ignore_errors;
    }

    $ignore_errors = $flag;
    return $ignore_errors;
}


sub new {
    my ($class, %params) = @_;

    my $self = {};

    for my $p (qw/url user password auth/) {
        if ($params{auth} && $params{auth} !~ m/^basic|oauth1.0a?|ntlm$/s) {
            croak "Wrong auth method";
        }
        if (!defined $params{$p}) {
            croak "Missing mandatory parameter $p\n";
        }
        $self->{_data}->{$p} = $params{$p};
    }

    # Fixing url (remove trailing spaces, leave only one slash at value end)
    $self->{_data}->{url} =~ s/\s+$//gs;
    $self->{_data}->{url} =~ s|\/$||gs;
    $self->{_data}->{url} .= '/';

    if ($params{dispatch} && ref $params{dispatch} eq 'HASH') {
        $self->{_dispatch} = $params{dispatch};
    }

    if ($params{content_type} && $params{content_type} =~ m/^(?:xml|json)$/is) {
        $self->{_ctype} = lc $params{content_type};
    }
    elsif ($params{ctype}){
        $self->{_ctype} = lc $params{ctype};
    }

    if (!$self->{_ctype}) {
        $self->{_ctype} = 'json';
    }

    if ($params{oauth_params}){
        $self->{_data}{oauth_params} = $params{oauth_params};
    }

    if ($params{http_proxy}){
        $self->{_data}{proxy_params} = {
            http_proxy => $params{http_proxy},
            username   => $params{proxy_username},
            password   => $params{proxy_password},
        };
    }

    for my $sub_ref (qw/encode_sub decode_sub/){
        $self->{$sub_ref} = $params{$sub_ref} if $params{$sub_ref};
    }

    bless $self, $class;
    $self->_init();
    return $self;
}


sub _init {
    my ($self) = @_;
    #
    # $self->{ec} = ElectricCommander->new();
    # $self->{ec}->abortOnError(0);

    $self->{ua} = $self->get_lwp_instance();

    # Init proxy if defined
    if ($self->{_data}{proxy_params}){
        $self->{_proxy_dispatcher} = EC::ProxyDispatcher->new( $self->{_data}{proxy_params} );
        $self->{proxy} = $self->{_proxy_dispatcher}->get_proxy_dispatcher();

        if ($self->{proxy}) {
            $self->{proxy}->apply();
            $self->{ua} = $self->{proxy}->augment_lwp($self->{ua});
        }
    }

    # Init OAuth if have to use it
    if ($self->is_oauth){

        if (!$self->{_data}->{oauth_params}){
            croak "OAuth authorization should be used, but no OAuth parameters are provided";
        }

        require EC::OAuth;
        EC::OAuth->import();

        my $Oauth = EC::OAuth->new( $self->{_data}->{oauth_params} );

        # Set UserAgent with proxy
        # It will be used only for request/authorize token requests
        $Oauth->ua($self->{ua});
        $self->{oauth} = $Oauth;
    }
}


sub _call {
    my ($self, $meth, $url_path, $content) = @_;

    if ($meth !~ m/^(?:GET|POST|PUT|PATCH|OPTIONS|DELETE)$/s) {
        croak "Method $meth is unknown";
    }

    print "Request URL is:" .  $self->{_data}->{url} . $url_path . "\n";
    my $req = HTTP::Request->new($meth => $self->{_data}->{url} . $url_path);

    if ($self->{proxy}) {
        $req = $self->{proxy}->augment_request($req);
    }

    if ($self->{_data}->{auth} eq 'basic') {
        $req->authorization_basic($self->{_data}->{user}, $self->{_data}->{password});
    }

    if ($content) {
        $content = $self->encode_content($content);

        if ($self->{_ctype} eq 'json') {
            $req->header('Content-Type' => 'application/json');
        }
        elsif ($self->{_ctype} ne 'xml') {
            $req->header('Content-Type' => $self->{_ctype});
        }

        $req->content($content);
    }

    my $resp = $self->{ua}->request($req);

    # Saving here so we can get it later in check_connection
    $self->{last_response} = $resp;

    my $object;
    if ($resp->code() < 400) {
        $object = $self->decode_content($resp->decoded_content());
    }
    elsif ($resp->code() == 401) {
        croak "Unauthorized. Check your credentials\n";
    }
    elsif ($resp->code() == 403) {
        croak "Access is forbidden, check your data\n";
    }
    else {
        if (! ignore_errors) {
            croak "Response status:" . $resp->status_line() . "\n"
                . "Content: " . $resp->decoded_content() . "\n";
        }
        print "Error occured: " . Dumper $resp->decoded_content();
    }
    return $object;
}


sub encode_content {
    my ($self, $content) = @_;

    return undef unless $content;

    if ($self->{encode_sub}){
       return &{$self->{encode_sub}}($content);
    }
    elsif ($self->{_ctype} =~ 'json') {
        return encode_json($content);
    }
    elsif ($self->{_ctype} eq 'xml') {
        return XMLout($content);
    }

    # return as is
    return $content;
}


sub decode_content {
    my ($self, $content) = @_;

    return '' unless $content;

    if ($self->{decode_sub}){
       return &{$self->{decode_sub}}($content);
    }
    elsif ($self->{_ctype} eq 'json') {
        return decode_json($content);
    }
    elsif ($self->{_ctype} eq 'xml') {
        return XMLin($content);
    }

    # return as is
    return $content;
}

sub get {
    my ($self, $url_path, $params) = @_;

    # Clear URL (everything should go in params)
    # TODO: change this to exception
    if ($url_path =~ /\?.*$/){
        print "URL: $url_path, QUERY PARAMETERS: " . join(';', map { "$_ : '$params->{$_}'" } keys %$params) . "\n";
        confess "Query parameters should be passed in \$params.\n";
    }

    if ($self->is_oauth){
        # OAuth will add new parameters to query
        $params = $self->augment_oauth_params('GET', $url_path, $params);
    }
    if ($params && %$params) {
        $url_path = _augment_url($url_path, $params);
    }

    return $self->_call(
        'GET' =>  $url_path
    );
}

sub post {
    my ($self, $url_path, $params, $content) = @_;

    if ($self->is_oauth){
        # URL should contain OAuth params
        my $request_params = $self->augment_oauth_params('POST', $url_path);
        $url_path = _augment_url($url_path, $request_params);
    }
    elsif ($params && %$params) {
        $url_path = _augment_url($url_path, $params);
    }

    return $self->_call(
        'POST' =>  $url_path,
        $content
    );
}

sub put {
    my ($self, $url_path, $params) = @_;

    if ($self->is_oauth){
        my $request_params = $self->augment_oauth_params('PUT', $url_path);
        $url_path = _augment_url($url_path, $request_params);
    }

    return $self->_call(
        'PUT' => $url_path,
        $params
    );
}

sub patch {
    my ($self, $url_path, $params, $content) = @_;

    if ($self->is_oauth){
        my $request_params = $self->augment_oauth_params('PUT', $url_path);
        $url_path = _augment_url($url_path, $request_params);
    }

    if ($params && %$params) {
        $url_path = _augment_url($url_path, $params);
    }

    return $self->_call(
        'PATCH' => $url_path,
        $content
    );
}


sub delete {
    my ($self, $url_path, $params) = @_;

    if ($self->is_oauth){
        $params = $self->augment_oauth_params('DELETE', $url_path, $params);
    }

    return $self->_call(
        'DELETE' => $url_path,
        $params
    );
}

sub augment_oauth_params {
    my ( $self, $method, $url_path, $params ) = @_;

    if ($self->is_oauth()){
        $params = {} if (!$params || ref $params ne 'HASH');

        my $Oauth = $self->{oauth};
        my $params_with_oauth = $Oauth->augment_params_with_oauth($method, $self->{_data}{url} . $url_path, $params);
        if ($params_with_oauth){
            $params = $params_with_oauth;
        }
        else {
            confess 'OAuth did not returned oauth request params'
        }
    }

    return $params;
}


sub _augment_url {
    my ($url, $hash) = @_;

    $url =~ s|\/*?$||gs;
    my $gs = '';
    for my $k (keys %$hash) {
        $gs .= uri_escape($k) . '=' . uri_escape($hash->{$k}) . '&';
    }
    $gs =~ s/&$//s;
    if ($url =~ m|\?|s) {
        $gs = '&' . $gs;
    }
    else {
        $gs = '?' . $gs;
    }
    $url .= $gs;
    return $url;
}

sub encode_request {
    1;
}

sub decode_response {
    1;
}

sub is_oauth {
    my ($self) = @_;
    return $self->{_data}{auth} =~ m/oauth/si;
}

sub get_lwp_instance {
    my ($self) = @_;

    my LWP::UserAgent $ua = LWP::UserAgent->new;

    my $auth_type = $self->{_data}{auth};

    if ($auth_type eq 'ntlm'){

        if (!$ua->conn_cache()) {
            $ua = LWP::UserAgent->new(keep_alive => 1);
        }

        # Get credential
        my $username = $self->{_data}->{user};
        my $password = $self->{_data}->{password};

        if ($username !~ /\\/){
            $username = '\\' . $username;
        }

        # Get url
        my $url = URI->new($self->{_data}->{url});

        # Get host:port
        my ($host, $port) = ($url->host(), $url->port);

        $ua->credentials($host . ":" . $port, '', $username, $password);

        # TFS will return three possible authentication schemes. Bearer (OAuth, Basic and NTLM)
        # LWP::UserAgent will hug itself at Basic, so we should leave only NTLM for processing
        $ua->set_my_handler('response_done', sub {
            my HTTP::Response $response = shift;
            my HTTP::Headers $headers = $response->headers;

            # Get all the headers
            my @auth_headers = $headers->header('WWW-Authenticate');

            # Leave only NTLM header
            $headers->header('WWW-Authenticate', grep { $_ =~ /^ntlm/i } @auth_headers);

            # Apply the changed headers
            $response->headers($headers);
        });

    }

    return $ua;
}

1;

