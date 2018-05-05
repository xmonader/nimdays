# Day 4: LinksChecker

## What to expect ?
We will be writing a simple linkschecker in both `sequential` and `asynchronous` style in nim

## Implementation

### Step 0: Imports
```nim
import  os, httpclient
import strutils
import times
import asyncdispatch
```


### Step 1: Data types
```nim
type
    LinkCheckResult = ref object 
        link: string
        state: bool
```
LinkCheckResult is a simple representation for a link and its state


### Step 2: GO Sequential!
```nim
proc checkLink(link: string) : LinkCheckResult  =
    var client = newHttpClient()
    try:
        return LinkCheckResult(link:link, state:client.get(link).code == Http200)
    except:
        return LinkCheckResult(link:link, state:false)
```
Here, we have a proc `checkLink` takes a link and returns `LinkCheckResult`
- `newHttpClient()` to create a new client
- `client.get` to send a get request to a link and it returns a response
- `response.code` gives us the HTTP status code, and we consider a link is valid if its status == 200
- `client.get` raises error for invalid structured links that's why we wrapped it a `try/except` block

```nim
proc sequentialLinksChecker(links: seq[string]): void = 
    for index, link in links:
        if link.strip() != "":
            let result = checkLink(link)
            echo result.link, " is ", result.state
```
Here, `sequentialLinksChecker` proc takes sequence of `links` and executes `checkLink` on them `sequentially`

```
LINKS: @["https://www.google.com.eg", "https://yahoo.com", "https://reddit.com", "https://none.nonadasdet", "https://github.com", ""]
SEQUENTIAL::
https://www.google.com.eg is true
https://yahoo.com is true
https://reddit.com is true
https://none.nonadasdet is false
https://github.com is true
7.716497898101807
```
On my lousy internet it took 7.7 seconds to finish :( 

### Step 3: GO ASYNC!
We can do better than waiting on IO requests to finish

```nim
proc checkLinkAsync(link: string): Future[LinkCheckResult] {.async.} =
    var client = newAsyncHttpClient()

    let future = client.get(link)
    yield future
    if future.failed:
        return LinkCheckResult(link:link, state:false)
    else:
        let resp = future.read()
        return LinkCheckResult(link:link, state: resp.code == Http200) 
```
Here, we define a `checkLinkAsync` proc
- to declare a proc as async we use `async` pragma
- notice the client is of type `newAsyncHttpClient` that doesn't block on `.get` calls
- `client.get` returns immediately a future that can either fail, and we can infer know that from `future.failed` or succeed
- `yield future` means okay i'm done for now dear `event loop` you can schedule other tasks and continue my execution when you have more update on my fancy `future`
when the eventloop comes back because the future now has some updates
- clearly, if the `future` failed we return the link with a `false` state
- otherwise, we get the `response` object that's enclosed in the future by calling `read`

```nim

proc asyncLinksChecker(links: seq[string]) {.async.} = 
    # client.maxRedirects = 0
    var futures = newSeq[Future[LinkCheckResult]]()
    for index, link in links:
        if link.strip() != "":
            futures.add(checkLinkAsync(link))
    
    # waitFor -> call async proc from sync proc, await -> call async proc from async proc
    let done = await all(futures)
    for x in done:
        echo x.link, " is ", x.state
```
Here, we have another async procedure `asyncLinksChecker` that will take a sequence of `links` and create futures for all of them and wait when they finish and give us some results
- `futures` is a sequence for the future results of all the `LinkCheckResults` for all the links passed to `asyncLinksChecker` proc
- we loop on the links and get `future` for the  execution of `checkLinkAsync` and add it to the `futures` sequence.
- we now ask to force to block until we get all of the results out of the futures into `done` variable
- then we print all the results
- Please notice `await` is used only to call `async` proc from another `async` proc, and `waitFor` is used to call `async` proc from `sync` proc

```
ASYNC::
https://www.google.com.eg is true
https://yahoo.com is true
https://reddit.com is true
https://none.nonadasdet is false
https://github.com is true
 is false
3.601503849029541
```


### Step 4 simple cli
```nim
proc main()=
    echo "Param count: ", paramCount()
    if paramCount() == 1:
        let linksfile = paramStr(1)
        var f = open(linksfile, fmRead)
        let links = readAll(f).splitLines()
        echo "LINKS: " & $links
        echo "SEQUENTIAL:: "
        var t = epochTime()
        sequentialLinksChecker(links)
        echo epochTime()-t
        echo "ASYNC:: "
        t = epochTime()
        waitFor asyncLinksChecker(links)
        echo epochTime()-t

    else:
        echo "Please provide linksfile"
main()
```
the only interesting part is `waitFor asyncLinksChecker(links)` as we said to call `async` proc from `sync` proc like this main proc you will need to use `waitFor`


### Extra, threading

```nim
import threadpool
proc checkLinkParallel(link: string) : LinkCheckResult {.thread.} =
    var client = newHttpClient()
    try:
        return LinkCheckResult(link:link, state:client.get(link).code == Http200)
    except:
        return LinkCheckResult(link:link, state:false)
```
Same as before, only `thread` pragma i used to note that proc will be executed within a thread

```nim
proc threadsLinksChecker(links: seq[string]): void = 
    var LinkCheckResults = newSeq[FlowVar[LinkCheckResult]]()
    for index, link in links:
        LinkCheckResults.add(spawn checkLinkParallel(link))  
    
    for x in LinkCheckResults:
        let res = ^x
        echo res.link, " is ", res.state
```
- spawned `tasks` or `threads` returns a value of type `FlowVar[T]`, where `T` is the return value of the spawned `proc`
- To get the value of a `FlowVar` we use `^` operator.


> Note: you should use `nim.cfg` with flags `-d:ssl` to allow working with https

Send me a PR for improvements