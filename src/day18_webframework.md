# Day 18: From a socket to a Webframework

Today we will be focusing on building a webframework starting from a socket :)



## What to expect

```nim
proc main() =
    var router = newRouter()



    let loggingMiddleware = proc(request: var Request): (ref Response, bool) =
      let path = request.path
      let headers = request.headers
      echo "==============================="
      echo "from logger handler"
      echo "path: " & path
      echo "headers: " & $headers
      echo "==============================="
      return (newResponse(), true)

    let trimTrailingSlash = proc(request: var Request): (ref Response, bool) =
      let path = request.path
      if path.endswith("/"):
        request.path = path[0..^2]

      echo "==============================="
      echo "from slash trimmer "
      echo "path was : " & path
      echo "path: " & request.path
      echo "==============================="
      return (newResponse(), true)
      
    proc handleHello(req:var Request): ref Response =
      result = newResponse()
      result.code = Http200
      result.content = "hello world from handler /hello" & $req 
    router.addRoute("/hello", handleHello)

    let assertJwtFieldExists =  proc(request: var Request): (ref Response, bool) =
        echo $request.headers
        let jwtHeaderVals = request.headers.getOrDefault("jwt", @[""])
        let jwt = jwtHeaderVals[0]
        echo "================\n\njwt middleware"
        if jwt.len != 0:
          echo fmt"bye bye {jwt} "
        else:
          echo fmt"sure bye but i didn't get ur name"
        echo "===================\n\n"
        return (newResponse(), true)

    router.addRoute("/bye", handleHello, HttpGet, @[assertJwtFieldExists])
    
    proc handleGreet(req:var Request): ref Response =
      result = newResponse()
      result.code = Http200
      result.content = "generic greet" & $req 

        
    router.addRoute("/greet", handleGreet, HttpGet, @[])
    router.addRoute("/greet/:username", handleGreet, HttpGet, @[])
    router.addRoute("/greet/:first/:second/:lang", handleGreet, HttpGet, @[])

    let opts = ServerOptions(address:"127.0.0.1", port:9000.Port)
    var s = newServy(opts, router, @[loggingMiddleware, trimTrailingSlash])
    asyncCheck s.serve()
    echo "servy started..."
    runForever()
  
  main()

```

### defining a handler and wiring to to a pattern or more

```nim
    proc handleHello(req:var Request): ref Response =
      result = newResponse()
      result.code = Http200
      result.content = "hello world from handler /hello" & $req 
    router.addRoute("/hello", handleHello)

    proc handleGreet(req:var Request): ref Response =
      result = newResponse()
      result.code = Http200
      result.content = "generic greet" & $req 

    router.addRoute("/greet", handleGreet, HttpGet, @[])
    router.addRoute("/greet/:username", handleGreet, HttpGet, @[])
    router.addRoute("/greet/:first/:second/:lang", handleGreet, HttpGet, @[])


```

### defining/registering middlewares on the server globally

```nim
    let loggingMiddleware = proc(request: var Request): (ref Response, bool) =
      let path = request.path
      let headers = request.headers
      echo "==============================="
      echo "from logger handler"
      echo "path: " & path
      echo "headers: " & $headers
      echo "==============================="
      return (newResponse(), true)

    let trimTrailingSlash = proc(request: var Request): (ref Response, bool) =
      let path = request.path
      if path.endswith("/"):
        request.path = path[0..^2]

      echo "==============================="
      echo "from slash trimmer "
      echo "path was : " & path
      echo "path: " & request.path
      echo "==============================="
      return (newResponse(), true)

    var s = newServy(opts, router, @[loggingMiddleware, trimTrailingSlash])


```
    
### defining middlewares (request filters on certain routes)

```nim
    router.addRoute("/bye", handleHello, HttpGet, @[assertJwtFieldExists])
```


Sounds like a lot. Let's get to it.

## Implementation

### The big picture


```nim


proc newServy(options: ServerOptions, router:ref Router, middlewares:seq[MiddlewareFunc]): ref Servy =
  result = new Servy
  result.options = options
  result.router = router
  result.middlewares = middlewares

  result.sock = newAsyncSocket()
  result.sock.setSockOpt(OptReuseAddr, true)
```
we have a server listening on a socket/address (should be configurable) and has a router that knows which pattern should be handled by which handler and a set of middlewares to be used.


```nim
proc serve(s: ref Servy) {.async.} =
  s.sock.bindAddr(s.options.port)
  s.sock.listen()
  while true:
    let client = await s.sock.accept()
    asyncCheck s.handleClient(client)

  runForever()

```
we receive a connection and pass it to `handleClient` proc

```nim
proc handleClient(s: ref Servy, client: AsyncSocket) {.async.} =
  ## code to read request from the user
  var req = await s.parseRequestFromConnection(client)
  
  ...
  echo "received request from client: " & $req

  ## code to get the route handler
  let (routeHandler, params) = s.router.getByPath(req.path)
  req.urlParams = params
  let handler = routeHandler.handlerFunc

  ..
  ## call the handler and return response in valid http protocol format
  let resp = handler(req)
  echo "reached the handler safely.. and executing now."
  await client.send(resp.format())
  echo $req.formData

```

handleClient reads the data from the wire in [HTTP protocol](https://www.w3.org/Protocols/rfc2616/rfc2616.html) and finds the route or requested path handler and then formats a valid http response and write it on the wire.
Cool? Awesome!

### Example HTTP requests and responses

when you execute `curl httpbin.org/get -v` the following (http formatted request) is sent to `httpbin.org` webserver    
```
GET /get HTTP/1.1
Host: httpbin.org
User-Agent: curl/7.62.0-DEV
```
That is called a `Request` that has a request line `METHOD PATH HTTPVERSION` e.g `GET /get HTTP/1.1`. Followed by a list of headers `lines with colon in it` representing key values 
e.g 
- `Host: httpbin.org` a header is a line of `Key: value`
- `User-Agent: curl/7.62.0-DEV` a header indicating the client type 

As soon as the server receives that request it'll handle it as it was told to
```
HTTP/1.1 200 OK
Content-Type: application/json
Date: Mon, 21 Oct 2019 18:28:13 GMT
Server: nginx
Content-Length: 206

{
  "args": {}, 
  "headers": {
    "Accept": "*/*", 
    "Host": "httpbin.org", 
    "User-Agent": "curl/7.62.0-DEV"
  }, 
  "origin": "197.52.178.58, 197.52.178.58", 
  "url": "https://httpbin.org/get"
}

```
This is called a Response, response consists of 
- status line: `HTTPVER STATUS_CODE STATUS_MESSAGE` e.g `HTTP/1.1 200 OK`
- list of headers
  - `Content-Type`: `application/json` type of content 
  - `Date`: `Mon, 21 Oct 2019 18:28:13 GMT` date of the response
  - `Server`: nginx `server name`
  - `Content-Length`: 206 length of the upcoming body

Now let's go over the abstractions needed

### Http Version
There're multiple http specifications `0.9`, `1.0`, `1.1`, .. 

so let's start with that. a Simple enum should be enough

```nim
type
  HttpVersion* = enum
    HttpVer11,
    HttpVer10


proc `$`(ver:HttpVersion): string = 
      case ver
      of HttpVer10: result="HTTP/1.0"
      of HttpVer11: result="HTTP/1.1"


```

### HttpMethods

We all know `GET`, `POST`, `HEAD`, .. methods, again can be represented by a Simple enum
```nim
type
  HttpMethod* = enum  ## the requested HttpMethod
    HttpHead,         ## Asks for the response identical to the one that would
                      ## correspond to a GET request, but without the response
                      ## body.
    HttpGet,          ## Retrieves the specified resource.
    HttpPost,         ## Submits data to be processed to the identified
                      ## resource. The data is included in the body of the
                      ## request.
    HttpPut,          ## Uploads a representation of the specified resource.
    HttpDelete,       ## Deletes the specified resource.
    HttpTrace,        ## Echoes back the received request, so that a client
                      ## can see what intermediate servers are adding or
                      ## changing in the request.
    HttpOptions,      ## Returns the HTTP methods that the server supports
                      ## for specified address.
    HttpConnect,      ## Converts the request connection to a transparent
                      ## TCP/IP tunnel, usually used for proxies.
    HttpPatch         ## Applies partial modifications to a resource.



proc httpMethodFromString(txt: string):  Option[HttpMethod] = 
    let s2m = {"GET": HttpGet, "POST": HttpPost, "PUT":HttpPut, "PATCH": HttpPatch, "DELETE": HttpDelete, "HEAD":HttpHead}.toTable
    if txt in s2m:
        result = some(s2m[txt.toUpper])
    else:
        result = none(HttpMethod)
```
Also we add `httpMethodFromString` that takes a string and returns option[HttpMethod] value.

### Http Code
HTTP specifications specifies certain code responses (status codes) to indicate the state for the request

- 20X -> it's fine
- 30X -> redirections
- 40X -> client messed up
- 50X -> server messed up


```nim

  HttpCode* = distinct range[0 .. 599]

const
  Http200* = HttpCode(200)
  Http201* = HttpCode(201)
  Http202* = HttpCode(202)
  Http203* = HttpCode(203)
  ...
  Http300* = HttpCode(300)
  Http301* = HttpCode(301)
  Http302* = HttpCode(302)
  Http303* = HttpCode(303)
  ..
  Http400* = HttpCode(400)
  Http401* = HttpCode(401)
  Http403* = HttpCode(403)
  Http404* = HttpCode(404)
  Http405* = HttpCode(405)
  Http406* = HttpCode(406)
  ...
  Http451* = HttpCode(451)
  Http500* = HttpCode(500)
  ...


proc `$`*(code: HttpCode): string =
    ## Converts the specified ``HttpCode`` into a HTTP status.
    ##
    ## For example:
    ##
    ##   .. code-block:: nim
    ##       doAssert($Http404 == "404 Not Found")
    case code.int
    ..
    of 200: "200 OK"
    of 201: "201 Created"
    of 202: "202 Accepted"
    of 204: "204 No Content"
    of 205: "205 Reset Content"
    ...
    of 301: "301 Moved Permanently"
    of 302: "302 Found"
    of 303: "303 See Other"
    ..
    of 400: "400 Bad Request"
    of 401: "401 Unauthorized"
    of 403: "403 Forbidden"
    of 404: "404 Not Found"
    of 405: "405 Method Not Allowed"
    of 406: "406 Not Acceptable"
    of 408: "408 Request Timeout"
    of 409: "409 Conflict"
    of 410: "410 Gone"
    of 411: "411 Length Required"
    of 413: "413 Request Entity Too Large"
    of 414: "414 Request-URI Too Long"
    of 415: "415 Unsupported Media Type"
    of 416: "416 Requested Range Not Satisfiable"
    of 429: "429 Too Many Requests"
    ...
    of 500: "500 Internal Server Error"
    of 501: "501 Not Implemented"
    of 502: "502 Bad Gateway"
    of 503: "503 Service Unavailable"
    of 504: "504 Gateway Timeout"
    ...
    else: $(int(code))

```

the code above is taken from `pure/http` in nim stdlib


### headers

another abstraction we need is the headers list. Headers in http aren't just key=value, but key=[value] so key can has a list of values. 

```nim
type HttpHeaders* = ref object
      table*: TableRef[string, seq[string]]

type HttpHeaderValues* =  seq[string]

proc newHttpHeaders*(): HttpHeaders =
  new result
  result.table = newTable[string, seq[string]]()

proc newHttpHeaders*(keyValuePairs:
    seq[tuple[key: string, val: string]]): HttpHeaders =
  var pairs: seq[tuple[key: string, val: seq[string]]] = @[]
  for pair in keyValuePairs:
    pairs.add((pair.key.toLowerAscii(), @[pair.val]))
  new result
  result.table = newTable[string, seq[string]](pairs)

proc `$`*(headers: HttpHeaders): string =
  return $headers.table

proc clear*(headers: HttpHeaders) =
  headers.table.clear()

proc `[]`*(headers: HttpHeaders, key: string): HttpHeaderValues =
  ## Returns the values associated with the given ``key``. If the returned
  ## values are passed to a procedure expecting a ``string``, the first
  ## value is automatically picked. If there are
  ## no values associated with the key, an exception is raised.
  ##
  ## To access multiple values of a key, use the overloaded ``[]`` below or
  ## to get all of them access the ``table`` field directly.
  return headers.table[key.toLowerAscii].HttpHeaderValues

# converter toString*(values: HttpHeaderValues): string =
#   return seq[string](values)[0]

proc `[]`*(headers: HttpHeaders, key: string, i: int): string =
  ## Returns the ``i``'th value associated with the given key. If there are
  ## no values associated with the key or the ``i``'th value doesn't exist,
  ## an exception is raised.
  return headers.table[key.toLowerAscii][i]

proc `[]=`*(headers: HttpHeaders, key, value: string) =
  ## Sets the header entries associated with ``key`` to the specified value.
  ## Replaces any existing values.
  headers.table[key.toLowerAscii] = @[value]

proc `[]=`*(headers: HttpHeaders, key: string, value: seq[string]) =
  ## Sets the header entries associated with ``key`` to the specified list of
  ## values.
  ## Replaces any existing values.
  headers.table[key.toLowerAscii] = value

proc add*(headers: HttpHeaders, key, value: string) =
  ## Adds the specified value to the specified key. Appends to any existing
  ## values associated with the key.
  if not headers.table.hasKey(key.toLowerAscii):
    headers.table[key.toLowerAscii] = @[value]
  else:
    headers.table[key.toLowerAscii].add(value)

proc del*(headers: HttpHeaders, key: string) =
  ## Delete the header entries associated with ``key``
  headers.table.del(key.toLowerAscii)

iterator pairs*(headers: HttpHeaders): tuple[key, value: string] =
  ## Yields each key, value pair.
  for k, v in headers.table:
    for value in v:
      yield (k, value)

proc contains*(values: HttpHeaderValues, value: string): bool =
  ## Determines if ``value`` is one of the values inside ``values``. Comparison
  ## is performed without case sensitivity.
  for val in seq[string](values):
    if val.toLowerAscii == value.toLowerAscii: return true

proc hasKey*(headers: HttpHeaders, key: string): bool =
  return headers.table.hasKey(key.toLowerAscii())

proc getOrDefault*(headers: HttpHeaders, key: string,
    default = @[""].HttpHeaderValues): HttpHeaderValues =
  ## Returns the values associated with the given ``key``. If there are no
  ## values associated with the key, then ``default`` is returned.
  if headers.hasKey(key):
    return headers[key]
  else:
    return default

proc len*(headers: HttpHeaders): int = return headers.table.len

proc parseList(line: string, list: var seq[string], start: int): int =
  var i = 0
  var current = ""
  while start+i < line.len and line[start + i] notin {'\c', '\l'}:
    i += line.skipWhitespace(start + i)
    i += line.parseUntil(current, {'\c', '\l', ','}, start + i)
    list.add(current)
    if start+i < line.len and line[start + i] == ',':
      i.inc # Skip ,
    current.setLen(0)

proc parseHeader*(line: string): tuple[key: string, value: seq[string]] =
  ## Parses a single raw header HTTP line into key value pairs.
  ##
  ## Used by ``asynchttpserver`` and ``httpclient`` internally and should not
  ## be used by you.
  result.value = @[]
  var i = 0
  i = line.parseUntil(result.key, ':')
  inc(i) # skip :
  if i < len(line):
    i += parseList(line, result.value, i)
  elif result.key.len > 0:
    result.value = @[""]
  else:
    result.value = @[]
```

So we have the abstraction now over the headers. very nice.

### Request

```nim
type Request = object 
  httpMethod*: HTTPMethod
  httpVersion*: HttpVersion
  headers*: HTTPHeaders
  path*: string
  body*: string
  queryParams*: TableRef[string, string]
  formData*: TableRef[string, string]
  urlParams*: TableRef[string, string]
```
request is a type that keeps track of 
- http version: from the client request
- request method: get, post, .. etc
- requested path: if the url is `localhost:9000/users/myfile` the requested path would be `/users/myfile`
- headers: request headers
- body: body
- formData: submitted form data
- queryParams: if the url is `/users/search?name=xmon&age=50` the queryParams will be Table {"name":"xmon", "age":50}
- urlParams: are the captured variables by the router 
  if we have a route to handle `/users/:username/:language` and we received request with path `/users/xmon/ar` it will bind `username` to `xmon` and `language` to `ar` and make that available on the request object to be used later on by the handler.

#### Building the request

remember the `handleClient` that we mentioned in the big picture section?

```nim

proc handleClient(s: ref Servy, client: AsyncSocket) {.async.} =
  var req = await s.parseRequestFromConnection(client)
  ...
```
So let's implement `parseRequestFromConnection`


```nim


proc parseRequestFromConnection(s: ref Servy, conn:AsyncSocket): Future[Request] {.async.} = 

    result.queryParams = newTable[string, string]()
    result.formData = newTable[string, string]()
    result.urlParams = newTable[string, string]()

    let requestline = $await conn.recvLine(maxLength=maxLine)
    var  meth, path, httpver: string
    var parts = requestLine.splitWhitespace()
    meth = parts[0]
    path = parts[1]
    httpver = parts[2]
    var contentLength = 0
    echo meth, path, httpver
    let m = httpMethodFromString(meth)
    if m.isSome:
        result.httpMethod = m.get()
    else:
        echo meth
        raise newException(OSError, "invalid httpmethod")
    if "1.1" in httpver:
        result.httpVersion = HttpVer11
    elif "1.0" in httpver:
        result.httpVersion = HttpVer10
  
    result.path = path

    if "?" in path:
      # has query params
      result.queryParams = parseQueryParams(path) 
    
```
First we parse the request line `METHOD PATH HTTPVER` e.g `GET /users HTTP/1.1` so if we split on spaces we get the method, path, and http version

Also if there's `?` like in `/users?username=xmon` in the request path, we should parse the Query Parameters

```nim

proc parseQueryParams(content: string): TableRef[string, string] =
  result = newTable[string, string]()
  var consumed = 0
  if "?" notin content and "=" notin content:
    return
  if "?" in content:
    consumed += content.skipUntil({'?'}, consumed)

  inc consumed # skip ? now.

  while consumed < content.len:
    if "=" notin content[consumed..^1]:
      break

    var key = ""
    var val = ""
    consumed += content.parseUntil(key, "=", consumed)
    inc consumed # =
    consumed += content.parseUntil(val, "&", consumed)
    inc consumed
    # result[decodeUrl(key)] = result[decodeUrl(val)]
    result.add(decodeUrl(key), decodeUrl(val))
    echo "consumed:" & $consumed
    echo "contentlen:" & $content.len


```

Next should be the headers


```nim
    result.headers = newHttpHeaders()


    # parse headers
    var line = ""
    line = $(await conn.recvLine(maxLength=maxLine))
    echo fmt"line: >{line}< "
    while line != "\r\n":
      # a header line
      let kv = parseHeader(line)
      result.headers[kv.key] = kv.value
      if kv.key.toLowerAscii == "content-length":
        contentLength = parseInt(kv.value[0])
      line = $(await conn.recvLine(maxLength=maxLine))
      # echo fmt"line: >{line}< "

```
We receive the headers and figure out the body length from `content-length` header to know how much to consume from the socket after we're done with the headers.


```nim
    if contentLength > 0:
      result.body = await conn.recv(contentLength)

    discard result.parseFormData()
```
Now that we know how much to consume (`contentLength`) from socket we can capture the request's body.
Notice that `parseFormData` handles the form submitted in the request, let's take a look at that next.

##### Submitting data.

In HTTP there are different `Content-Type(s)` to submit (post) data: `application/x-www-form-urlencoded` and `multipart/form-data`.

Quoting stackoverflow [answer](https://stackoverflow.com/questions/4007969/application-x-www-form-urlencoded-or-multipart-form-data)

```
The purpose of both of those types of requests is to send a list of name/value pairs to the server. Depending on the type and amount of data being transmitted, one of the methods will be more efficient than the other. To understand why, you have to look at what each is doing under the covers.

For application/x-www-form-urlencoded, the body of the HTTP message sent to the server is essentially one giant query string -- name/value pairs are separated by the ampersand (&), and names are separated from values by the equals symbol (=). An example of this would be: 

MyVariableOne=ValueOne&MyVariableTwo=ValueTwo


That means that for each non-alphanumeric byte that exists in one of our values, it's going to take three bytes to represent it. For large binary files, tripling the payload is going to be highly inefficient.

That's where multipart/form-data comes in. With this method of transmitting name/value pairs, each pair is represented as a "part" in a MIME message (as described by other answers). Parts are separated by a particular string boundary (chosen specifically so that this boundary string does not occur in any of the "value" payloads). Each part has its own set of MIME headers like Content-Type, and particularly Content-Disposition, which can give each part its "name." The value piece of each name/value pair is the payload of each part of the MIME message. The MIME spec gives us more options when representing the value payload -- we can choose a more efficient encoding of binary data to save bandwidth (e.g. base 64 or even raw binary).
```

e.g:

If you want to send the following data to the web server:

```
name = John
age = 12
```

using `application/x-www-form-urlencoded` would be like this:
```
name=John&age=12
```
As you can see, the server knows that parameters are separated by an ampersand &. If & is required for a parameter value then it must be encoded.

So how does the server know where a parameter value starts and ends when it receives an HTTP request using multipart/form-data?

Using the boundary, similar to &.

For example:
```
--XXX
Content-Disposition: form-data; name="name"

John
--XXX
Content-Disposition: form-data; name="age"

12
--XXX--
```
[reference](https://stackoverflow.com/questions/3508338/what-is-the-boundary-in-multipart-form-data) of the above explanation



```nim

type FormPart = object
      name*: string
      headers*: HttpHeaders
      body*: string

proc newFormPart(): ref FormPart = 
  new result
  result.headers = newHttpHeaders()

proc `$`(this:ref FormPart): string = 
  result = fmt"partname: {this.name} partheaders: {this.headers} partbody: {this.body}" 

type FormMultiPart = object
  parts*: TableRef[string, ref FormPart]

proc newFormMultiPart(): ref FormMultiPart = 
  new result
  result.parts = newTable[string, ref FormPart]()

proc `$`(this: ref FormMultiPart): string = 
  return fmt"parts: {this.parts}"
```
So that's our abstraction for multipart form.

```
proc parseFormData(r: Request): ref FormMultiPart =


  discard """
received request from client: (httpMethod: HttpPost, requestURI: "", httpVersion: HTTP/1.1, headers: {"accept": @["*/*"], "content-length": @["241"], "content-type": @["multipart/form-data; boundary=------------------------95909933ebe184f2"], "host": @["127.0.0.1:9000"], "user-agent": @["curl/7.62.0-DEV"]}, path: "/post", body: "--------------------------95909933ebe184f2\c\nContent-Disposition: form-data; name=\"who\"\c\n\c\nhamada\c\n--------------------------95909933ebe184f2\c\nContent-Disposition: form-data; name=\"next\"\c\n\c\nhome\c\n--------------------------95909933ebe184f2--\c\n", raw_body: "", queryParams: {:})
  """

  result = newFormMultiPart()
  
  let contenttype = r.headers.getOrDefault("content-type")[0]
  let body = r.body
  
  if "form-urlencoded" in contenttype.toLowerAscii():
    # query params are the post body
    let postBodyAsParams = parseQueryParams(body)
    for k, v in postBodyAsParams.pairs:
      r.queryParams.add(k, v)     

```
if the content-type has the word `form-urlencoded` we parse he body as if it was queryParams

```nim

  elif contenttype.startsWith("multipart/") and "boundary" in contenttype:
    var boundaryName = contenttype[contenttype.find("boundary=")+"boundary=".len..^1]
    echo "boundayName: " & boundaryName
    for partString in body.split(boundaryName & "\c\L"):
      var part = newFormPart()
      var partName = ""

      var totalParsedLines = 1
      let bodyLines = body.split("\c\L")[1..^1] # at the boundary line
      for line in bodyLines:
        if line.strip().len != 0:
          let splitted = line.split(": ")
          if len(splitted) == 2:
            part.headers.add(splitted[0], splitted[1])
          elif len(splitted) == 1:
            part.headers.add(splitted[0], "")
          
          if "content-disposition" in line.toLowerAscii and "name" in line.toLowerAscii:
            # Content-Disposition: form-data; name="next"
            var consumed = line.find("name=")+"name=".len
            discard line.skip("\"", consumed) 
            inc consumed
            consumed += line.parseUntil(partName, "\"", consumed)

        else:
          break # done with headers now for the body.

        inc totalParsedLines
      
      let content = join(bodyLines[totalParsedLines..^1], "\c\L")
      part.body = content
      part.name = partName
      result.parts.add(partName, part)
      echo $result.parts

```
if it's not `form-urlencoded` then it's a multipart then we need to figure out the boundary and split the body on that boundary text


### Response
Now that we can parse the client request we need to be able to build a correctly formatted response.
Response keeps track of 
- http version
- response status code
- response content
- response headers

```nim
type Response = object
  headers: HttpHeaders
  httpver: HttpVersion
  code: HttpCode
  content: string
```


#### Formatting response


```nim

proc formatStatusLine(code: HttpCode, httpver: HttpVersion) : string =
  return fmt"{httpver} {code}" & "\r\n"

```
Here we build status line which is `HTTPVERSION STATUS_CODE STATUS_MSG\r\n` e.g `HTTP/1.1 200 OK`

```nim
proc formatResponse(code:HttpCode, httpver:HttpVersion, content:string, headers:HttpHeaders): string = 
  result &= formatStatusLine(code, httpver)
  if headers.len > 0:
    for k,v in headers.pairs:
      result &= fmt"{k}: {v}" & "\r\n"
  result &= fmt"Content-Length: {content.len}" & "\r\n\r\n"
  result &= content
  echo "will send"
  echo result
  

proc format(resp: ref Response) : string = 
  result = formatResponse(resp.code, resp.httpver, resp.content, resp.headers)


```

To format a complete response we need
- building status line
- headers to string
- content length to be the length for the body
- the body itself


### Handling client request
so every handler function should take a `Request` object and return a Response to be sent on the wire. Right? 

```nim


proc handleClient(s: ref Servy, client: AsyncSocket) {.async.} =
  var req = await s.parseRequestFromConnection(client)
  ...
  let (routeHandler, params) = s.router.getByPath(req.path)
  req.urlParams = params
  let handler = routeHandler.handlerFunc
  ...
  let resp = handler(req)
  await client.send(resp.format())

```
Very cool the router will magically return to us a suitable route handler or 404 handler if not found using its `getByPath` proc

- We get the handler
- apply it to the request to get a valid http response
- send the response to the client on the wire.


Let's get to the Handler Function example definition again
```nim

    proc handleHello(req:var Request): ref Response =
      result = newResponse()
      result.code = Http200
      result.content = "hello world from handler /hello" & $req 
```
so it takes a request and returns a response, how about we create an alias for that?

```nim
type HandlerFunc = proc(req: var Request):ref Response {.nimcall.}
```

### Middlewares
It's typical in many frameworks to apply certain set of checks or functions on the incoming request before sending it to any handler, like logging the request first, or trimming the trailing slashes, or checking for a certain header

How can we implement that? Remember our `handleClient`? they need to be applied before the request reach the handler so should be above `handler(req)`

```nim

proc handleClient(s: ref Servy, client: AsyncSocket) {.async.} =
  var req = await s.parseRequestFromConnection(client)
  ### HERE SHOULD BE MIDDLEWARE Code
  ###
  ###


  let (routeHandler, params) = s.router.getByPath(req.path)
  req.urlParams = params
  let handler = routeHandler.handlerFunc
  ...
  let resp = handler(req)
  await client.send(resp.format())
```
So let's get to the implementation

```nim

proc handleClient(s: ref Servy, client: AsyncSocket) {.async.} =
  var req = await s.parseRequestFromConnection(client)
  
  for  m in s.middlewares:
    let (resp, usenextmiddleware) = m(req)
    if not usenextmiddleware:
      echo "early return from middleware..."
      await client.send(resp.format())
      return
  ...
  let handler = routeHandler.handlerFunc
  ...
  let resp = handler(req)
  await client.send(resp.format())

```
here we loop over all registered middlewares
- middleware should return a response to be sent if it needs to terminate the handling immediately
- should tell us if we should continue applying middlewares or terminate immediately

That's why the definition of a middleware is like that

```nim

    let loggingMiddleware = proc(request: var Request): (ref Response, bool) =
      let path = request.path
      let headers = request.headers
      echo "==============================="
      echo "from logger handler"
      echo "path: " & path
      echo "headers: " & $headers
      echo "==============================="
      return (newResponse(), true)

```

Let's create an alias for middleware function so we can use it easily in the rest of our code

```nim
type MiddlewareFunc = proc(req: var Request): (ref Response, bool) {.nimcall.}
```


#### Route specific middlewares

above we talked about global application middlewares, but maybe we want to apply some middleware or `filter` to a certain route

```nim

proc handleClient(s: ref Servy, client: AsyncSocket) {.async.} =
  var req = await s.parseRequestFromConnection(client)
  
  
  for  m in s.middlewares:
    let (resp, usenextmiddleware) = m(req)
    if not usenextmiddleware:
      echo "early return from middleware..."
      await client.send(resp.format())
      return

  echo "received request from client: " & $req

  let (routeHandler, params) = s.router.getByPath(req.path)
  req.urlParams = params
  let handler = routeHandler.handlerFunc
  let middlewares = routeHandler.middlewares
  
  

  for  m in middlewares:
    let (resp, usenextmiddleware) = m(req)
    if not usenextmiddleware:
      echo "early return from route middleware..."
      await client.send(resp.format())
      return
    
  let resp = handler(req)
  echo "reached the handler safely.. and executing now."
  await client.send(resp.format())
  echo $req.formData


```
notice now we have a route specific middlewares to apply as well before calling `handler(req)` maybe to check for a header before allowing access on that route.


### Router
Router is one of the essential components in our code it's responsible to keep track of what the registered pattern and their handlers so we can actually do something with incoming request and the filters `middlewares` to apply on the request


```nim

type RouterValue = object
  handlerFunc: HandlerFunc
  middlewares:seq[MiddlewareFunc]

type Router = object
  table: TableRef[string, RouterValue]

```
Basic definition of the router as it's a map from a `url pattern` to `RouterValue` that basically has a reference to the handler proc and a sequence of middlewares/filters


```nim
proc newRouter(): ref Router =
  result = new Router
  result.table = newTable[string, RouterValue]()
```
Initializing the router

```nim
proc handle404(req: var Request): ref Response  = 
  var resp = newResponse()
  resp.code = Http404
  resp.content = fmt"nothing at {req.path}"
  return resp
```
Simple 404 handler in case that we don't find a handler for the requested path


```nim
proc getByPath(r: ref Router, path: string, notFoundHandler:HandlerFunc=handle404) : (RouterValue, TableRef[string, string]) =
  var found = false
  if path in r.table: # exact match
    return (r.table[path], newTable[string, string]())

  for handlerPath, routerValue in r.table.pairs:
    echo fmt"checking handler:  {handlerPath} if it matches {path}" 
    let pathParts = path.split({'/'})
    let handlerPathParts = handlerPath.split({'/'})
    echo fmt"pathParts {pathParts} and handlerPathParts {handlerPathParts}"

    if len(pathParts) != len(handlerPathParts):
      echo "length isn't ok"
      continue
    else:
      var idx = 0
      var capturedParams = newTable[string, string]()

      while idx<len(pathParts):
        let pathPart = pathParts[idx]
        let handlerPathPart = handlerPathParts[idx]
        echo fmt"current pathPart {pathPart} current handlerPathPart: {handlerPathPart}"

        if handlerPathPart.startsWith(":") or handlerPathPart.startsWith("@"):
          echo fmt"found var in path {handlerPathPart} matches {pathPart}"
          capturedParams[handlerPathPart[1..^1]] = pathPart
          inc idx
        else:
          if pathPart == handlerPathPart:
            inc idx
          else:
            break

        if idx == len(pathParts):
          found = true
          return (routerValue, capturedParams)

  if not found:
    return (RouterValue(handlerFunc:notFoundHandler, middlewares: @[]), newTable[string, string]())
```
Here we search for pattern registered in the router for exact match or if it has varialbes we and capture their values
e.g: `/users/:name/:lang` pattern matches the request `/users/xmon/ar` and creates env `Table` with `{"name":"xmon", "lang":"ar"}`

- `/mywebsite/homepage` pattern matches /mywebsite/homepage
- `/blogs/:username` pattern` matches the path `/blogs/xmon` and `/blogs/ahmed` so it capture the env with variable name `username` and variable value `xmon` or `ahmed` and returns
- when we found the suitable handler and its env we set the env on the request on `urlParams` field and call the handler on the updated request.
Remember our `handleClient` proc?

```nim

proc handleClient(s: ref Servy, client: AsyncSocket) {.async.} =
  var req = await s.parseRequestFromConnection(client)
  
  ## Global middlewares
  ## ..
  ## ..

  let (routeHandler, params) = s.router.getByPath(req.path)
  req.urlParams = params
  let handler = routeHandler.handlerFunc

  ## Route middlewares.
  ## ..
  ## ..
  let resp = handler(req)
  await client.send(resp.format())

```


```nim
proc addHandler(router: ref Router, route: string, handler: HandlerFunc, httpMethod:HttpMethod=HttpGet, middlewares:seq[MiddlewareFunc]= @[]) = 
  router.table.add(route, RouterValue(handlerFunc:handler, middlewares:middlewares))

```
we provide a simple function to add a handler to a route setting the method type and the middlewares as well on a `Router` object.



## What's next?
We didn't talk about templates, cookies, sessions, dates, sending files and for sure that's not a complete [HTTP ref](https://www.w3.org/Protocols/rfc2616/rfc2616.html) implementation by any means. [Jester](https://github.com/dom96/jester) is a great option to check.
Thank you for going through this day and please feel free to send PR or open issue on [nim-servy](https://github.com/xmonader/nim-servy/) repository 
