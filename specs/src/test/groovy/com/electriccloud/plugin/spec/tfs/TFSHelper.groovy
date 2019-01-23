package com.electriccloud.plugin.spec.tfs

import com.electriccloud.plugin.spec.PluginTestHelper
import com.electriccloud.plugin.spec.http.HeaderCredentials
import com.electriccloud.plugin.spec.http.ICredentials
import com.electriccloud.plugin.spec.http.RestClient
import com.electriccloud.plugin.spec.http.RestException

import net.sf.json.JSON
import net.sf.json.JSONObject

import org.apache.http.client.methods.HttpPost
import org.apache.http.impl.client.DefaultHttpClient


class TFSHelper {
    final static String METHOD_GET = 'GET'
    final static String METHOD_POST = 'POST'
    final static String METHOD_PUT = 'PUT'
    final static String METHOD_PATCH = 'PATCH'
    final static String METHOD_DELETE = 'DELETE'

    String url

    String collectionName
    String apiVersion = '1.0'
    String projectName

    RestClient client

    TFSHelper(String url, String login, String password, String collectionName, String projectName) {
        assert url
        assert login
        assert password
        assert collectionName

        this.collectionName = collectionName
        this.projectName = projectName

        this.url = url

        // Instantiate client
        DefaultHttpClient httpclient = new DefaultHttpClient()
        ICredentials credentials = new HeaderCredentials(login, password)
        client = new RestClient(httpclient, credentials, URI.create(this.url))

    }

    void setApiVersion(String apiVersion) {
        this.apiVersion = apiVersion
    }


    boolean isAuthenticated() {
        return true
    }

    JSON getWorkItemById(def id) {
        assert id
        String path = this.collectionName + '/_apis/wit/workitems/' + id
        return request(METHOD_GET, path)
    }

    /**
     * Creates a work Item. Map keys should be the same as CreateWorkItems procedure parameters
     *
     * @param workItemParams
     * @return
     */
    JSON createWorkItem(String workItemType, Map workItemParams) {
        String path = [this.collectionName, this.projectName, '_apis/wit/workitems', "\$${workItemType}"].join("/")

        // Transforming parameter map to TFS expected JSON payload format
        def tfsWorkItems = new WorkItemFields(workItemParams)
        JSON payload = tfsWorkItems.getAsJSONPayload()

        return postWithContentType(
            path,
            ['api-version': getApiVersion()],
            payload,
            "application/json-patch+json"
        )
    }

    JSON deleteWorkItem(def workItemId) {
        String path = [this.collectionName, '_apis/wit/workitems', workItemId].join('/')
        return request(METHOD_DELETE, path)
    }

    JSON createWorkItemQuery(String name, String wiql, Map queryParams = [:], String parent = 'My Queries') {

        String path = [this.collectionName, this.projectName, '_apis/wit/queries', parent].join('/')

        JSON payload = new JSONObject([
            wiql: wiql,
            name: name,
        ])

        queryParams.each { String k, String v -> payload[k] = v }

        return request(METHOD_POST, path, [:], payload)

    }

    def deleteWorkItemQuery(String id) {
        String path = [this.collectionName, this.projectName, '_apis/wit/queries', id].join('/')

        // This request does not return the content, and request() don't likes that
        try {
            request(METHOD_DELETE, path)
        }
        catch (AssertionError ignored) {
        }

        return true
    }

    // This one has different request body for different API versions
    JSON triggerBuild(String buildDefinitionName) {
        String path = [this.collectionName, this.projectName, '_apis/build/builds'].join('/')

        int buildDefinitionId = getDefinitionIdByName(buildDefinitionName)

        Map payload = [
            'Definition': [Id: buildDefinitionId],
        ]

        JSONObject jsonPayload = JSONObject.newInstance(payload)
        JSON result = request(METHOD_POST, path, ['api-version': this.apiVersion], jsonPayload)

        assert result
        return result
    }

    JSON getBuild(int buildId){
        String path = [this.collectionName, this.projectName, '_apis/build/builds', buildId].join('/')
        return request(METHOD_GET, path, ['api-version': this.apiVersion])
    }

    JSON getFinishedBuild(int buildId, boolean wait = false, int timeout = 120) {

        JSON result = getBuild(buildId)

        if (result.status =~ /inProgress|notStarted/ && wait){
            result = waitForBuild(buildId, timeout)
        }

        assert result
        return result
    }

    JSON waitForBuild(int buildId, int timeout = 120, int waited = 0){
        assert buildId

        JSON result = getBuild(buildId)

        assert result.status
        if (waited >= timeout){
            throw new RuntimeException("Waiting for build time has exceeded timeout")
        }

        if (result.status =~ /inProgress|notStarted/){
            // Sleep thirty seconds and try again
            PluginTestHelper.logger.debug("Build is still running. Will try again in 30 seconds.")
            Thread.sleep(30 * 1000)
            return waitForBuild(buildId, timeout, waited + 30)
        }

        return result
    }

    int getEntityIdByName(String apiSearchPath, String entityName){
        assert entityName
        assert apiSearchPath

        String path = [this.collectionName, this.projectName, apiSearchPath].join('/')
        JSON searchResult = request(METHOD_GET, path, [name: entityName])

        if (searchResult.count == 0) {
            PluginTestHelper.logger.debug(searchResult.toString())
            throw new RuntimeException("Cannot find queue with name ${entityName}")
        }

        Map entity = (Map) searchResult['value'][0]
        return entity.id
    }

    int getDefinitionIdByName(String definitionName) {
        return getEntityIdByName('_apis/build/definitions', definitionName)
    }

    int getQueueIdByName(String queueName) {
        return getEntityIdByName('_apis/build/queues', queueName)
    }

    JSON postWithContentType(String path, Map queryParameters = [:], JSON payload, String contentType) {
        assert queryParameters['api-version']
        URI uri = this.client.buildURI(path, queryParameters)

        HttpPost request = new HttpPost(uri)

        println("[DEBUG] HELPER REQUEST PATH: " + uri)

        JSON result = null
        try {
            result = this.client.request(request, payload.toString(), contentType)
        } catch (RestException e) {
            println "Error happened for the request" + e.getHttpStatusCode()
            println e.getMessage()
        }
        assert result
        return result
    }

    JSON request(String method, String path, Map parameters = [:], JSON payload = null) {
        assert method
        assert path

        // Adding api-version to parameters
        parameters['api-version'] = this.apiVersion

        if (!path =~ /^\//) {
            path = '/' + path
        }

        def url_with_params = this.client.buildURI(path, parameters)

        if (payload && !(method == METHOD_PUT || method == METHOD_POST)) {
            throw new RuntimeException("Payload is implemented only for PUT and POST methods")
        }

        JSON result = null

        try {
            // Adding parameters to URI
            switch (method.toUpperCase()) {
                case METHOD_GET:
                    result = this.client.get(url_with_params)
                    break
                case METHOD_POST:
                    result = this.client.post(url_with_params, payload)
                    break
                case METHOD_PUT:
                    result = this.client.put(url_with_params, payload)
                    break
                case METHOD_PATCH:
                    throw new RuntimeException("PATCH method is not implemented.")
                    result = this.client.patch(url_with_params)
                    break
                case METHOD_DELETE:
                    result = this.client.delete(url_with_params)
                    break
            }
        } catch (RestException e) {
            println "Error happened for the request" + e.getHttpStatusCode()
            println e.getMessage()
        }

        assert result
        return result
    }


}
