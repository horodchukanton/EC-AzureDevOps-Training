package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import spock.lang.*

class GetDefaultValues extends PluginTestHelper {

    static String procedureName = "GetDefaultValues"
    static String projectName = "Spec Tests $procedureName"
    static String configName = "config_${procedureName}"

    @Shared
    TFSHelper tfsClient

    /// Procedure parameters
    // Mandatory
    @Shared
    def config = configName
    @Shared
    def project = ''
    @Shared
    def workItemType = ''
    @Shared
    def resultPropertySheet = '/myJob/defaultValues'
    @Shared
    def resultFormat = 'propertySheet'

    /// Specs parameters
    @Shared
    def caseId,
        expectedSummary,
        expectedOutcome

    def doSetupSpec() {
        createConfiguration(configName)
        dslFile "dsl/$procedureName/procedure.dsl", [projectName: projectName]

        tfsClient = getClient()
        assert tfsClient
    }

    def doCleanupSpec() {
        deleteConfiguration('EC-AzureDevOps-Training', configName)
        conditionallyDeleteProject(projectName)
    }

    @Unroll
    def "#caseId. Sanity. Get Default Values"() {
        given:

        def resultJobPropertyName = 'defaultValues'
        resultPropertySheet = '/myJob/' + resultJobPropertyName
        resultFormat = 'propertySheet'

        project = getADOSProjectName()

        def procedureParams = [
            config             : configName,
            project            : project,
            workItemType       : workItemType,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat,
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)
        def jobProperties = getJobProperties(result.jobId)

        then:
        println getJobLink(result.jobId)

        assert result.outcome == 'success'

        // Simply assert we have a same type template
        Map workItemTemplate = (Map) jobProperties[resultJobPropertyName]
        assert workItemTemplate['System.WorkItemType'] == workItemType

        where:
        caseId       | workItemType
        'CHANGEME_1' | 'Feature'
        'CHANGEME_2' | 'Bug'
        'CHANGEME_3' | 'User Story'
    }


}
