# hayai

HTTP web server for jai, focused on performance and simplicity.

While remaining simple, Hayai will aim to be production-ready in supporting the following features:

- HTTP
    - Methods
    - Paths, including path parameters
    - Headers
    - Query Params
    - Cookies
- HTML and JSON responses
- Compile-time HTML templating
- Serve static files
- Websockets

For now, HTTPS is not a goal for Hayai itself, since most hosts handle SSL via reverse proxy.


## Quickstart

Put this code in `/modules/hayai`, then start a http server:

```c
#import "hayai";

main :: () {
    http_listen(port=80);

    // logging middleware
    any("*", (req: *Request) {
        print("[Hayai] Incoming request: % %", req.method, req.path);
    });

    // dynamic routing
    get("/hello/:name", (req: *Request) {
        send_html(req, tprint("Hello %!", Request.get_param(req, "name")));
    });

    // serve static files from the /public folder
    serve_static("public");
}
```

## HTML Templating

Often, we want to build some HTML to send to the client. Hayai makes this easy, while doing as much as possible at compile time.

To do this, Hayai provides a `template` macro which is evaluated at compile time to generate a `tprint` statement that inserts your variables into HTML strings. This is a very simple yet effective form of templating.

To insert dynamic content into an HTML string using the `template` macro, wrap any Jai expression in `#{}`. If you use `template`, your template will be able to access anything in the scope that it is called from.

```c
// We will define a function which generates an HTML document based on a given head and body.
// This will be our base for all endpoints. Global CSS and Scripts can go here.

make_document :: (head: string, body: string) -> string {
    return template(#string __HTML
        <!doctype html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            #{head}
        </head>
        <body>
            #{body}
        </body>
        </html>
    __HTML);
}

// Next, we will set up our server with a couple of routes that send back some HTML using this templating system.

main :: () {
    http_listen(port=80);

    // dynamic routing
    get("/hello/:name", (req: *Request) {
        name := Request.get_param(req, "name");

        // for this route, the head never changes, so it can be a compile-time constant.
        head :: "<title>Greetings</title>"

        // the body is dynamic, so we'll use template to create a dynamic template.
        body := template(#string __HTML
            <main>
                <h1>Hello, #{name}!</h1>
            </main>
        __HTML);

        // now we send the final html calling make_document, which is just inserting these into the base template.
        send_html(req, make_document(head, body));
    });
}
```

Hayai is all about dealing with HTML as a bunch of strings, instead of trying to build complex data structures out of it. You can do a whole lot just by combining strings together and running `tprint` a few times instead of whatever Next.js is doing.

## What about client-side logic and scoped styles?

For client-side logic and scoped styles, there are many options. Technically nothing is stopping you from using React or something else, because this is just a web server, and you could generate bundles and send those if you want. But "hayai" means "fast", and we want to go fast. So instead of React, we endorse the following stack, which aims to maximize the amount of HTML and minimize the amount of JavaScript you have to deal with:

- [HTMX](https://htmx.org/)
    - Allows the client to be interactive over the network without replacing the entire page.
    - Solves many problems that people reach for a javascript framework to solve, while still just being HTML strings.
    - Works great with Hayai's HTML templating.

- [Alpine.js](https://alpinejs.dev/)
    - If you need a lot of client-side interactivity and dynamic changes to the DOM, this makes it easy to get there.
    - Complements HTMX by handling purely client-side non-networked changes.
    - String-friendly, its just HTML still.

- [TailwindCSS](https://tailwindcss.com/)
    - Instead of needing any kind of scoped styling, or using horrible BEM classes, Tailwind is entirely localized to the element it is written on.
    - String-friendly. Just HTML.

With these three technologies, you can achieve just about everything that you would need a complicated Next.js setup to achieve, with the same or better "developer experience". You can write "components" that encapsulate content, behavior, and styling, as simple Jai functions that return strings.

A reusable and fully customizable button component, for example, would just look like this:

```c
Button :: (
    text: string,
    type := "button",
    bg_color := "bg-primary-500",
    text_color := "text-white",
    class := "",
    attrs := "",
) -> string {
    return template(#string __HTML
        <button type="#{type}" class="rounded-md #{bg_color} #{text_color} #{class}" #{attrs}>
            #{text}
        </button>
    __HTML);
}
```

Then we could use it within other templates like so:

```c
some_page :: () -> string {
    return template(#string __HTML
        <main>
            <h1>Button example</h1>
            #{Button(
                text="Click me!",
                class="mt-8"
                attrs="onclick=\"alert('clicked!!!')\""
            )}
        </main>
    __HTML);
}

```
