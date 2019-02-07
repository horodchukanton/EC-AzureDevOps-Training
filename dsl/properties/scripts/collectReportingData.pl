use strict;
use warnings FATAL => 'all';

use ElectricCommander;
use EC::AzureDevOps::Plugin;
use JSON;

main();
exit 0;

sub get_step_parameters {
    my ($plugin_instance) = @_;

    my $parameters = {};
    my $procedure_name = $plugin_instance->ec->getProperty('/myProcedure/name')->findvalue('//value')->string_value;
    my $xpath = $plugin_instance->ec->getFormalParameters({projectName => '@PLUGIN_NAME@', procedureName => $procedure_name});
    for my $param ($xpath->findnodes('//formalParameter')) {
        my $name = $param->findvalue('formalParameterName')->string_value;
        my $value = $plugin_instance->get_param($name);

        my $name_in_list = $name;
        if ($param->findvalue('type')->string_value eq 'credential') {
            my $cred = $plugin_instance->ec->getFullCredential($value);
            my $username = $cred->findvalue('//userName')->string_value;
            my $password = $cred->findvalue('//password')->string_value;

            $parameters->{$name_in_list . 'Username'} = $username;
            $parameters->{$name_in_list . 'Password'} = $password;
        }
        else {
            $parameters->{$name_in_list} = EC::Plugin::Core::trim_input($value);
            $plugin_instance->out(1, qq{Got parameter "$name" with value "$value"\n});
        }
    }
    return $parameters;
}

sub check_parameters {
    my ($plugin, $parameters) = @_;

    my @required = qw/config queryText project/;
    for my $parameter_name (@required){
        if (! $parameters->{$parameter_name}){
            $plugin->bail_out("No value for required parameter '$parameter_name'");
            return 0;
        }
    }

    return 1;
}

# https://docs.microsoft.com/uk-ua/rest/api/azure/devops/wit/wiql/query%20by%20wiql?view=azure-devops-rest-4.1
sub get_report_entities {
    my ($plugin, $config, $params) = @_;

    my $microrest = $plugin->get_microrest_client($config, 'application/json');

    # Defining where request should go
    my $api_path = $params->{project} . '/_apis/wit/wiql',

    # AzureDevOps specific! Hardcoded api-version
    my $api_version = '4.1';

    my $response = $microrest->post(
        $api_path,
        {
            'timePrecision' => 'true',
            'api-version' => $api_version
        },
        { query => $params->{queryText} }
    );

    $plugin->logger->debug("RESPONSE", $response);

    ## A note about AzureDevOps API response.
    #  The result of the search query does not contain
    #  items itself, but only the reference to the items
    # (**Captain Jack Sparrow with a drawing of a key goes here**)

    my @ids = map {$_->{id}} @{$response->{workItems}};
    $plugin->logger->info("IDs of the found work items: " . join(', ', @ids));

    # So now we can request the items itself
    # I'm using plugin method
    my $work_items_result = $plugin->get_work_items(\@ids, {
        config => $params->{config}
    });

    $plugin->logger->debug("WORK ITEMS RESULT", $work_items_result);

    return $work_items_result;
}

sub transform_items {
    my ($plugin, $items) = @_;

    return $items;
}

sub main {
    # Initialize the plugin object instance
    my $plugin = EC::AzureDevOps::Plugin->new();
    $plugin->logger->info("Hello, world");

    # Get the job parameters.
    my $params = get_step_parameters($plugin);

    # Checking the parameters
    check_parameters($plugin, $params)
      or die "Parameters check failed";

    # Get configuration values
    my $config = $plugin->get_config_values($params->{config});

    # Request the entities
    my $entities = get_report_entities($plugin, $config, $params);

    # If necessary, filter the results to exclude the duplicate items.
    ## TODO: we can specify a timestamp in the query (add a parameter?)

    # Perform additional requests to get the item fields that are not included into the first result.
    ## TODO: no need for this plugin, because we can specify the fields in a query

    # Transform the raw data to the standardized one.
    my $json_payload = transform_items($plugin, $entities);

    my $report_object_type = 'feature';

    if ($params->{preview}){
        my $beautified_payload = JSON->new->pretty->utf8()->encode($json_payload);
        $plugin->logger->info("Preview of the payload", $beautified_payload);
        $plugin->logger->info("[PREVIEW MODE] Exit without the payload sending");

        return 1;
    }

    # Send the data to EC.
    $plugin->ec->sendReportingData({payload => $json_payload, reportObjectTypeName => $report_object_type});

    return 1;
}

exit 0;