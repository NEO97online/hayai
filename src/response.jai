SetCookie :: struct {
  key       : string;
  value     : string;
  expires   : string;
  domain    : string;
  path      : string;
  same_site : string;
  secure    : bool;
  http_only : bool;
}

send_html :: (request: *Request, html: string, status_code: u16 = 200, content_type: string = "text/html", content_encoding: string = "", headers: []string = .[]) {
  // todo: status_code 404 is responding with 404 OK; lol
  
  headers_builder: String_Builder;
  init_string_builder(*headers_builder);

  if content_encoding {
    print_to_builder(*headers_builder, "\r\nContent-Encoding: %", content_encoding);
  }
  
  for header : headers {
    print_to_builder(*headers_builder, "\r\n%", header);
  }

  headers_str := builder_to_string(*headers_builder);

  http_response := tprint("HTTP/1.1 % OK\r\nContent-Length: %\r\nContent-Type: %; charset=UTF-8%\r\n\r\n%", status_code, html.count, content_type, headers_str, html);

  // print("[DEBUG] send_html response: \n%\n", tprint("HTTP/1.1 % OK\r\nContent-Length: %\r\nContent-Type: %; charset=UTF-8%\r\n\r", status_code, html.count, content_type, headers_str));

  bytes_sent := mysocket_write(request.socket, http_response);
  // print("bytes_sent: %\n", bytes_sent);
  request.response_sent = true;
}

send_json :: (request: *Request, json: string) {
  http_response := tprint("HTTP/1.1 200 OK\r\nContent-Length: %\r\nContent-Type: application/json\r\n\r\n%", json.count, json);
  mysocket_write(request.socket, http_response);
  request.response_sent = true;
}

send_redirect :: (request: *Request, redirect_to: string, status := 307, headers: []string = .[]) {
  headers_builder: String_Builder;
  init_string_builder(*headers_builder);
  for header : headers {
    print_to_builder(*headers_builder, "\r\n%", header);
  }
  headers_str := builder_to_string(*headers_builder);

  http_response := tprint("HTTP/1.1 % Temporary Redirect\r\nLocation: %\r\nContent-Length: 0%\r\n\r\n", status, redirect_to, headers_str);
  print("response: %\n", http_response);
  mysocket_write(request.socket, http_response);
  request.response_sent = true;
}