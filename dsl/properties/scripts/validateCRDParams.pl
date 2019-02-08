use strict;
use warnings 'FATAL' => 'all';

use EC::AzureDevOps::Plugin;

my $plugin = EC::AzureDevOps::Plugin->new();
my $params = get_step_parameters($plugin);
check_parameters($params);

exit 0;


# Procedures are copied from the collectReportingData.pl
sub check_parameters {
    my ($plugin_instance, $parameters) = @_;

    # Checking required parameters value
    # This is controlled by UI but we also have DSL and special values, like '$[]'
    my @required = qw/config/;
    for my $parameter_name (@required){
        if (! $parameters->{$parameter_name}){
            $plugin_instance->bail_out("No value for the required parameter '$parameter_name'.");
            return 0;
        }
    }

    if ( !($parameters->{queryId} || $parameters->{queryText})
        || ($parameters->{queryId} && $parameters->{queryText})
    ){
        $plugin_instance->bail_out("Either the 'Query Id' or 'Query Text' should be specified.");
    }

    return 1;
}

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
