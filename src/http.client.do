HttpClientError error = HttpRequestDenied | HttpConnectionFailed | HttpTimeout | HttpProtocolFailed

HttpRequest {
    method [u8]
    url [u8]
    body [u8]
}

HttpResponse {
    status u16
    body [u8]
}

is_http_timeout(err HttpClientError) -> bool {
    return @eq(err, HttpTimeout)
}
