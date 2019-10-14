# Day 17: Nim-Sonic-Client: Nim and Rust can be friends!
[sonic](https://github.com/valeriansaliou/sonic)  is a fast, lightweight and schema-less search backend. It ingests search texts and identifier tuples that can then be queried against in a microsecond's time, and it's implemented in rust. Sonic can be used as a simple alternative to super-heavy and full-featured search backends such as Elasticsearch in some use-cases. It is capable of normalizing natural language search queries, auto-completing a search query and providing the most relevant results for a query. Sonic is an identifier index, rather than a document index; when queried, it returns IDs that can then be used to refer to the matched documents in an external database. We use it heavily in all of our projects currently using [python client](https://github.com/xmonader/python-sonic-client), but we are here today to talk about nim. Please make sure to check sonic website for more info on how start the server and its configurations

## What to expect ? 


### Ingest 

We should be able to push data over tcp from nim to sonic
```nim
    var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Ingest)
    echo $cl.execCommand("PING")

    echo cl.ping()
    echo cl.protocol
    echo cl.bufsize
    echo cl.push("wiki", "articles", "article-1",
                  "for the love of god hell")
    echo cl.push("wiki", "articles", "article-2",
                  "for the love of satan heaven")
    echo cl.push("wiki", "articles", "article-3",
                  "for the love of lorde hello")
    echo cl.push("wiki", "articles", "article-4",
                  "for the god of loaf helmet")
```
```
PONG
true
0
0
true
2
0
true
true
true
```


### Search

We should be able to search/complete data from nim client using sonic

```nim

    var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Search)
    echo $cl.execCommand("PING")

    echo cl.ping()
    echo cl.query("wiki", "articles", "for")
    echo cl.query("wiki", "articles", "love")
    echo cl.suggest("wiki", "articles", "hell")
    echo cl.suggest("wiki", "articles", "lo")
```
```
PONG
true
@[]
@["article-3", "article-2"]
@[]
@["loaf", "lorde", "love"]

```

## Sonic specification
If you go to their [wire protocol page](https://github.com/valeriansaliou/sonic/blob/master/PROTOCOL.md) you will find some examples using telnet. I'll copy some in the following section

### 2️⃣ Sonic Channel (uninitialized)

* `START <mode> <password>`: select mode to use for connection (either: `search` or `ingest`). The password is found in the `config.cfg` file at `channel.auth_password`.

_Issuing any other command — eg. `QUIT` — in this mode will abort the TCP connection, effectively resulting in a `QUIT` with the `ENDED not_recognized` response._

---

### 3️⃣ Sonic Channel (Search mode)

_The Sonic Channel Search mode is used for querying the search index. Once in this mode, you cannot switch to other modes or gain access to commands from other modes._

**➡️ Available commands:**

* `QUERY`: query database (syntax: `QUERY <collection> <bucket> "<terms>" [LIMIT(<count>)]? [OFFSET(<count>)]? [LANG(<locale>)]?`; time complexity: `O(1)` if enough exact word matches or `O(N)` if not enough exact matches where `N` is the number of alternate words tried, in practice it approaches `O(1)`)
* `SUGGEST`: auto-completes word (syntax: `SUGGEST <collection> <bucket> "<word>" [LIMIT(<count>)]?`; time complexity: `O(1)`)
* `PING`: ping server (syntax: `PING`; time complexity: `O(1)`)
* `HELP`: show help (syntax: `HELP [<manual>]?`; time complexity: `O(1)`)
* `QUIT`: stop connection (syntax: `QUIT`; time complexity: `O(1)`)

**⏩ Syntax terminology:**

* `<collection>`: index collection (ie. what you search in, eg. `messages`, `products`, etc.);
* `<bucket>`: index bucket name (ie. user-specific search classifier in the collection if you have any eg. `user-1, user-2, ..`, otherwise use a common bucket name eg. `generic, default, common, ..`);
* `<terms>`: text for search terms (between quotes);
* `<count>`: a positive integer number; set within allowed maximum & minimum limits;
* `<locale>`: an ISO 639-3 locale code eg. `eng` for English (if set, the locale must be a valid ISO 639-3 code; if set to `none`, lexing will be disabled; if not set, the locale will be guessed from text);
* `<manual>`: help manual to be shown (available manuals: `commands`);

_Notice: the `bucket` terminology may confuse some Sonic users. As we are well-aware Sonic may be used in an environment where end-users may each hold their own search index in a given `collection`, we made it possible to manage per-end-user search indexes with `bucket`. If you only have a single index per `collection` (most Sonic users will), we advise you use a static generic name for your `bucket`, for instance: `default`._

**⬇️ Search flow example (via `telnet`):**

```bash
T1: telnet sonic.local 1491
T2: Trying ::1...
T3: Connected to sonic.local.
T4: Escape character is '^]'.
T5: CONNECTED <sonic-server v1.0.0>
T6: START search SecretPassword
T7: STARTED search protocol(1) buffer(20000)
T8: QUERY messages user:0dcde3a6 "valerian saliou" LIMIT(10)
T9: PENDING Bt2m2gYa
T10: EVENT QUERY Bt2m2gYa conversation:71f3d63b conversation:6501e83a
T11: QUERY helpdesk user:0dcde3a6 "gdpr" LIMIT(50)
T12: PENDING y57KaB2d
T13: QUERY helpdesk user:0dcde3a6 "law" LIMIT(50) OFFSET(200)
T14: PENDING CjPvE5t9
T15: PING
T16: PONG
T17: EVENT QUERY CjPvE5t9
T18: EVENT QUERY y57KaB2d article:28d79959
T19: SUGGEST messages user:0dcde3a6 "val"
T20: PENDING z98uDE0f
T21: EVENT SUGGEST z98uDE0f valerian valala
T22: QUIT
T23: ENDED quit
T24: Connection closed by foreign host.
```

_Notes on what happens:_

* **T6:** we enter `search` mode (this is required to enable `search` commands);
* **T8:** we query collection `messages`, in bucket for platform user `user:0dcde3a6` with search terms `valerian saliou` and a limit of `10` on returned results;
* **T9:** Sonic received the query and stacked it for processing with marker `Bt2m2gYa` (the marker is used to track the asynchronous response);
* **T10:** Sonic processed search query of T8 with marker `Bt2m2gYa` and sends 2 search results (those are conversation identifiers, that refer to a primary key in an external database);
* **T11 + T13:** we query collection `helpdesk` twice (in the example, this one is heavy, so processing of results takes more time);
* **T17 + T18:** we receive search results for search queries of T11 + T13 (this took a while!);

---

### 4️⃣ Sonic Channel (Ingest mode)

_The Sonic Channel Ingest mode is used for altering the search index (push, pop and flush). Once in this mode, you cannot switch to other modes or gain access to commands from other modes._

**➡️ Available commands:**

* `PUSH`: Push search data in the index (syntax: `PUSH <collection> <bucket> <object> "<text>" [LANG(<locale>)]?`; time complexity: `O(1)`)
* `POP`: Pop search data from the index (syntax: `POP <collection> <bucket> <object> "<text>"`; time complexity: `O(1)`)
* `COUNT`: Count indexed search data (syntax: `COUNT <collection> [<bucket> [<object>]?]?`; time complexity: `O(1)`)
* `FLUSHC`: Flush all indexed data from a collection (syntax: `FLUSHC <collection>`; time complexity: `O(1)`)
* `FLUSHB`: Flush all indexed data from a bucket in a collection (syntax: `FLUSHB <collection> <bucket>`; time complexity: `O(N)` where `N` is the number of bucket objects)
* `FLUSHO`: Flush all indexed data from an object in a bucket in collection (syntax: `FLUSHO <collection> <bucket> <object>`; time complexity: `O(1)`)
* `PING`: ping server (syntax: `PING`; time complexity: `O(1)`)
* `HELP`: show help (syntax: `HELP [<manual>]?`; time complexity: `O(1)`)
* `QUIT`: stop connection (syntax: `QUIT`; time complexity: `O(1)`)

**⏩ Syntax terminology:**

* `<collection>`: index collection (ie. what you search in, eg. `messages`, `products`, etc.);
* `<bucket>`: index bucket name (ie. user-specific search classifier in the collection if you have any eg. `user-1, user-2, ..`, otherwise use a common bucket name eg. `generic, default, common, ..`);
* `<object>`: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact);
* `<text>`: search text to be indexed (can be a single word, or a longer text; within maximum length safety limits; between quotes);
* `<locale>`: an ISO 639-3 locale code eg. `eng` for English (if set, the locale must be a valid ISO 639-3 code; if set to `none`, lexing will be disabled; if not set, the locale will be guessed from text);
* `<manual>`: help manual to be shown (available manuals: `commands`);

_Notice: the `bucket` terminology may confuse some Sonic users. As we are well-aware Sonic may be used in an environment where end-users may each hold their own search index in a given `collection`, we made it possible to manage per-end-user search indexes with `bucket`. If you only have a single index per `collection` (most Sonic users will), we advise you use a static generic name for your `bucket`, for instance: `default`._

**⬇️ Ingest flow example (via `telnet`):**

```bash
T1: telnet sonic.local 1491
T2: Trying ::1...
T3: Connected to sonic.local.
T4: Escape character is '^]'.
T5: CONNECTED <sonic-server v1.0.0>
T6: START ingest SecretPassword
T7: STARTED ingest protocol(1) buffer(20000)
T8: PUSH messages user:0dcde3a6 conversation:71f3d63b Hey Valerian
T9: ERR invalid_format(PUSH <collection> <bucket> <object> "<text>")
T10: PUSH messages user:0dcde3a6 conversation:71f3d63b "Hello Valerian Saliou, how are you today?"
T11: OK
T12: COUNT messages user:0dcde3a6
T13: RESULT 43
T14: COUNT messages user:0dcde3a6 conversation:71f3d63b
T15: RESULT 1
T16: FLUSHO messages user:0dcde3a6 conversation:71f3d63b
T17: RESULT 1
T18: FLUSHB messages user:0dcde3a6
T19: RESULT 42
T20: PING
T21: PONG
T22: QUIT
T23: ENDED quit
T24: Connection closed by foreign host.
```

_Notes on what happens:_

* **T6:** we enter `ingest` mode (this is required to enable `ingest` commands);
* **T8:** we try to push text `Hey Valerian` to the index, in collection `messages`, bucket `user:0dcde3a6` and object `conversation:71f3d63b` (the syntax that was used is invalid);
* **T9:** Sonic refuses the command we issued in T8, and provides us with the correct command format (notice that `<text>` should be quoted);
* **T10:** we attempt to push another text in the same collection, bucket and object as in T8;
* **T11:** this time, our push command in T10 was valid (Sonic acknowledges the push commit to the search index);
* **T12:** we count the number of indexed terms in collection `messages` and bucket `user:0dcde3a6`;
* **T13:** there are 43 terms (ie. words) in index for query in T12;
* **T18:** we flush all index data from collection `messages` and bucket `user:0dcde3a6`;
* **T19:** 42 terms have been flushed from index for command in T18;

---

### 5️⃣ Sonic Channel (Control mode)

_The Sonic Channel Control mode is used for administration purposes. Once in this mode, you cannot switch to other modes or gain access to commands from other modes._

**➡️ Available commands:**

* `TRIGGER`: trigger an action (syntax: `TRIGGER [<action>]? [<data>]?`; time complexity: `O(1)`)
* `INFO`: get server information (syntax: `INFO`; time complexity: `O(1)`)
* `PING`: ping server (syntax: `PING`; time complexity: `O(1)`)
* `HELP`: show help (syntax: `HELP [<manual>]?`; time complexity: `O(1)`)
* `QUIT`: stop connection (syntax: `QUIT`; time complexity: `O(1)`)

**⏩ Syntax terminology:**

* `<action>`: action to be triggered (available actions: `consolidate`, `backup`, `restore`);
* `<data>`: additional data to provide to the action (required for: `backup`, `restore`);
* `<manual>`: help manual to be shown (available manuals: `commands`);

**⬇️ Control flow example (via `telnet`):**

```bash
T1: telnet sonic.local 1491
T2: Trying ::1...
T3: Connected to sonic.local.
T4: Escape character is '^]'.
T5: CONNECTED <sonic-server v1.0.0>
T6: START control SecretPassword
T7: STARTED control protocol(1) buffer(20000)
T8: TRIGGER consolidate
T9: OK
T10: PING
T11: PONG
T12: QUIT
T13: ENDED quit
T14: Connection closed by foreign host.
```

_Notes on what happens:_

* **T6:** we enter `control` mode (this is required to enable `control` commands);
* **T8:** we trigger a database consolidation (instead of waiting for the next automated consolidation tick);




## Implementation

### imports

these are the imports that we will use because we will be dealing with networks, some data parsing, .. etc
```nim
import strformat, tables, json, strutils, sequtils, hashes, net, asyncdispatch, asyncnet, os, strutils, parseutils, deques, options, net
```


### Types

As we said earlier there're three channels

```nim
type 
  SonicChannel* {.pure.} = enum
   Ingest
   Search
   Control
```

Generic sonic exception
```nim
type 
  SonicServerError = object of Exception
```

Now for the base connection

```nim
type
  SonicBase[TSocket] = ref object of RootObj
   socket: TSocket
   host: string
   port: int
   password: string
   connected: bool
   timeout*: int
   protocol*: int
   bufSize*: int
   channel*: SonicChannel

  Sonic* = ref object of SonicBase[net.Socket]
  AsyncSonic* = ref object of SonicBase[asyncnet.AsyncSocket]
```
we require
- host: sonic server running on
- password: for sonic server
- connected: flag for connected or none
- timeout: timeout in seconds
- protocol: information sent to us on connecting to sonic server
- bufsize: how big is the data buffer u can use
- channel: to indicate the current mode.



### Helpers

```nim

proc quoteText(text:string): string =
  ## Quote text and normalize it in sonic protocol context.
  ##  - text str  text to quote/escape
  ##  Returns:
  ##    str  quoted text

  return '"' & text.replace('"', '\"').replace("\r\n", "") & '"'
```
quoteText used to escape quotes and replace newline

```nim
proc isError(response: string): bool =
  ## Check if the response is Error or not in sonic context.
  ## Errors start with `ERR`
  ##  - response   response string
  ##  Returns:
  ##    bool  true if response is an error.

  response.startsWith("ERR ")
```
isError checks if the response represents and error

```nim
proc raiseForError(response:string): string =
  ## Raise SonicServerError in case of error response.
  ##  - response message to check if it's error or not.
  ##  Returns:
  ##    str the response message
  if isError(response):
    raise newException(SonicServerError, response)
  return response
```
raiseError a short circuit for raising errors if response is an errror or returning response


### Making a connection

```nim
proc open*(host = "localhost", port = 1491, password="", channel:SonicChannel, ssl=false, timeout=0): Sonic =
  result = Sonic(
   socket: newSocket(buffered = true),
   host: host,
   port: port,
   password: password,
   channel: channel
  )
  result.timeout = timeout
  result.channel = channel
  when defined(ssl):
   if ssl == true:
     SSLifySonicConnectionNoVerify(result)
  result.socket.connect(host, port.Port)

  result.startSession()

proc openAsync*(host = "localhost", port = 1491, password="", channel:SonicChannel, ssl=false, timeout=0): Future[AsyncSonic] {.async.} =
  ## Open an asynchronous connection to a Sonic server.
  result = AsyncSonic(
   socket: newAsyncSocket(buffered = true),
   channel: channel
  )
  when defined(ssl):
   if ssl == true:
     SSLifySonicConnectionNoVerify(result)
  result.timeout = timeout
  await result.socket.connect(host, port.Port)
  await result.startSession()

```

Here we support to APIs async/sync APIs for opening connection and as soon as we do the connection we call `startSession`

### startSession

```nim

proc startSession*(this:Sonic|AsyncSonic): Future[void] {.multisync.} =
  let resp = await this.socket.recvLine()

  if "CONNECTED" in resp:
   this.connected = true

  var channelName = ""
  case this.channel:
   of SonicChannel.Ingest:  channelName = "ingest"
   of SonicChannel.Search:  channelName = "search"
   of SonicChannel.COntrol: channelName = "control"

  let msg = fmt"START {channelName} {this.password} \r\n"
  await this.socket.send(msg)  #### start
  discard await this.socket.recvLine()  #### started. FIXME extract protocol bufsize
  ## TODO: this.parseSessionMeta(line)
```
- we use multisync pragma to support async, sync APIs (check redisclient chapter for more info).
according to wire protocol we just send the raw string `START` `SPACE` `CHANNEL_NAME` `SONIC_PASSWORD` and terminate that with `\r\n`   
- when we recieve data we should parse protocol version and the bufsize and set it in our SonicClient `this`


### Sending/Receiving data

```nim
proc receiveManaged*(this:Sonic|AsyncSonic, size=1): Future[string] {.multisync.} =
  when this is Sonic:
   if this.timeout == 0:
     result = this.socket.recvLine()
   else:
     result = this.socket.recvLine(timeout=this.timeout)
  else:
   result = await this.socket.recvLine()

  result = raiseForError(result.strip())

proc execCommand*(this: Sonic|AsyncSonic, command: string, args:seq[string]): Future[string] {.multisync.} =
  let cmdArgs = concat(@[command], args)
  let cmdStr = join(cmdArgs, " ").strip()
  await this.socket.send(cmdStr & "\r\n")
  result = await this.receiveManaged()

proc execCommand*(this: Sonic|AsyncSonic, command: string): Future[string] {.multisync.} =
  result = await this.execCommand(command, @[""])

```
here we have couple helpers to send data on the wire `execCommand` and receiving data `receiveManaged`
- we only support timeout for sync client (there's a [withTimeout](https://nim-lang.org/docs/asyncdispatch.html#withTimeout%2CFuture%5BT%5D%2Cint) for async the user can try to implement )


Now we have everything we need to interact with sonic server, but not with userfriendly API, we can do better by converting the results to nim data structures or booleans when suitable

### User-friendly APIs

#### Ping
checks the server endpoint

```nim
proc ping*(this: Sonic|AsyncSonic): Future[bool] {.multisync.} =
  ## Send ping command to the server
  ## Returns:
  ## bool  True if successfully reaching the server.
  result = (await this.execCommand("PING")) == "PONG"
```

#### Quit

Ends the connection
```nim
proc quit*(this: Sonic|AsyncSonic): Future[string] {.multisync.} =
   ## Quit the channel and closes the connection.
   result = await this.execCommand("QUIT")
   this.socket.close()
```


#### Push

Pushes search data into the index

```nim
proc push*(this: Sonic|AsyncSonic, collection, bucket, objectName, text: string, lang=""): Future[bool] {.multisync.} =
   ## Push search data in the index
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ##   - text: search text to be indexed can be a single word, or a longer text; within maximum length safety limits
   ##   - lang: ISO language code
   ##   Returns:
   ##     bool  True if search data are pushed in the index. 
   var langString = ""
   if lang != "":
     langString = fmt"LANG({lang})"
   let text = quoteText(text)
   result = (await this.execCommand("PUSH", @[collection, bucket, objectName, text, langString]))=="OK"


```
#### Pop

Pops search data from the index

```nim
proc pop*(this: Sonic|AsyncSonic, collection, bucket, objectName, text: string): Future[int] {.multisync.} =
   ## Pop search data from the index
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ##   - text: search text to be indexed can be a single word, or a longer text; within maximum length safety limits
   ##   Returns:
   ##     int 
   let text = quoteText(text)
   let resp = await this.execCommand("POP", @[collection, bucket, objectName, text])
   result = resp.split()[^1].parseInt()
```

#### Count

Count the indexed data

```nim
proc count*(this: Sonic|AsyncSonic, collection, bucket, objectName: string): Future[int] {.multisync.} =
   ## Count indexed search data
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ## Returns:
   ## int  count of index search data.

   var bucketString = ""
   if bucket != "":
     bucketString = bucket
   var objectNameString = ""
   if objectName != "":
     objectNameString = objectName
   result = parseInt(await this.execCommand("COUNT", @[collection, bucket, objectName]))

```

#### flush

Generic flush to be called from flushCollection, flushBucket, flushObject

```nim
proc flush*(this: Sonic|AsyncSonic, collection: string, bucket="", objectName=""): Future[int] {.multisync.} =
   ## Flush indexed data in a collection, bucket, or in an object.
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ##   Returns:
   ##     int  number of flushed data
   if bucket == "" and objectName=="":
      result = await this.flushCollection(collection)
   elif bucket != "" and objectName == "":
      result = await this.flushBucket(collection, bucket)
   elif objectName != "" and bucket != "":
      result = await this.flushObject(collection, bucket, objectName)
```


#### flushCollection

Flushes all the indexed data from a collection

```nim
proc flushCollection*(this: Sonic|AsyncSonic, collection: string): Future[int] {.multisync.} =
   ## Flush all indexed data from a collection
   ##  - collection index collection (ie. what you search in, eg. messages, products, etc.)
   ##   Returns:
   ##     int  number of flushed data
   result = (await this.execCommand("FLUSHC", @[collection])).parseInt
```


#### flushBucket

flushes all indexd data from a bucket in a collection

```nim
proc flushBucket*(this: Sonic|AsyncSonic, collection, bucket: string): Future[int] {.multisync.} =
   ## Flush all indexed data from a bucket in a collection
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   Returns:
   ##    int  number of flushed data
   result = (await this.execCommand("FLUSHB", @[collection, bucket])).parseInt
```

#### flushObject

Flushes all indexed data from an object in a bucket in collection

```nim
proc flushObject*(this: Sonic|AsyncSonic, collection, bucket, objectName: string): Future[int] {.multisync.} =
   ## Flush all indexed data from an object in a bucket in collection
   ##   - collection: index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket: index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - objectName: object identifier that refers to an entity in an external database, where the searched object is stored (eg. you use Sonic to index CRM contacts by name; full CRM contact data is stored in a MySQL database; in this case the object identifier in Sonic will be the MySQL primary key for the CRM contact)
   ##   Returns:
   ##     int  number of flushed data
   result = (await this.execCommand("FLUSHO", @[collection, bucket, objectName])).parseInt
```

#### Query

Queries sonic and returns a list of results.

```nim
proc query*(this: Sonic|AsyncSonic, collection, bucket, terms: string, limit=10, offset: int=0, lang=""): Future[seq[string]] {.multisync.} =
  ## Query the database
  ##  - collection index collection (ie. what you search in, eg. messages, products, etc.)
  ##  - bucket index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
  ##  - terms text for search terms
  ##  - limit a positive integer number; set within allowed maximum & minimum limits
  ##  - offset a positive integer number; set within allowed maximum & minimum limits
  ##  - lang an ISO 639-3 locale code eg. eng for English (if set, the locale must be a valid ISO 639-3 code; if not set, the locale will be guessed from text).
  ##  Returns:
  ##    list  list of objects ids.
  let limitString = fmt"LIMIT({limit})"
  var langString = ""
  if lang != "":
   langString = fmt"LANG({lang})"
  let offsetString = fmt"OFFSET({offset})"

  let termsString = quoteText(terms)
  discard await this.execCommand("QUERY", @[collection, bucket, termsString, limitString, offsetString, langString])
  let resp = await this.receiveManaged()
  result = resp.splitWhitespace()[3..^1]
```

#### Suggest
autocompletes a word using a collection and a bucket.

```nim
proc suggest*(this: Sonic|AsyncSonic, collection, bucket, word: string, limit=10): Future[seq[string]] {.multisync.} =
   ## auto-completes word.
   ##   - collection index collection (ie. what you search in, eg. messages, products, etc.)
   ##   - bucket index bucket name (ie. user-specific search classifier in the collection if you have any eg. user-1, user-2, .., otherwise use a common bucket name eg. generic, procault, common, ..)
   ##   - word word to autocomplete
   ##   - limit a positive integer number; set within allowed maximum & minimum limits (procault: {None})
   ##   Returns:
   ##     list list of suggested words.
   var limitString = fmt"LIMIT({limit})" 
   let wordString = quoteText(word)
   discard await this.execCommand("SUGGEST", @[collection, bucket, wordString, limitString])
   let resp = await this.receiveManaged()
   result = resp.splitWhitespace()[3..^1]


```


### Test code to use 
```nim
when isMainModule:

  proc testIngest() =
   var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Ingest)
   echo $cl.execCommand("PING")

   echo cl.ping()
   echo cl.protocol
   echo cl.bufsize
   echo cl.push("wiki", "articles", "article-1",
              "for the love of god hell")
   echo cl.pop("wiki", "articles", "article-1",
              "for the love of god hell")
   echo cl.pop("wikis", "articles", "article-1",
              "for the love of god hell")
   echo cl.push("wiki", "articles", "article-2",
              "for the love of satan heaven")
   echo cl.push("wiki", "articles", "article-3",
              "for the love of lorde hello")
   echo cl.push("wiki", "articles", "article-4",
              "for the god of loaf helmet")

  proc testSearch() =

   var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Search)
   echo $cl.execCommand("PING")

   echo cl.ping()
   echo cl.query("wiki", "articles", "for")
   echo cl.query("wiki", "articles", "love")
   echo cl.suggest("wiki", "articles", "hell")
   echo cl.suggest("wiki", "articles", "lo")

  proc testControl() =
   var cl = open("127.0.0.1", 1491, "dmdm", SonicChannel.Control)
   echo $cl.execCommand("PING")

   echo cl.ping()
   echo cl.trigger("consolidate")


  testIngest()
  testSearch()
  testControl()

```


Code is available on [xmonader/nim-sonic-client](https://github.com/xmonader/nim-sonic-client). Feel free to send me a PR or open an issue.