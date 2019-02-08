
def procName = 'ValidateCRDParameters'
def stepName = 'Validate CRD Parameters'
procedure procName, description: 'Service procedure to check the parameters of a new RCC datasource', {
    property 'standardStepPicker', 'false'
    step stepName,

        command: """
\$[/myProject/scripts/preamble]
\$[/myProject/scripts/validateCRDParams]
""",
        shell: 'ec-perl'

}
