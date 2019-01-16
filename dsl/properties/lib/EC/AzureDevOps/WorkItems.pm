package EC::AzureDevOps::WorkItems;

use strict;
use warnings;

sub collect_tree_ids {
    my ($parsed) = @_;

    my $relations = $parsed->{workItemRelations};
    return [] unless $relations;

    my @ids = ();
    for my $rel (@$relations) {
        push @ids, $rel->{target}->{id};
    }
    return \@ids;
}


sub collect_flat_ids {
    my ($parsed) = @_;

    my @ids = map {$_->{id}} @{$parsed->{workItems}};
    return \@ids;
}

sub collect_one_hop_ids {
    my ($parsed) = @_;

    my @ids = map {$_->{target}->{id}} @{$parsed->{workItemRelations}};
    return \@ids;
}



1;
