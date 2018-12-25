package com.electriccloud.plugin.spec

import spock.lang.*
import com.electriccloud.plugin.spec.tfs.TFSHelper

class GetWorkItems extends PluginTestHelper {

    static String procedureName = "GetWorkItems"
    static String projectName = "Spec Tests $procedureName"
    static String configName = "config_${procedureName}"

    @Shared
    TFSHelper tfsClient

    /// Procedure parameters
    // Mandatory
    @Shared
    def workItemIds = ''
    @Shared
    def resultPropertySheet = '/myJob/workItems'
    @Shared
    def resultFormat = 'json'

    //Optional
    @Shared
    def fields = ''
    @Shared
    def asOf = ''
    @Shared
    def expandRelations = ''

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
//        deleteConfiguration('EC-AzureDevOps', configName)
        conditionallyDeleteProject(projectName)
    }

    @Unroll
    def "#caseId. Sanity"() {
        given:
        resultPropertySheet = '/myJob/workItems'
        resultFormat = 'propertySheet'

        def createdWorkItems = createWorkItems(count)
        def workItemIds = createdWorkItems.collect({ it -> it.id })
        String workItemIdsStr = workItemIds.join(",")

        def procedureParams = [
            config             : configName,
            workItemIds        : workItemIdsStr,
            fields             : fields,
            asOf               : asOf,
            expandRelations    : expandRelations,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat,
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        println getJobLink(result.jobId)

        assert result.outcome == 'success'
        def summary = getJobUpperStepSummary(result.jobId)
        assert summary == expectedSummary

        // check that list contains IDS that was passed
        def resultIdsStr = getJobProperty("$resultPropertySheet/workItemIds", result.jobId)
        def resultIdsArr = resultIdsStr.split(', ')

        def resultIdsArrList = new ArrayList(resultIdsArr.size())
        resultIdsArrList.addAll(resultIdsArr)

        assert arrEquals(resultIdsArrList, workItemIds)

        cleanup:
        if (workItemIds.size()) {
            workItemIds.each({ id ->
                tfsClient.deleteWorkItem(id)
            })
        }

        where:
        caseId | count | expectedSummary
        'CHANGEME_1'    | 1     | 'Work items are saved to a property sheet.'
        'CHANGEME_2'    | 2     | 'Work items are saved to a property sheet.'
    }

    @Unroll
    def "#caseId. Warning"() {
        given:
        resultPropertySheet = '/myJob/workItems'
        resultFormat = 'propertySheet'

        def createdWorkItems = createWorkItems(count)
        def workItemIds = createdWorkItems.collect({ it -> it.id })

        // Adding unexisting work item's id
        def unexistingId = (workItemIds[workItemIds.size()-1]) + 1

        String workItemIdsStr = workItemIds.join(",")
        workItemIdsStr += ', ' + unexistingId

        def procedureParams = [
            config             : configName,
            workItemIds        : workItemIdsStr,
            fields             : fields,
            asOf               : asOf,
            expandRelations    : expandRelations,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat,
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        println getJobLink(result.jobId)

        assert result.outcome == 'warning'
        def summary = getJobUpperStepSummary(result.jobId)
        assert summary =~ expectedSummary

        cleanup:
        if (workItemIds.size()) {
            workItemIds.each({ id ->
                tfsClient.deleteWorkItem(id)
            })
        }

        where:
        caseId | count | expectedSummary
        'CHANGEME_1'    | 1     | /Work Item\(s\) with the following IDs were not found:/

    }
}