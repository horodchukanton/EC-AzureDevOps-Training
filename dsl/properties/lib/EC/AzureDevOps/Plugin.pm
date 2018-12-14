package EC::AzureDevOps::Plugin;
use strict;
use warnings FATAL => 'all';

use base 'EC::Plugin::Core';

use Data::Dumper;
use JSON::XS qw/decode_json encode_json/;

use EC::Plugin::Microrest;
use EC::AzureDevOps::WorkItems;

my %MS_FIELDS_MAPPING = (
    title       => 'System.Title',
    description => 'System.Description',
    assignTo    => 'System.AssignedTo',
    priority    => 'Microsoft.VSTS.Common.Priority',
);


sub after_init_hook {
    my ($self, %params) = @_;

    $self->{plugin_name} = '@PLUGIN_NAME@';
    $self->{plugin_key} = '@PLUGIN_KEY@';
    my $debug_level = 0;
    my $proxy;

    $self->logger->info($self->{plugin_name});

    if ($self->{plugin_key}) {
        eval {
            $debug_level = $self->ec()->getProperty(
                "/plugins/$self->{plugin_key}/project/debugLevel"
            )->findvalue('//value')->string_value();
        };

        eval {
            $proxy = $self->ec->getProperty(
                "/plugins/$self->{plugin_key}/project/proxy"
            )->findvalue('//value')->string_value;
        };
    }

    if ($debug_level) {
        $self->debug_level($debug_level);
        $self->logger->level($debug_level);
        $self->logger->debug("Debug enabled for $self->{plugin_key}");
    }

    else {
        $self->debug_level(0);
    }

    if ($proxy) {
        $self->{proxy} = $proxy;
        $self->logger->info("Proxy enabled: $proxy");
    }

    eval {
        my $log_to_property = $self->ec->getProperty('/plugins/@PLUGIN_KEY@/project/ec_debug_logToProperty')->findvalue('//value')->string_value;
        $self->logger->log_to_property($log_to_property);
        $self->logger->info("Logs are redirected to property $log_to_property");
    };
}


sub step_create_work_items {
    my ($self) = @_;

    my $fields = [qw/config project type title priority assignTo description additionalFields requestBody sourceProperty resultPropertySheet resultFormat/];
    my $parameters = $self->get_params_as_hashref(@$fields);

    $self->logger->debug("Parameters", $parameters);

    for my $required (qw/config project title type resultPropertySheet resultFormat/){
        $self->bail_out("Parameter '$required' is mandatory") unless $parameters->{$required};
    }

    my $config = $self->get_config_values($parameters->{config});
    my $username = $config->{userName};
    my $password = $config->{password};

    my $client = EC::Plugin::MicroRest->new(
        url      => $self->get_base_url($config),
        auth     => $config->{auth} || 'basic',
        user     => $username,
        password => $password,
        ctype    => 'application/json-patch+json'
    );

    my $type = ($parameters->{type} =~ /^\$/) ? $parameters->{type} : '$' . $parameters->{type};

    my $method_path = $parameters->{project} . '/_apis/wit/workitems/' . $type;
    $self->logger->debug("Path: $method_path");

    # Api version should be sent in query
    my %query = ();
    $query{'api-version'} = EC::AzureDevOps::WorkItems::get_api_version($method_path, $config);

    my @work_item_payloads = $self->build_createupdate_workitem_payloads($parameters);

    my @created_items = ();
    my @ids = ();

    # Finally can send the request
    for my $payload (@work_item_payloads){
        my $response = $client->post($method_path, \%query, $payload);

        my $result = $self->decode_json_or_bail_out($response, "Failed to parse JSON response from $config->{endpoint}.");

        push @created_items, $result;
        push(@ids, $result->{id});
    }

    $self->save_entities();

    my $count = scalar(@created_items);
    my $summary = "Successfully created $count work item" . (($count > 1) ? 's' : '') . '.';

    $self->set_pipeline_summary($summary);
    $self->set_summary($summary);
}

sub build_createupdate_workitem_payloads {
    my ($self, $parameters) = @_;

    my @results = ();

    # If we have a request body, will not read other parameters.
    # But should be sure that it is valid.
    if ($parameters->{requestBody}){
        my $err_msg = 'Value for "Request Body" parameter should contain valid JSON array.';

        my $payload = $self->decode_json_or_bail_out( $parameters->{requestBody}, $err_msg);
        $self->bail_out($err_msg) unless ref($payload) eq 'ARRAY';

        return $payload;
    }

    my @generic_fields = ();

    # Map parameters to Azure operations
    for my $param (qw/priority assignTo description/){
        next unless $parameters->{$param};
        my $ms_name = $MS_FIELDS_MAPPING{$param};
        push @generic_fields, { op => 'add', path => '/fields/' . $ms_name, value => $parameters->{$param} };
    }

    # Add additional fields
    if ($parameters->{additionalFields}){
        my $err_msg = 'Value for "Additional Fields" parameter should contain valid JSON array.';
        my $additional_fields = $self->decode_json_or_bail_out($parameters->{additionalFields}, $err_msg);
        $self->bail_out($err_msg) unless (ref($additional_fields) eq 'ARRAY');

        push @generic_fields, @$additional_fields;
    }

    # Add title. In this point we will know if have to create more that one work items;
    my @titles = ();
    if ($parameters->{sourceProperty}) {
        my $propertyValue = '';
        eval {
            $propertyValue = $self->ec()->getProperty($parameters->{sourceProperty});
            1;
        } or do {
            $self->bail_out("Failed to read property '$parameters->{sourceProperty}'. $@");
        };

        if (!$propertyValue){
            $self->bail_out("Failed to get value of the \"Source Property\"");
        }

        my $err_msg = 'Value for "Source Property" should contain valid JSON array.';
        my $source_titles = $self->decode_json_or_bail_out($propertyValue, $err_msg);
        $self->bail_out($err_msg) unless ref($source_titles) eq 'ARRAY' && scalar @$source_titles;
        push @titles, map { $_->{Title} } @$source_titles;
    }
    else {
        push @titles, $parameters->{title};
    }

    @results = map {
        [
            @generic_fields,
            {
                op => 'add',
                path => '/fields/' . $MS_FIELDS_MAPPING{title},
                value => $_
            }
        ]
    } @titles;


    return wantarray ? @results : \@results;
}

sub save_entities{
    my ($entities_list, $result_format, $result_property) = @_;

    print Dumper $entities_list;

    return 1;
}

sub get_base_url {
    my ($self, $config) = @_;

    $config ||= $self->{_config};
    $self->bail_out("No configuration was given to EC::AzureDevOps::Plugin\n") unless($config);


    # Check mandatory
    for my $param (qw/endpoint collection/){
        $self->bail_out("No value for configuration parameter '$param' was provided\n") unless $config->{$param};
    }

    # Strip value
    $config->{endpoint} =~ s|/+$||g;

    return "$config->{endpoint}/$config->{collection}";
}

1;