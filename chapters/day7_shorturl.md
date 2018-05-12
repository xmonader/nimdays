# Day 7: Shorturl service

Today, we will develop a url shortening service like `bit.ly` or something


## imports
```nim
import jester, asyncdispatch, htmlgen, json, os, strutils, strformat, db_sqlite
```

- jester: is sinatra like framework

- asyncdispatch: for async/await instructions

- htmlgen: to generate html pages

- json: to parse json string into nim structures and dump json structures to strings

- db_sqlite: to work on sqlite databse behind our application


## Database connection
```nim
# hostname can be something configurable "http://ni.m:5000"
let hostname = "localhost:5000"
var theDb : DbConn
```

- `hostname` is the basepath for our site to access it, and can be configurable using `/etc/hosts` file or using even `reverse proxy` like `caddy`, or in real world case you will have a dns record for your site. 

- `theDb` is the connection object to work with `sqlite` database. 

```nim
if not fileExists("/tmp/mytest.db"):
  theDb = open("/tmp/mytest.db", nil, nil, nil)
  theDb.exec(sql("""create table urls (
      id   INTEGER PRIMARY KEY,
      url  VARCHAR(255) NOT NULL
     )"""
  ))
else:
  theDb = open("/tmp/mytest.db", nil, nil, nil)
```

- We check if the database file doesn't exist `/tmp/mytest.db` we create a `urls` table  otherwise we just get the connection and do nothing


## Jester and http endpoints
```nim
routes:
```

- jester defines a DSL to work on routes 

```nim
METHOD ROUTE_PATH:
    ##codeblock
```

- METHOD can be `get` `post` or any `http` verb

- ROUTE_PATH is the path accessed on the server for instance `/users`, `/user/52`, here `52` is a query parameter when route is defined  like this`/user/@id`

### HOME page

Here we handle `GET` requests on `/home` path on our server:
```nim
 get "/home":
  var htmlout = """
    <html>
      <title>NIM SHORT</title>
      <head>
        <script
      src="https://code.jquery.com/jquery-3.3.1.min.js"
      integrity="sha256-FgpCb/KJQlLNfOu91ta32o/NMZxltwRo8QtmkMRdAu8="
      crossorigin="anonymous"></script>

      <script>
        function postData(url, data) {
          // Default options are marked with *
          return fetch(url, {
            body: JSON.stringify(data), // must match 'Content-Type' header
            cache: 'no-cache', // *default, no-cache, reload, force-cache, only-if-cached
            credentials: 'same-origin', // include, same-origin, *omit
            headers: {
              'user-agent': 'Mozilla/4.0 MDN Example',
              'content-type': 'application/json'
            },
            method: 'POST', // *GET, POST, PUT, DELETE, etc.
            mode: 'cors', // no-cors, cors, *same-origin
            redirect: 'follow', // manual, *follow, error
            referrer: 'no-referrer', // *client, no-referrer
          })
          .then(resp => resp.json())
      }

      $(document).ready(function() {
        $('#btnsubmit').on('click', function(e){
          e.preventDefault();
          postData('/shorten', {url: $("#url").val()})
          .then( data => {
            let id = data["id"]
            $("#output").html(`<a href="%%hostname/${id}">Shortlink: ${id}</a>`);
           });
      });
    });
      </script>
      </head>
      <body>
          <div>
            <form>
              <label>URL</label>
              <input type="url" name="url" id="url" />
              <button id="btnsubmit" type="button">SHORT!</button
            </form>
          </div>

          <div id="output">

          </div>
      </body>
    </html>
    """
    htmlout = htmlout.replace("%%hostname", hostname)
    resp  htmlout
```

- Include jquery framework

- Create a form with in `div tag with 1 textinput to allow user to enter a url`

- override form submission to do an ajax request

- on the button shorturl click event we send a post request to `/shorten` endpoint in the background using `fetch` api and whenever we get a result we parse the json data and extract the `id` from it and put the new url in the `output` div

- `resp` to return a response to the user and it can return a `http status` too

### Shorten endpoint 

```nim
  post "/shorten":
    let url = parseJson(request.body).getOrDefault("url").getStr()
    if not url.isNilOrEmpty():
      var id = theDb.getValue(sql"SELECT id FROM urls WHERE url=?", url)
      if id.isNilOrEmpty():
        id = $theDb.tryInsertId(sql"INSERT INTO urls (url) VALUES (?)", url)
      var jsonResp = $(%*{"id": id})
      resp Http200, jsonResp
    else:
      resp Http400, "please specify url in the posted data."
```

Here we handle `POST` requests on `/shorten` endpoint 
- get the url from parsed json post data. please note that POST data is `available under request.body` `explained in the previous section` 

- if url is passed we try to check if it's there in our `urls` table, if it's there we return it, otherwise we insert it in the table.
- if the url isn't passed we return a badrequest `400` status code.

- `parseJson`: loads json from a string and you can get value using `getOrDefault` and `getStr` to get string value, there's getBool, and so on.
- `getValue` to get the id from the result of the select statement `returns the first column from the first row in the result set`

- `tryInsertId` executes insert statement and returns the id of the new row

- after successfull insertion we would like to return `json` serialized string to the user `$(%*{"id": id})`

- `%*` is a macro to convert nim struct into json node and to convert it to string we wrap `$` around it


### Shorturls redirect
```nim
  get "/@Id":
    let url = theDb.getValue(sql"SELECT url FROM urls WHERE id=?", @"Id")
    if url.isNilOrEmpty():
      resp Http404, "Don't know that url"
    else:
      redirect url
```

- Here we fetch whatever path `@Id` the user trying to access `except for /home and /shorten` and we try to get the long url for that path

- If the path is resolved to a url we `redirect` the user to to or we show an error message

- `@"Id"` gets the value of `@Id` query parameter : notice the `@` position in both situation
 
## RUN
```nim
runForever()
```
start jester webserver

Code is available here [https://gist.github.com/xmonader/d41a5c9f917eadb90d3025e7b7e748dd](https://gist.github.com/xmonader/d41a5c9f917eadb90d3025e7b7e748dd)