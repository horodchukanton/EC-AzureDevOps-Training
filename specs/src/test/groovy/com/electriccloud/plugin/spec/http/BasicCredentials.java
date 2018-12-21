/*
 *  This code was borrowed from JIRA client (net.rcarz.jiraclient package)
 *
 * */

package com.electriccloud.plugin.spec.http;


import org.apache.http.HttpRequest;
import org.apache.http.auth.Credentials;
import org.apache.http.auth.UsernamePasswordCredentials;
import org.apache.http.impl.auth.BasicScheme;

public class BasicCredentials implements ICredentials {
    private String username;
    private String password;

    public BasicCredentials(String username, String password) {
        this.username = username;
        this.password = password;
    }

    @Override
    public void initialize(RestClient client) throws RestException {

    }

    public void authenticate(HttpRequest req) {
        Credentials creds = new UsernamePasswordCredentials(this.username, this.password);
        new BasicScheme();
        req.addHeader(BasicScheme.authenticate(creds, "utf-8", false));
    }

    public String getLogonName() {
        return this.username;
    }

    @Override
    public void logout(RestClient client) throws RestException {

    }
}
