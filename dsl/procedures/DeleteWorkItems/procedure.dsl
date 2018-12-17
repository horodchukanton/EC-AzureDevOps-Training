def procName = 'DeleteWorkItems'
def stepName = 'delete work items'
procedure procName, description: 'Deletes the specified work items', {

    step stepName,
        command: """
\$[/myProject/scripts/preamble]
use EC::AzureDevOps::Plugin;
EC::AzureDevOps::Plugin->new->step_delete_work_items();
""",
        errorHandling: 'failProcedure',
        exclusiveMode: 'none',
        releaseMode: 'none',
        shell: 'ec-perl',
        timeLimitUnits: 'minutes'

}
