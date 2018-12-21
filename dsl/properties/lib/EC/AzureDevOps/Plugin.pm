package EC::AzureDevOps::Plugin;
use strict;
use warnings FATAL => 'all';

use base 'EC::Plugin::Core';

use Data::Dumper;
use JSON::XS qw/decode_json encode_json/;

use EC::Plugin::Microrest;
use EC::AzureDevOps::WorkItems;

use constant {
    FORBIDDEN_FIELD_NAME_PREFIX => '_'
};
use constant FORBIDDEN_FIELD_NAME_PROPERTY_SHEET => qw(acl createTime lastModifiedBy modifyTime owner propertySheetId description);


my %MS_FIELDS_MAPPING = (
    title       => 'System.Title',
    description => 'System.Description',
    assignto    => 'System.AssignedTo',
    priority    => 'Microsoft.VSTS.Common.Priority',
    commentbody => 'System.History'
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

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        project             => { label => 'Project Name', required => 1 },
        type                => { label => 'Type', required => 1 },
        title               => { label => 'Title', required => 1 },
        priority            => { label => 'Priority', check => 'number' },
        assignTo            => { label => 'Assign To' },
        description         => { label => 'Description' },
        additionalFields    => { label => 'Additional Fields' },
        workItemsJSON       => { label => 'Work Items JSON' },
        resultPropertySheet => { label => 'Result Property Sheet', required => 1 },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(sort keys %procedure_parameters );

    $self->check_parameters($params, \%procedure_parameters);

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config);

    # Api version should be sent in query
    my $api_version = EC::AzureDevOps::WorkItems::get_api_version('/_apis/wit/workitems/', $config);

    # Reading values from the parameters
    my %generic_fields = $self->parse_generic_create_update_parameters($params);

    my @work_item_hashes = @{ $self->build_create_multi_entity_payload($params, %generic_fields) };

    # Sending requests one by one
    my @created_items = ();
    for my $work_item (@work_item_hashes) {

        # Prepending '$' to the type name and removing from hash
        my $type = ( $work_item->{type} =~ /^\$/ ) ? $work_item->{type} : '$' . $work_item->{type};
        delete $work_item->{type};

        # Building API path (includes type)
        my $api_path = $params->{project} . '/_apis/wit/workitems/' . $type;
        $self->logger->debug("API Path: $api_path");

        # Forming request payload
        my @payload = map { _generate_field_op_hash($_, $work_item->{$_}) } keys %$work_item;

        # Adding Additional fields
        if ($params->{additionalFields}){
            # Check it is JSON
            my $additional_fields_decoded = $self->decode_json_or_bail_out($params->{additionalFields}, "Failed to parse Additional Fields.");

            if (ref $additional_fields_decoded eq 'HASH'){
                push @payload, $additional_fields_decoded;
            }
            elsif (ref $additional_fields_decoded eq 'ARRAY'){
                push @payload, @$additional_fields_decoded;
            }
        }

        my $result = $client->post($api_path, { 'api-version' => $api_version }, \@payload);

        push @created_items, $result;
    }

    # Save the properties
    $self->save_result_entities(\@created_items, $params->{resultPropertySheet}, $params->{resultFormat});

    my $count = scalar(@created_items);
    my $summary = "Successfully created $count work item" . (($count > 1) ? 's' : '') . '.';

    $self->set_pipeline_summary($summary);
    $self->set_summary($summary);
}

sub step_update_work_items {
    my ( $self ) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        workItemIds         => { label => 'Work Item ID(s)', required => 1 },
        title               => { label => 'Title', required => 1 },
        priority            => { label => 'Priority', check => 'number' },
        assignTo            => { label => 'Assign To' },
        description         => { label => 'Description' },
        commentBody         => { label => 'Comment Body' },
        additionalFields    => { label => 'Additional Fields' },
        resultPropertySheet => { label => 'Result Property Sheet', required => 1 },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(sort keys %procedure_parameters);

    $self->check_parameters($params, \%procedure_parameters);

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config);

    # Api version should be sent in query
    my $api_version = EC::AzureDevOps::WorkItems::get_api_version('/_apis/wit/workitems/', $config);

    # Generating the payload from the parameters
    my %generic_fields = $self->parse_generic_create_update_parameters($params);

    $self->logger->debug("Generic parameters", \%generic_fields);

    # Sending requests one by one
    my @updated_items = ();
    for my $id (split(',\s?', $params->{workItemIds})) {
        my $api_path = '/_apis/wit/workitems/' . $id;
        $self->logger->debug("API Path: $api_path");

        my @payload = map {_generate_field_op_hash($_, $generic_fields{$_})} keys %generic_fields;

        # Adding Additional fields
        if ($params->{additionalFields}){
            # Check it is JSON
            my $additional_fields_decoded = $self->decode_json_or_bail_out($params->{additionalFields}, "Failed to parse Additional Fields.");

            if (ref $additional_fields_decoded eq 'HASH'){
                push @payload, $additional_fields_decoded;
            }
            elsif (ref $additional_fields_decoded eq 'ARRAY'){
                push @payload, @$additional_fields_decoded;
            }
        }

        $self->logger->debug("Payload", \%generic_fields);

        my $result = $client->patch($api_path, { 'api-version' => $api_version }, \@payload);
        push @updated_items, $result;
    }

    # Save the properties
    $self->save_result_entities(\@updated_items, $params->{resultPropertySheet}, $params->{resultFormat});

    my $count = scalar(@updated_items);
    my $summary = "Successfully updated $count work item" . ( ( $count > 1 ) ? 's' : '' ) . '.';

    $self->set_pipeline_summary($summary);
    $self->set_summary($summary);
}

sub step_delete_work_items {
    my ($self) = @_;

    my %procedure_parameters = (
        config              => { label => 'Configuration name', required => 1 },
        workItemIds         => { label => 'Work Item Id(s)', required => 1 },
        resultPropertySheet => { label => 'Result Property Sheet', required => 1 },
        resultFormat        => { label => 'Result Format', required => 1 },
    );

    my $params = $self->get_params_as_hashref(keys %procedure_parameters);
    $self->check_parameters($params, \%procedure_parameters);

    my $config = $self->get_config_values($params->{config});
    my $client = $self->get_microrest_client($config);

    my $api_version = EC::AzureDevOps::WorkItems::get_api_version('/_apis/wit/workitems/', $config);

    my @deleted = ();
    my @unexisting = ();
    for my $id (split(',\s?', $params->{workItemIds})){
        if ($id !~ /^\d+$/){
            $self->bail_out("$procedure_parameters{workItemIds}->{label} parameter should contain numbers.");
        }
        my $api_path = "_apis/wit/workitems/${id}";

        my $result;
        eval {
            $result = $client->delete($api_path, { 'api-version' => $api_version });
            push @deleted, $result;
            1;
        } or do {
            my ($error) = $@;

            # 404 Not found.
            if (!ref $error && $error =~ /Work item [0-9]+ does not exist/){
                $self->logger->info("Work item $id does not exist.\n");
                push @unexisting, $id;
            }
        };

    }

    # Save the properties
    $self->save_result_entities(\@deleted, $params->{resultPropertySheet}, $params->{resultFormat});

    my $count = scalar(@deleted);
    my $summary = '';

    if (@deleted){
        $summary = "Successfully deleted $count work item" . ( ( $count > 1 ) ? 's' : '' ) . '.';
    }

    if (@unexisting){
        $summary .= "\n" if (@deleted);

        $summary .= "Work item(s) " . (join(@unexisting)) . " was not found";
        $self->warning("Some work items were not found. See the job logs");
    }

    $self->set_pipeline_summary($summary);
    $self->set_summary($summary);
}

sub _generate_field_op_hash {
    my ($field_name, $field_value, $operation) = @_;

    $operation ||= 'add';

    return { op => $operation, path => '/fields/' . $MS_FIELDS_MAPPING{lc ($field_name)}, value => $field_value }
}

#@returns EC::Plugin::MicroRest
sub get_microrest_client {
    my ($self, $config) = @_;

    return EC::Plugin::MicroRest->new(
        url        => $self->get_base_url($config),
        auth       => $config->{auth} || 'basic',
        user       => $config->{userName},
        password   => $config->{password},
        ctype      => 'application/json-patch+json',
        encode_sub => \&encode_json,
        decode_sub => sub {
            $self->decode_json_or_bail_out(shift, "Failed to parse JSON response from $config->{endpoint})")
        }
    );
}

sub parse_generic_create_update_parameters {
    my ($self, $parameters) = @_;

    my %generic_fields = ();

    # Map parameters to Azure operations (Update does not contain "type" parameter)
    for my $param (qw/priority assignTo description title type commentBody/){
        $generic_fields{ lc ($param) } = $parameters->{$param} if $parameters->{$param};
    }

    return wantarray ? %generic_fields : \%generic_fields;
}

sub build_create_multi_entity_payload {
    my ($self, $parameters, %generic_fields) = @_;
    my @results = ();

    # If we have Request Body, than this is the only payload
    if ($parameters->{workItemsJSON}) {
        my $work_items_json = $parameters->{workItemsJSON};

        my $err_msg = 'Value for "Work Items JSON" should contain valid non-empty JSON array.';
        my $work_items = $self->decode_json_or_bail_out($work_items_json, $err_msg);
        $self->bail_out($err_msg) unless ref($work_items) eq 'ARRAY' && scalar @$work_items;

        my @field_params = (qw/Type Title Priority Description/, 'Assign To');

        # JSON object keys are the same as Parameter label
        # Item hash keys are the same as Parameter property names (lower cased)
        for my $predefined_work_item (@$work_items){
            my %work_item = ();

            for my $key (@field_params) {
                my $search_key = ( $key eq 'Assign To' ) ? 'assignto' :  lc($key);
                $work_item{$search_key} = $predefined_work_item->{$key} || $generic_fields{$search_key};
            }

            push @results, \%work_item;
        }
    }
    else {
        push @results, { map { $_ => $generic_fields{$_} } keys %generic_fields };
    }

    return wantarray ? @results : \@results;
}

sub save_result_entities {
    my ($self, $entities_list, $result_property, $result_format) = @_;

    my @ids = ();
    for my $entity (@$entities_list){
        my $id = $entity->{id};
        push @ids, $id;
        $self->save_parsed_data($entity, $result_property . "/$id", $result_format)
    }

    my $ids_property = $result_property . '/workItemIds';
    my $ids = join(', ', @ids);
    $self->logger->info("Work item IDs ($ids) will be saved to a property '$ids_property'.") if $ids;
    $self->ec->setProperty($ids_property, $ids);

    return 1;
}

sub save_parsed_data {
    my ($self, $parsed_data, $result_property, $result_format) = @_;

    unless($result_format) {
        return $self->bail_out('No format has been selected');
    }

    unless($parsed_data) {
        $self->logger->info("Nothing to save");
        return;
    }

    $self->logger->info("Got data", JSON->new->pretty->encode($parsed_data));
    if ($result_format eq 'none'){
        $self->logger->info("Results will not be saved to a property");
    }
    elsif ($result_format eq 'propertySheet') {

        my $flat_map = $self->_self_flatten_map($parsed_data, $result_property, 'check_errors!');

        for my $key (sort keys %$flat_map) {
            $self->logger->info("Saving $key -> $flat_map->{$key}");
            $self->ec->setProperty($key, $flat_map->{$key});
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