package EC::AzureDevOps::WorkItems;

use strict;
use warnings;
use JSON;
use MIME::Base64 qw(encode_base64);
use Data::Dumper;
use base qw(EC::RESTPlugin);
use LWP::UserAgent;


sub step_query_work_items {
    my ($self) = @_;

    my $fields = [qw/config project query timePrecision fields asOf $expand resultPropertySheet resultFormat/];
    my $parameters = $self->get_params_as_hashref(@$fields);
    $self->logger->debug("Parameters", $parameters);
    my $config = $self->get_config_values($parameters->{config});

    my $username = $config->{userName};
    my $password = $config->{password};

    my $auth = encode_base64("$username:$password");

    my $endpoint = "$config->{endpoint}/$config->{collection}/$parameters->{project}/_apis/wit/wiql";
    $self->logger->debug("Endpoint: $endpoint");

    my %query = ();
    if ($parameters->{timePrecision}) {
        $query{timePrecision} = $parameters->{timePrecision};
    }
    $query{'api-version'} = get_api_version($endpoint, $config);

    my $url = URI->new($endpoint);
    $url->query_form(%query);
    my $request = $self->get_new_http_request(POST => $url);

    $request->header('Authorization' => "Basic $auth");
    my $payload = encode_json({query => $parameters->{query}});

    $request->content($payload);
    $request->header('Content-type', 'application/json');

    $self->logger->trace('Request', $request);
    my $ua = $self->new_lwp();
    my $response = $ua->request($request);

    unless($response->is_success) {
        $self->logger->info($response);
        return $self->bail_out("Request failed: " . $response->decoded_content);
    }

    $self->logger->trace('Got response', $response->decoded_content);

    my $parsed = decode_json($response->content);
    my @ids = ();

    $self->logger->debug('Parsed response', $parsed);

    my $ids = [];
    if ($parsed->{queryType} eq 'flat') {
        $ids = $self->get_flat_ids($parsed);
    }
    elsif ($parsed->{queryType} eq 'tree') {
        $ids = $self->get_tree_ids($parsed);
    }
    elsif($parsed->{queryType} eq 'oneHop') {
        $ids = $self->get_one_hop_ids($parsed);
    }
    else {
        $self->bail_out("Unknown type of query: $parsed->{queryType}");
    }

    unless(@$ids) {
        $self->set_summary('No work items found');
        exit 0;
    }

    $endpoint = "$config->{endpoint}/$config->{collection}/_apis/wit/workitems";
    %query = ('api-version' => get_api_version($endpoint, $config));
    for my $field ( qw(asOf $expand)) {
        if ($parameters->{$field}) {
            $query{$field} = $parameters->{$field};
        }
    }
    $query{ids} = join(',' => @$ids);
    $url = URI->new($endpoint);
    $url->query_form(%query);

    $request = $self->get_new_http_request(GET => $url);
    $request->header('Authorization' => "Basic $auth");
    $self->logger->trace('Request', $request);
    $response = $ua->request($request);

    unless($response->is_success) {
        $self->logger->debug($response);
        $self->bail_out("Request failed: " . $response->decoded_content);
    }

    $self->logger->debug('Response raw', $response->decoded_content);

    $parsed = decode_json($response->content);
    $self->save_parsed_data($parameters, $parsed);

    my $count = $parsed->{count};
    my @titles = ();
    my $more = 0;
    for my $item (@{$parsed->{value}}) {
        my $title = $item->{fields}->{'System.Title'};

        if ( scalar @titles > 5) {
            $more = 1;
            last;
        }
        else {
            push @titles, $title if $title;
        }
    }
    my $summary = "Got work items: $count, titles: " . join(", ", @titles);
    $summary .= ', ' . ($count - 5) . ' items more'  if $more;
    $self->set_pipeline_summary("Work items retrieved", $summary);
    $self->set_summary($summary);
}


sub save_parsed_data {
    my ($self, $parameters, $parsed_data) = @_;

    my $property_name = $parameters->{resultPropertySheet};
    my $selected_format = $parameters->{resultFormat};

    unless($selected_format) {
        return $self->bail_out('No format has beed selected');
    }

    unless($parsed_data) {
        $self->logger->info("Nothing to save");
        return;
    }

    $self->logger->info("Got data", JSON->new->pretty->utf8->encode($parsed_data));
    if ($selected_format eq 'propertySheet') {
        my $flat_map = EC::RESTPlugin::_flatten_map($parsed_data, $property_name);

        for my $key (sort keys %$flat_map) {
            $self->ec->setProperty($key, $flat_map->{$key});
            $self->logger->info("Saved $key -> $flat_map->{$key}");
        }
    }
    elsif ($selected_format eq 'json') {
        my $json = encode_json($parsed_data);
        $self->ec->setProperty($property_name, $json);
        $self->logger->info("Saved answer under $property_name");
    }
}

sub get_tree_ids {
    my ($self, $parsed) = @_;

    my $relations = $parsed->{workItemRelations};
    return [] unless $relations;

    my @ids = ();
    for my $rel (@$relations) {
        push @ids, $rel->{target}->{id};
    }
    return \@ids;
}


sub get_flat_ids {
    my ($self, $parsed) = @_;

    my @ids = map {$_->{id}} @{$parsed->{workItems}};
    return \@ids;
}

sub get_one_hop_ids {
    my ($self, $parsed) = @_;

    my @ids = map {$_->{target}->{id}} @{$parsed->{workItemRelations}};
    return \@ids;
}

sub _parse_api_versions {
    my ($string) = @_;

    my @lines = split(/\n+/, $string);
    my %retval = map { my ($key, $value) = split(/\s*=\s*/, $_) } grep { $_ } @lines;
    return \%retval;
}

sub get_api_version {
    my ($uri, $config) = @_;

    if ($config->{apiVersion} ne 'custom'){
        return $config->{apiVersion};
    }

    my $api_versions = _parse_api_versions($config->{apiVersions});
    my ($first_name, $second_name) = $uri =~ m{/_apis/(\w+)/(\w+)};
    my $version = $api_versions->{"$first_name/$second_name"} || '1.0';

    return $version;
}


1;
