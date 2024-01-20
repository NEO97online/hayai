cwd: string;
the_static_folder_to_serve: string;

serve_static :: (folder: string) {
    assert(folder.count > 0, "folder to serve can't be an empty string");
    assert(the_static_folder_to_serve.count == 0, "you can't currently static serve more than 1 folder");

    cwd = copy_string(get_working_directory());
    the_static_folder_to_serve = folder;

    get("*", (request: *Request) {
        // if the path ends wht a / then we consider it a folder, and we'll add index.html to the end of the path to load that.
        path: string;
        if ends_with(request.path, "/") {
            path = join(cwd, "/", the_static_folder_to_serve, request.path, "index.html",, temp);
        } else {
            path = join(cwd, "/", the_static_folder_to_serve, request.path,, temp);
        }

        send_file(request, path);
    });
}


// when we cache a file, we store both the raw content and also the brotli compressed version of it
File_Cache_Record :: struct {rawcontent: string; brotli: string; }
file_cache: Table(string, File_Cache_Record);

file_cache_get_or_create :: (filename: string) -> File_Cache_Record, bool {

    #if false && OS != .WINDOWS { // don't actually cache files on windows. for better development experience
        record, found := table_find(*file_cache, filename);
        if found then return record, true;
    }

    filetext, success := read_entire_file(filename);
    if !success return .{}, false;


    // just incase filename is in temporary storage
    // we have to leak a copy of it here to store in the table that won't turn to garbage
    filename_allocated := copy_string(filename);
    file_cache_record := table_set(*file_cache, filename_allocated, .{});
    file_cache_record.rawcontent = filetext;

    content_type := extension2contenttype(filename);
    is_filecontent_text := find_index_from_left("content_type", "text/") == 0;

    #import,dir "../modules/brotli";
    compressed := ifx is_filecontent_text then brotli_compress_text(filetext) else brotli_compress(filetext);
    file_cache_record.brotli = compressed;

    return file_cache_record, true;
}


send_file :: (request: *Request, raw_filename: string) {
    filename := normalize_filename(raw_filename);

    print("sending file: %\n", filename);

    file_cache_record, success := file_cache_get_or_create(filename);
    if !success {
        print("[ERROR] failed to send file: %\n", filename);
        return;
    }

    // for very small files, it's possible that brotli encoding is longer than the raw content.
    // in that case the brotli api will return the brotli encoding as ""
    // and so we will return the raw content instead, even though the client accepts br encoding
    are_we_returning_br := false;//does_request_accept_encoding(request, "br") && file_cache_record.brotli != "";

    content := ifx are_we_returning_br then file_cache_record.brotli else file_cache_record.rawcontent;
    content_encoding := ifx are_we_returning_br then "br" else "";
    content_type := extension2contenttype(filename);
    print("successfully sending file\n");
    send_html(request, content, content_type=content_type, content_encoding=content_encoding);
}


extension2contenttype :: (filename: string) -> string {
    index_of_dot := find_index_from_right(filename, ".");
    if index_of_dot == -1 return "text/html";

    extension: string;
    extension.data = filename.data + index_of_dot;
    extension.count = filename.count - index_of_dot;

    if extension == {
        case ".css";  return "text/css";
        case ".js";   return "text/javascript";
        case ".mps";  return "audio/mpeg";
        case ".png";  return "image/png";
        case ".webm"; return "video/webm";
        case ".webp"; return "image/webp";
        case ".gif";  return "image/gif";
        case ".ico";  return "image/x-icon";
        case ".jpg";  return "image/jpeg";
        case ".jpeg"; return "image/jpeg";
        case ".ini";  return "text/plain";
        case ".txt";  return "text/plain";
    }

    return "text/html";
}

normalize_filename :: (raw_filename: string) -> string {
    filename := raw_filename;

    { // strip questionmark from filename if it exists ex: main.js?293849203
        questionmark_location_in_filename := find_index_from_left(filename, #char "?");
        if questionmark_location_in_filename != -1 {
            filename.count = questionmark_location_in_filename;
        }
    }

    { // replace %xx with xx conveted to a hex byte
        start_index := 0;
        while true {
            percent_location_in_filename := find_index_from_left(filename, #char "%", start_index);
            percent_escape_exists := percent_location_in_filename != -1;
            if !percent_escape_exists break;
            // todo check that there's actually 2 hex chars after the percent
            // ^ this probably can currently crash the server
            // todo make sure it's valid hex? not sure how this should be handled if it's not? probably just ignored?
            hex_chars := substr(filename, percent_location_in_filename + 1, 2);
            string_byte := hex_chars_to_byte(hex_chars);

            filename.data[percent_location_in_filename] = string_byte;
            copy_starting_from := percent_location_in_filename + 1 + 2;
            memcpy(filename.data + percent_location_in_filename + 1, filename.data + copy_starting_from, filename.count-copy_starting_from);
            filename.count -= 2;

            start_index = percent_location_in_filename + 1;
        }
    }

    return filename;
}