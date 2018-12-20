/*
 *  This code was borrowed from JIRA client (net.rcarz.jiraclient package)
 *
 * */

package com.electriccloud.plugin.spec.http;

public class RestException extends Exception {
    private int status;
    private String result;

    public RestException(String msg, int status, String result) {
        super(msg);
        this.status = status;
        this.result = result;
    }

    public int getHttpStatusCode() {
        return this.status;
    }

    public String getHttpResult() {
        return this.result;
    }

    public String getMessage() {
        return String.format("%s %s: %s", Integer.toString(this.status), super.getMessage(), this.result);
    }
}

