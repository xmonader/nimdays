# Day 13: Implementing Redis Client
Today we will implement a redis client for Nim. Requires reading Day 12 to create redis parser

## Redisclient
We want to create a client to communicate with redis servers

> As library designers we should keep in mind How people are going to use our library, specially if it's doing IO Operations and we need to make decisions about what kind of APIs are we going to support (blocking or nonblocking ones) or should we duplicate the functionality for both interfaces. Lucky us Nim is pretty neat when it comes to providing async, sync interfaces for your library.

## What do we expect?

- Sync APIs: blocking APIs

```Nimrod
  let con = open("localhost", 6379.Port)
  echo $con.execCommand("PING", @[])
  echo $con.execCommand("SET", @["auser", "avalue"])
  echo $con.execCommand("GET", @["auser"])
  echo $con.execCommand("SCAN", @["0"])
```

- Async APIs: Nonblocking APIs around `async/await`
```Nimrod
  let con = await openAsync("localhost", 6379.Port)
  echo await con.execCommand("PING", @[])
  echo await con.execCommand("SET", @["auser", "avalue"])
  echo await con.execCommand("GET", @["auser"])
  echo await con.execCommand("SCAN", @["0"])
  echo await con.execCommand("SET", @["auser", "avalue"])
  echo await con.execCommand("GET", @["auser"])
  echo await con.execCommand("SCAN", @["0"])

  await con.enqueueCommand("PING", @[])
  await con.enqueueCommand("PING", @[])
  await con.enqueueCommand("PING", @[])
  echo await con.commitCommands()
 
```
- Pipelining

```Nimrod
  con.enqueueCommand("PING", @[])
  con.enqueueCommand("PING", @[])
  con.enqueueCommand("PING", @[])
  
  echo $con.commitCommands()
```


## Implementation

### Imports and constants

Let's starts with main imports

```
import redisparser, strformat, tables, json, strutils, sequtils, hashes, net, asyncdispatch, asyncnet, os, strutils, parseutils, deques, options, net

```
Mainly
-  `redisparser` because we will be manipulating redis values so let's not decouple the parsing and transport
- `asyncnet, asyncdispatch` for async sockets APIs
- `net` for SSL and blocking APIs


### Data types
Thinking of the expected APIs we talked about earlier we have some sort of client that has exactly the same operations with different blocking policies, so we can abstract it a bit 

```Nimrod
type
  RedisBase[TSocket] = ref object of RootObj
    socket: TSocket
    connected: bool
    timeout*: int
    pipeline*: seq[RedisValue]

```

Base class parameterized on `TSocket` that has 
- socket: socket object that can be the blocking `net.Socket` or the nonoblocking `asyncnet.AsyncSocket`
- connected: flag to indicate the connection status
- timeout: to timeout (raise TimeoutError) after certain amount of seconds

```Nimrod
  Redis* = ref object of RedisBase[net.Socket]
```
Here we say `Redis` is a sub type of `RedisBase` and the type of transport socket we are using is the blocking `net.Socket`

```Nimrod
  AsyncRedis* = ref object of RedisBase[asyncnet.AsyncSocket]
```
Same, but here we say the socket we use is non blocking of type `asyncnet.AsyncSocket`

### Opening Connection 

```Nimrod
proc open*(host = "localhost", port = 6379.Port, ssl=false, timeout=0): Redis =
  result = Redis(
    socket: newSocket(buffered = true),
  )
  result.pipeline = @[]
  result.timeout = timeout
  ## .. code omitted for supporting SSL
  result.socket.connect(host, port)
  result.connected = true
```
Here we define `open` proc the entry point to get sync redis client `Redis`. We do some initializations regarding the endpoint and the timeout and setting that on our `Redis` new object.


```Nimrod
proc openAsync*(host = "localhost", port = 6379.Port, ssl=false, timeout=0): Future[AsyncRedis] {.async.} =
  ## Open an asynchronous connection to a redis server.
  result = AsyncRedis(
    socket: newAsyncSocket(buffered = true),
  )
  ## .. code omitted for supporting SSL
  result.pipeline = @[]
  result.timeout = timeout
  await result.socket.connect(host, port)
  result.connected = true

```
Exactly the same thing for openAsync, but instead of returning `Redis` we return a `Future` of potential `AsyncRedis` object


### Executing commands

Our APIs will be created around `execCommand` proc that will send some `command` with `arguments` formatted with `redis` protocol (using the redisparser library) to a server using Our socket and then read a complete parsable `RedisValue` back to the user (using `readForm` proc) 


- Sync version
```Nimrod

proc execCommand*(this: Redis|AsyncRedis, command: string, args:seq[string]): RedisValue =
  let cmdArgs = concat(@[command], args)
  var cmdAsRedisValues = newSeq[RedisValue]()
  for cmd in cmdArgs:
    cmdAsRedisValues.add(RedisValue(kind:vkBulkStr, bs:cmd))
  var arr = RedisValue(kind:vkArray, l: cmdAsRedisValues)
  this.socket.send(encode(arr))
  let form = this.readForm()
  let val = decodeString(form)
  return val
```

- Async version
```Nimrod

proc execCommandAsync*(this: Redis|AsyncRedis, command: string, args:seq[string]): Future[RedisValue] =
  let cmdArgs = concat(@[command], args)
  var cmdAsRedisValues = newSeq[RedisValue]()
  for cmd in cmdArgs:
    cmdAsRedisValues.add(RedisValue(kind:vkBulkStr, bs:cmd))
  var arr = RedisValue(kind:vkArray, l: cmdAsRedisValues)
  await this.socket.send(encode(arr))
  let form = await this.readForm()
  let val = decodeString(form)
  return val

```
It'd be very annoying to do provide duplicate procs for every single API `get` and `asyncGet` ... etc

#### Multisync FTW!
Nim provides a very neat feature `multisync` pragma that allows us to use the `async` definition in sync scopes 

Here is the details from [nim](https://github.com/nim-lang/Nim/blob/master/lib/pure/asyncmacro.nim#L430)
>  Macro which processes async procedures into both asynchronous and synchronous procedures. The generated async procedures use the `async` macro, whereas the generated synchronous procedures simply strip off the `await` calls.

```Nimrod

proc execCommand*(this: Redis|AsyncRedis, command: string, args:seq[string]): Future[RedisValue] {.multisync.} =
  let cmdArgs = concat(@[command], args)
  var cmdAsRedisValues = newSeq[RedisValue]()
  for cmd in cmdArgs:
    cmdAsRedisValues.add(RedisValue(kind:vkBulkStr, bs:cmd))
  var arr = RedisValue(kind:vkArray, l: cmdAsRedisValues)
  await this.socket.send(encode(arr))
  let form = await this.readForm()
  let val = decodeString(form)
  return val
```


### Readers
`readForm` is the other main proc in our client. `readForm` is responsible for reading X amount of bytes from the socket until we have a complete `RedisValue` object.

- `readMany` as the redis protocol encodes some information about the values lengths we can totally make use of that, so let's build a primitive `readMany` that reads X amount of the socket

```Nimrod

proc readMany(this:Redis|AsyncRedis, count:int=1): Future[string] {.multisync.} =
  if count == 0:
    return ""
  let data = await this.receiveManaged(count)
  return data
```

Here again to make sure our code works with `sync` and `async` usages we use `multisync` if the count required is 0 we return empty string without any fancy things with the socket otherwise we delegate to the `receiveManaged` proc

- `receivedManaged` a bit into details version on how we read the data from the socket (could be combined in the readMany proc code)

```Nimrod
proc receiveManaged*(this:Redis|AsyncRedis, size=1): Future[string] {.multisync.} =
  result = newString(size)
  when this is Redis:
    if this.timeout == 0:
      discard this.socket.recv(result, size)
    else:
      discard this.socket.recv(result, size, this.timeout)
  else:
    discard await this.socket.recvInto(addr result[0], size)
  return result
```
We check the type of `this` object using `when/is` combo to dispatch to the correct implementation (sync or async) with timeouts or not 

- `recv` has multiple versions one of them takes a `Timeout` `this.timeout` if the user wants to timeout after a while
- `recvInto` is the `async` version and doesn't support timeouts


#### readForm
`readForm` is used to retrieve a complete `RedisValue` from the server using the primitives we provided like 1readMany` or `receiveManaged`


Remember how we decode strings into RedisValue objects?

```Nimrod
  echo decodeString("*3\r\n:1\r\n:2\r\n:3\r\n\r\n")
  # # @[1, 2, 3]
  echo decodeString("+Hello, World\r\n")
  # # Hello, World
  echo decodeString("-Not found\r\n")
  # # Not found
  echo decodeString(":1512\r\n")
  # # 1512
  echo $decodeString("$32\r\nHello, World THIS IS REALLY NICE\r\n")
  # Hello, World THIS IS REALLY NICE
  echo decodeString("*2\r\n+Hello World\r\n:23\r\n")
  # @[Hello World, 23]
  echo decodeString("*2\r\n*3\r\n:1\r\n:2\r\n:3\r\n\r\n*5\r\n:5\r\n:7\r\n+Hello Word\r\n-Err\r\n$6\r\nfoobar\r\n")
  # @[@[1, 2, 3], @[5, 7, Hello Word, Err, foobar]]
  echo $decodeString("*4\r\n:51231\r\n$3\r\nfoo\r\n$-1\r\n$3\r\nbar\r\n")
  # @[51231, foo, , bar]
```

We will be doing exactly the same, but the only tricky part is we are reading from a socket and we can't move freely forward/backward without consuming data.

The way we were decoding strings into RedisValues was by peeking on the first character to see what type we are decoding `simple string`, `bulkstring`, `error`, `int`, `array`


```Nimrod

proc readForm(this:Redis|AsyncRedis): Future[string] {.multisync.} =
  var form = ""
  ## code responsible of reading a complete parsable string representing RedisValue from the socket
  return form
```

- Setup the loop

```Nimrod
  while true:
    let b = await this.receiveManaged()
    form &= b
    ## ...
```
as long as we aren't done reading a complete form yet we read just 1 byte and append it to the form string we will be returning (in the beginning that byte can be one of (`+`, `-`, `:`, `$`, `*`)


- Simple String
```Nimrod
    if b == "+":
      form &= await this.readStream(CRLF)
      return form
```
If the character we peeking at is `+` we read until we consume the `\r\n` `CRLF` (from redisparser library) because strings in redis protocl are contained between `+` and `CRLF`

but wait! what's `readStream`?
It's a small proc we need to consume bytes from the socket until we reach [and consume] a certain character 
```Nimrod
proc readStream(this:Redis|AsyncRedis, breakAfter:string): Future[string] {.multisync.} =
  var data = ""
  while true:
    if data.endsWith(breakAfter):
      break
    let strRead = await this.receiveManaged()
    data &= strRead
  return data
```

- Errors
```Nimrod
    elif b == "-":
      form &= await this.readStream(CRLF)
      return form
```
Exactly the same as `Simple strings` but we check on `-` instead of `+`

- Ints

```Nimrod
    elif b == ":":
      form &= await this.readStream(CRLF)
      return form
```
Same, serialized between `:` and `CRLF`


- Bulkstrings
```Nimrod
    elif b == "$":
      let bulklenstr = await this.readStream(CRLF)
      let bulklenI = parseInt(bulklenstr.strip()) 
      form &= bulklenstr
      if bulklenI == -1:
        form &= CRLF

    else:
      form &= await this.readMany(bulklenI)
      form &= await this.readStream(CRLF)

    return form
```
From RESP page

```
Bulk Strings are used in order to represent a single binary safe string up to 512 MB in length.

Bulk Strings are encoded in the following way:

A "$" byte followed by the number of bytes composing the string (a prefixed length), terminated by CRLF.
The actual string data.
A final CRLF.
So the string "foobar" is encoded as follows:

"$6\r\nfoobar\r\n"
When an empty string is just:

"$0\r\n\r\n"
RESP Bulk Strings can also be used in order to signal non-existence of a value using a special format that is used to represent a Null value. In this special format the length is -1, and there is no data, so a Null is represented as:

"$-1\r\n"
```

So we can have 
1- `0` for empty strings `$0\r\n\r\n`:read from `$` until we consume CRLF and CRLF
2- `number` of bytes to read:  read from `$` N amounts of bytes then consume CRLF
3- `-1` for nils read from `$`  until we consume CRLF

- Arrays

```Nimrod
    elif b == "*":
        let lenstr = await this.readStream(CRLF)
        form &= lenstr
        let lenstrAsI = parseInt(lenstr.strip())
        for i in countup(1, lenstrAsI):
          form &= await this.readForm()
        return form
```
Arrays can be bit tricky. To encode an array we do `*` followed by array length then `\r\n` then encode each element then end the array encoding with `\r\n`

As the arrays encode their `length` we know how many inner `forms` or items we need to read from the socket while reading the array

### Pipelining

From redis [pipelining](https://redis.io/topics/pipelining) page 
```
A Request/Response server can be implemented so that it is able to process new requests even if the client didn't already read the old responses. This way it is possible to send multiple commands to the server without waiting for the replies at all, and finally read the replies in a single step.

This is called pipelining, and is a technique widely in use since many decades. For instance many POP3 protocol implementations already supported this feature, dramatically speeding up the process of downloading new emails from the server.
Redis supports pipelining since the very early days, so whatever version you are running, you can use pipelining with Redis. This is an example using the raw netcat utility:
$ (printf "PING\r\nPING\r\nPING\r\n"; sleep 1) | nc localhost 6379
+PONG
+PONG
+PONG
```

So the idea we maintain a sequence of commands commands to be executed `enqueueCommand` and send them `commitCommands` and reset the `pipeline` sequence afterwards 

```Nimrod

proc enqueueCommand*(this:Redis|AsyncRedis, command:string, args: seq[string]): Future[void] {.multisync.} = 
  let cmdArgs = concat(@[command], args)
  var cmdAsRedisValues = newSeq[RedisValue]()
  for cmd in cmdArgs:
    cmdAsRedisValues.add(RedisValue(kind:vkBulkStr, bs:cmd))
  var arr = RedisValue(kind:vkArray, l: cmdAsRedisValues)
  this.pipeline.add(arr)

proc commitCommands*(this:Redis|AsyncRedis) : Future[RedisValue] {.multisync.} =
  for cmd in this.pipeline:
    await this.socket.send(cmd.encode())
  var responses = newSeq[RedisValue]()
  for i in countup(0, len(this.pipeline)-1):
    responses.add(decodeString(await this.readForm()))
  this.pipeline = @[]
  return RedisValue(kind:vkArray, l:responses)

```
### Higher level APIs

are basically `proc`s around the `execCommand` proc and with using `multisync` pargma you can have them enabled for both `sync` and `async` execution
```nim
proc del*(this: Redis | AsyncRedis, keys: seq[string]): Future[RedisValue] {.multisync.} =
  ## Delete a key or multiple keys
  return await this.execCommand("DEL", keys)


proc exists*(this: Redis | AsyncRedis, key: string): Future[bool] {.multisync.} =
  ## Determine if a key exists
  let val = await this.execCommand("EXISTS", @[key])
  result = val.i == 1
```

## nim-redisclient
That day is based on [nim-redisclient](https://github.com/xmonader/nim-redisclient) project which is using some higher level API code from [Nim/redis](https://github.com/nim-lang/redis). Feel free to send PRs or open issues 

