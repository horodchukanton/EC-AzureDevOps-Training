package EC::AzureDevOps::Plugin;
use strict;
use warnings FATAL => 'all';

use base 'EC::Plugin::Core';

use Data::Dumper;
use JSON::XS qw/decode_json encode_json/;

use EC::Plugin::Microrest;
use EC::AzureDevOps::WorkItems;

use constant {
    RESULT_PROPERTY_SHEET_FIELD => 'resultPropertySheet',
    FORBIDDEN_FIELD_NAME_PREFIX => '_'
};
use constant FORBIDDEN_FIELD_NAME_PROPERTY_SHEET => qw(acl createTime lastModifiedBy modifyTime owner propertySheetId description);


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

    my @fields = qw/config project type title priority assignTo
        description additionalFields requestBody sourceProperty
        resultPropertySheet resultFormat/;
    my $parameters = $self->get_params_as_hashref(@fields);

    $self->logger->debug("Parameters", $parameters);

    for my $required (qw/config project title type resultPropertySheet resultFormat/){
        $self->bail_out("Parameter '$required' is mandatory") unless $parameters->{$required};
    }

    my $config = $self->get_config_values($parameters->{config});

     my $client = EC::Plugin::MicroRest->new(
         url        => $self->get_base_url($config),
         auth       => $config->{auth} || 'basic',
         user       => $config->{userName},
         password   => $config->{password},
         ctype      => 'application/json-patch+json',
         encode_sub => \&encode_json,
         decode_sub => sub {
             $self->decode_json_or_bail_out(shift, "Failed to parse JSON response from $config->{endpoint}).")
         }
    );

    # Prepend $ to the type name
    my $type = ($parameters->{type} =~ /^\$/) ? $parameters->{type} : '$' . $parameters->{type};

    my $method_path = $parameters->{project} . '/_apis/wit/workitems/' . $type;
    $self->logger->debug("Path: $method_path");

    # Api version should be sent in query
    my %query = ();
    $query{'api-version'} = EC::AzureDevOps::WorkItems::get_api_version($method_path, $config);

    my @work_item_payloads = $self->build_createupdate_workitem_payloads($parameters);

    # Sending requests one by one
    my @created_items = ();
    for my $payload (@work_item_payloads){
        my $result = $client->post($method_path, \%query, $payload);
        push @created_items, $result;
    }

    my $result_property_sheet = $parameters->{resultPropertySheet};
    my $result_ids_property_name =  $result_property_sheet . '/workItemIds';
    $self->save_entities(\@created_items, $result_property_sheet, $parameters->{resultFormat}, $result_ids_property_name);

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

sub save_entities {
    my ($self, $entities_list, $result_property, $result_format, $ids_property) = @_;

    my @ids = ();
    for my $entity (@$entities_list){
        my $id = $entity->{id};
        push @ids, $id;
        $self->save_parsed_data($entity, $result_property . "/$id", $result_format)
    }

    $self->logger->info("Created work item IDs saved to a property $ids_property", );
    $self->set_property($ids_property, join(', ', @ids));

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

sub save_parsed_data {
    my ($self, $parsed_data, $result_property, $result_format) = @_;

    unless($result_format) {
        return $self->bail_out('No format has beed selected');
    }

    unless($parsed_data) {
        $self->logger->info("Nothing to save");
        return;
    }

    $self->logger->info("Got data", JSON->new->pretty->encode($parsed_data));

    if ($result_format eq 'propertySheet') {

        my $flat_map = $self->_self_flatten_map($parsed_data, $result_property, 'check_errors!');

        for my $key (sort keys %$flat_map) {
            $self->ec->setProperty($key, $flat_map->{$key});
            $self->logger->info("Saved $key -> $flat_map->{$key}");
        }
    }
    elsif ($result_format eq 'json') {
        my $json = encode_json($parsed_data);
        $json = decode('utf8', $json);
        $self->logger->trace(Dumper($json));
        $self->ec->setProperty($result_property, $json);
        $self->logger->info("Saved answer under $result_property");
    }
    elsif ($result_format eq 'file') {
        #saving data implementation is on Hooks side!
    }
    else {
        $self->bail_out("Cannot process format $result_format: not implemented");
    }
}


sub _self_flatten_map {
    my ($self, $map, $prefix, $check) = @_;

    if (defined $check and $check){
        $check = 1;
    }
    else{
        $check = 0;
    }
    $prefix ||= '';
    my %retval = ();

    for my $key (keys %$map) {

        my $value = $map->{$key};
        if (ref $value eq 'ARRAY') {
            my $counter = 1;
            my %copy = map { my $key = ref $_ ? $counter ++ : $_; $key => $_ } @$value;
            $value = \%copy;
        }
        if (ref $value ne 'HASH') {
            $value = '' unless defined $value;
            $value = "$value";
        }
        if (ref $value) {
            if ($check){
                foreach my $bad_key(FORBIDDEN_FIELD_NAME_PROPERTY_SHEET){
                    if (exists $value->{$bad_key}){
                        $self->fix_propertysheet_forbidden_key($value, $bad_key);
                    }
                }
            }

            %retval = (%retval, %{$self->_self_flatten_map($value, "$prefix/$key", $check)});
        }
        else {
            if ($check){
                foreach my $bad_key(FORBIDDEN_FIELD_NAME_PROPERTY_SHEET){
                    if ($key eq $bad_key){
                        $self->fix_propertysheet_forbidden_key(\$key, $bad_key);
                    }
                }
            }

            $retval{"$prefix/$key"} = $value;
        }
    }
    return \%retval;
}

sub fix_propertysheet_forbidden_key{
    my ($self, $ref_var, $key) = @_;

    $self->logger->info("\"$key\" is the system property name", "Prefix FORBIDDEN_FIELD_NAME_PREFIX was added to prevent failure.");
    my $new_key = FORBIDDEN_FIELD_NAME_PREFIX . $key;
    if(ref($ref_var) eq 'HASH'){
        $ref_var->{$new_key} = $ref_var->{$key};
        delete $ref_var->{$key};
    }
    elsif(ref($ref_var) eq 'SCALAR'){
        $$ref_var = $new_key;
    }
}
1;