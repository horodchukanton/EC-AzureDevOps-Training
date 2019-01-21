def projName = args.projectName
def resource = args.resourceName

def procedureName = 'WriteToFile'

project projName, {
    procedure procedureName, {
        resourceName = resource

        step 'RunProcedure', {
            shell = 'ec-perl'
            command = '''
use strict;
use warnings;

my $text = q{$[text]};
my $filepath = \'$[filepath]\';

die "Filepath is required" unless ($filepath);

print $filepath . "\\n";
print $text . "\\n";

if ($^O eq 'MSWin32'){
  $filepath =~ s/\\//\\\\/g;
}

print "Substituted path to: $filepath\\n";

open (my $fh, '>', $filepath)
    or die "Can't open $filepath: $@";

print $fh $text;

exit 0;
            '''
        }

        formalParameter 'filepath', defaultValue: '', {
            type = "entry"
        }

        formalParameter 'text', defaultValue: '', {
            type = "textarea"
        }

        // Custom properties
        filepath = ''
        text = ''
    }


}