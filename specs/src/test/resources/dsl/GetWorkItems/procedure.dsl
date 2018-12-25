def projName = args.projectName

def parameters = [
    config             : '',
    workItemIds        : '',
    fields             : '',
    asOf               : '',
    expandRelations    : '',
    resultPropertySheet: '',
    resultFormat       : '',
]

project projName, {
    procedure 'GetWorkItems', {

        step 'GetWorkItems', {
            description = ''
            subprocedure = 'GetWorkItems'
            subproject = '/plugins/EC-AzureDevOps/project'
            subpluginKey = 'EC-AzureDevOps'
            projectName = projName

            parameters.each { k, v ->
                actualParameter k, (parameters[k] ?: '$[' + k + ']')
            }

        }

        parameters.each { k, defaultValue ->
            formalParameter k, defaultValue: defaultValue, {
                type = 'textarea'
            }
        }
    }
}
