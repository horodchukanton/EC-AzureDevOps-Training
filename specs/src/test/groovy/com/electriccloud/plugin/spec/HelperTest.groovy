package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import com.electriccloud.plugin.spec.tfs.WorkItemFields
import net.sf.json.JSON

import spock.lang.*

@Stepwise
class HelperTest extends PluginTestHelper {

    @Shared
    TFSHelper azureDevOps, tfs

    @Shared
    int workItemId

    def doSetupSpec() {
        def adosApiVersion = getADOSApiVersion()
        def tfsApiVersion = getTFSApiVersion()

        azureDevOps = getADOSHelper(adosApiVersion)
        tfs = getTFSHelper(tfsApiVersion)
    }

    def "AzureDevOpsServices. CreateWorkItem"(){
        given:
        Map params = [
            title: "Spec Test Work Item",
            description: "Test description"
        ]

        when:
        JSON workItem = azureDevOps.createWorkItem('Task', params)

        // Saving id
        workItemId = workItem.id

        then:
        assert workItem.id

        assert workItem.fields

        Map resultMap = WorkItemFields.toParametersMap(workItem.fields)

        // Will get the 'params' existing keys from resultMap and then assert that values are equal
        assert resultMap.intersect(params) == params
    }

    def "AzureDevOpsServices. GetWorkItem"(){
        when:
        JSON workItem = azureDevOps.getWorkItemById(workItemId)

        then:
        assert workItem.id == workItemId
    }

    def "AzureDevOpsServices. DeleteWorkItem"(){
        when:
        JSON workItem = azureDevOps.deleteWorkItem(workItemId)

        then:
        assert workItem.id == workItemId
    }

    def "TFS. CreateWorkItem"(){
        given:
        Map params = [
            title: "Spec Test Work Item",
            description: "Test description"
        ]

        when:
        JSON workItem = tfs.createWorkItem('Task', params)
        assert workItem.id

        // Saving id
        workItemId = workItem.id

        then:
        assert workItem.fields

        Map resultMap = WorkItemFields.toParametersMap(workItem.fields)

        // Will get the 'params' existing keys from resultMap and then assert that values are equal
        assert resultMap.intersect(params) == params
    }

    def "TFS. GetWorkItem"(){
        when:
        JSON workItem = tfs.getWorkItemById(workItemId)

        then:
        assert workItem.id == workItemId
    }

    def "TFS. DeleteWorkItem"(){
        when:
        JSON workItem = tfs.deleteWorkItem(workItemId)

        then:
        assert workItem.id == workItemId
    }


}

