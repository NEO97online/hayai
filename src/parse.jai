ParseState :: enum {
    NONE;
    HASH;
    INSIDE;
}

ascii :: (num: u8) -> string #expand {
    // must be a macro or *num gets invalidated after return
    str : string = ---;
    str.count = 1;
    str.data  = *num;
    return str;
}

tprint_no_must :: (format_string: string, args: .. Any) -> string {
    builder: String_Builder;
    builder.allocator = __temporary_allocator;

    print_to_builder(*builder, format_string, ..args);

    return builder_to_string(*builder,, allocator = __temporary_allocator);
} @PrintLike

template :: (html: string, caller := #caller_code) -> string #expand {
    return #insert,scope(caller) #run parse_html(html);
}

parse_html :: (html: string) -> string {
    state := ParseState.NONE;

    template_builder: String_Builder;
    init_string_builder(*template_builder);

    code_index := 1;
    params_builder: String_Builder;
    init_string_builder(*params_builder);

    for i : 0..html.count-1 {
        if html[i] == {
            case #char "#";
                if state == .NONE {
                    state = .HASH;
                } else if state == .INSIDE {
                    print_to_builder(*params_builder, "#");
                }
            case #char "{";
                if state == .HASH {
                    state = .INSIDE;
                } else {
                    print_to_builder(*template_builder, "{");
                }
            case #char "}";
                if state == .INSIDE {
                    state = .NONE;
                    print_to_builder(*template_builder, "\%%", code_index);
                    print_to_builder(*params_builder, ",");
                    code_index += 1;
                } else {
                    print_to_builder(*template_builder, "}");
                }
            
            case;
                if state == .NONE {
                    print_to_builder(*template_builder, "%", ascii(html[i]));
                } else if state == .HASH {
                    // this was not a hash block, so we'll need to insert the missing #, plus the current char
                    print_to_builder(*template_builder, "#%", ascii(html[i]));
                    state = .NONE;
                } else if state == .INSIDE {
                    print_to_builder(*params_builder, "%", ascii(html[i]));
                }
        }
    }

    template := builder_to_string(*template_builder);
    print("template: %\n", template);

    params := builder_to_string(*params_builder);
    // print("params: %\n", params);

    if template {
        final_output := tprint(#string JAI
            tprint_no_must(#string END
%1
            END, %2);
        JAI, template, params);
        // print("final_output: %\n", final_output);
        return final_output;
    } else {
        return #string END
        "";
        END
    }
}
