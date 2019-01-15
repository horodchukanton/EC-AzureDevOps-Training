package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import com.electriccloud.plugin.spec.tfs.WorkItemFields
import net.sf.json.JSON

import spock.lang.*

@Stepwise
class TFSHelperTest extends PluginTestHelper {

    @Shared
    TFSHelper tfsClient

    @Shared
    int workItemId

    def doSetupSpec() {
        tfsClient = getClient()
    }

    def "Helper. CreateWorkItem"(){
        given:
        Map params = [
            title: "Spec Test Work Item",
            description: "Test description"
        ]

        when:
        JSON workItem = tfsClient.createWorkItem('Task', params)

        // Saving id
        workItemId = workItem.id

        then:
        assert workItem.id
        assert workItem.fields

        Map resultMap = WorkItemFields.toParametersMap(workItem.fields)

        // Will get the 'params' existing keys from resultMap and then assert that values are equal
        assert resultMap.intersect(params) == params
    }

    def "Helper. GetWorkItem"(){
        when:
        JSON workItem = tfsClient.getWorkItemById(workItemId)

        then:
        assert workItem.id == workItemId
    }

    def "Helper. DeleteWorkItem"(){
        when:
        JSON workItem = tfsClient.deleteWorkItem(workItemId)

        then:
        assert workItem.id == workItemId
    }

}

