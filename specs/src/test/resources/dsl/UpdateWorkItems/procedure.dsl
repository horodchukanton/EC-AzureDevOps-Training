def projName = args.projectName
def procName = 'UpdateWorkItems'

def parameters = [
    config             : '',
    workItemIds        : '',
    title              : '',
    priority           : '',
    assignTo           : '',
    description        : '',
    additionalFields   : '',
    commentBody        : '',
    resultPropertySheet: '',
    resultFormat       : ''
]

project projName, {
    procedure procName, {

        step procName, {
            description = ''
            subprocedure = procName
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
