# Day 15: TCP Router (Routing TCP traffic)

Today we will implement a `tcp router` or tcp portforwarder as it works against only 1 endpoint.

## What do we expect?

```nim
let opts = ForwardOptions(listenAddr:"127.0.0.1", listenPort:11000.Port, toAddr:"127.0.0.1", toPort:6379.Port)
var f = newForwarder(opts)
asyncCheck f.serve()
runForever()

```

and then you can do 
```
redis-client -p 11000
> PING
PONG

```

## The plan
- Listen on `listenPort` on address `listenAddr` and accept connections.
- On every new connection (incoming)
    - open a socket to `toPort` on `toAddr` (outgoing) 
    - whenever data is ready on any of both ends write the data to the other one

### How ready?
Linux provides APIs like select, poll to `watch` or `monitor` set of file descriptors and allows you to `do` some action on whatever `ready` file descriptor for reading or writing. 

> The select() function gives you a way to simultaneously check multiple sockets to see if they have data waiting to be recv()d, or if you can send() data to them without blocking, or if some exception has occurred.

Please check [Beej's guide to network programming](https://beej.us/guide/bgnet/html/multi/selectman.html) for more on that



## Imports

```nim
import  strformat, tables, json, strutils, sequtils, hashes, net, asyncdispatch, asyncnet, os, strutils, parseutils, deques, options, net
```

## Types

Options for the server specifying on which address to listen and where to forward the traffic.
```nim
type ForwardOptions = object
  listenAddr*: string
  listenPort*: Port
  toAddr*: string
  toPort*: Port
```

```
type Forwarder = object of RootObj
  options*: ForwardOptions


proc newForwarder(opts: ForwardOptions): ref Forwarder =
  result = new(Forwarder)
  result.options = opts

```

Represents the server `the forwarder`

and `newForwarder` creates a forwader and sets its options


## Server setup

```nim
proc serve(this: ref Forwarder) {.async.} =
  var server = newAsyncSocket(buffered=false)
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(this.options.listenPort, this.options.listenAddr)
  echo fmt"Started tcp server... {this.options.listenAddr}:{this.options.listenPort} "
  server.listen()
  
  while true:
    let client = await server.accept()
    echo "..Got connection "

    asyncCheck this.processClient(client)
```
We will utilize async/await features of nim to build our server.
- Create a new socket with `newAsyncSocket` (make sure to set buffered to false so Nim doesn't try to read all requested data)

- `setSockOpts` allows you to make the socket reusable
> SO_REUSEADDR is used in servers mainly because it's common that you need to restart the server for the sake of trying or changing configurations (some use SIGHUP to update the configuration as a pattern) and if there were active connections the next time you start the server will fail.
- `bindAddr` binds the server to certian address and port `listenAddr` and `listenPort`
- then we start a loop to recieve connections.
- we should call `await processClient` right? why `asyncCheck processClient` 


### await vs asyncCheck
- `await` means execute that async action and `block` the execution until you get a result.
- `asyncCheck` means execute async action and `don't block` a suitable name might be `discard` or `discardAsync`

No we can answer the question why call `asyncCheck processClient` instead of `await processClient` is because we will block the event machine until `processClient` completely executes which defeats the purpose of concurrency and accepting/handling multiple clients.

## Process a client

### Establish the connection

```nim
proc processClient(this: ref Forwarder, client: AsyncSocket) {.async.} =
  let remote = newAsyncSocket(buffered=false)
  await remote.connect(this.options.toAddr, this.options.toPort)
  ...
```

First thing is to get a socket to the endpoint where we forward the traffic defined in the `ForwardOptions` `toAddr` and `toPort`

No we could've established a loop and reading data from the `client` socket and write it to the `remote` socket

Problem is we may get out of sync, sometimes the remote sends data once a client connects to it before reading anything from the client. Maybe the remote sends information like server version or some metadata or instructions on protocol and it may not we can't be sure that it's waiting on recieving data always as the first step. So what we can do is `watch` the file descriptors and whoever has data we write to the other one.

e.g 
- remote has data: we read `recv` it and write `send` it to the client.
- client has data: we read `recv` it and write `send` it to the remote.

### The remote has data
```nim
  proc remoteHasData() {.async.} =
    while not remote.isClosed and not remote.isClosed:
      echo " in remote has data loop"
      let data = await remote.recv(1024)
      echo "got data: " & data
      await client.send(data)
    client.close()
    remote.close()
```

### The client has data

```nim
  proc clientHasData() {.async.} =
    while not client.isClosed and not remote.isClosed:
      echo "in client has data loop"
      let data = await client.recv(1024)
      echo "got data: " & data
      await remote.send(data)
    client.close()
    remote.close()
```

### Run the data processors

Now let's register `clientHasData` and `remoteHasData` procs to the event machine and `LET'S NOT BLOCK` on any of them (remember if you don't want to block then you need `asyncCheck`) 

```nim
  try:
    asyncCheck clientHasData()
    asyncCheck remoteHasData()
  except:
    echo getCurrentExceptionMsg()
```

So now our `processClient` should look like

```nim

proc processClient(this: ref Forwarder, client: AsyncSocket) {.async.} =
  let remote = newAsyncSocket(buffered=false)
  await remote.connect(this.options.toAddr, this.options.toPort)

  proc clientHasData() {.async.} =
    while not client.isClosed and not remote.isClosed:
      echo "in client has data loop"
      let data = await client.recv(1024)
      echo "got data: " & data
      await remote.send(data)
    client.close()
    remote.close()

  proc remoteHasData() {.async.} =
    while not remote.isClosed and not remote.isClosed:
      echo " in remote has data loop"
      let data = await remote.recv(1024)
      echo "got data: " & data
      await client.send(data)
    client.close()
    remote.close()
  
  try:
    asyncCheck clientHasData()
    asyncCheck remoteHasData()
  except:
    echo getCurrentExceptionMsg()
```

## Let's forward to redis

```nim

let opts = ForwardOptions(listenAddr:"127.0.0.1", listenPort:11000.Port, toAddr:"127.0.0.1", toPort:6379.Port)
var f = newForwarder(opts)
asyncCheck f.serve()
runForever()

```

`runForever` begins a never ending global dispatch poll loop

our full code

```nim
# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

import  strformat, tables, json, strutils, sequtils, hashes, net, asyncdispatch, asyncnet, os, strutils, parseutils, deques, options, net

type ForwardOptions = object
  listenAddr*: string
  listenPort*: Port
  toAddr*: string
  toPort*: Port

type Forwarder = object of RootObj
  options*: ForwardOptions

proc processClient(this: ref Forwarder, client: AsyncSocket) {.async.} =
  let remote = newAsyncSocket(buffered=false)
  await remote.connect(this.options.toAddr, this.options.toPort)

  proc clientHasData() {.async.} =
    while not client.isClosed and not remote.isClosed:
      echo "in client has data loop"
      let data = await client.recv(1024)
      echo "got data: " & data
      await remote.send(data)
    client.close()
    remote.close()

  proc remoteHasData() {.async.} =
    while not remote.isClosed and not remote.isClosed:
      echo " in remote has data loop"
      let data = await remote.recv(1024)
      echo "got data: " & data
      await client.send(data)
    client.close()
    remote.close()
  
  try:
    asyncCheck clientHasData()
    asyncCheck remoteHasData()
  except:
    echo getCurrentExceptionMsg()

proc serve(this: ref Forwarder) {.async.} =
  var server = newAsyncSocket(buffered=false)
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(this.options.listenPort, this.options.listenAddr)
  echo fmt"Started tcp server... {this.options.listenAddr}:{this.options.listenPort} "
  server.listen()
  
  while true:
    let client = await server.accept()
    echo "..Got connection "

    asyncCheck this.processClient(client)

proc newForwarder(opts: ForwardOptions): ref Forwarder =
  result = new(Forwarder)
  result.options = opts

let opts = ForwardOptions(listenAddr:"127.0.0.1", listenPort:11000.Port, toAddr:"127.0.0.1", toPort:6379.Port)
var f = newForwarder(opts)
asyncCheck f.serve()
runForever()

```

This project is very simple, but helped us tackle multiple concepts like how to utilize `async/await` and `asyncCheck` interesting use cases (literally @dom96 explained it to me). Of course, It can be extended to support something like forwarding TLS traffic based on [SNI](https://en.wikipedia.org/wiki/Server_Name_Indication) So you can serve multiple backends (with domains) using a single Public IP :) 

Please feel free to contribute by opening PR or issue on the repo.
