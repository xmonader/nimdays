# Day 19: Wit.AI client


Nim client for [wit.ai](https://wit.ai) to Easily create text or voice based bots that humans can chat with on their preferred messaging platform. It helps to reduce expressions into `entity/trait` 

e.g in your wit.ai project you define entity like `VM` (virtual machine) and trait to be something like `create`, `stop` and when you send an expression like `new virtual machine` or `fresh vm`, wit.ai helps to reduce it to entity `vm` and trait `create`

## What to expect

```nim
  let tok = getEnv("WIT_ACCESS_TOKEN", "")
  if tok == "":
    echo "Make sure to set WIT_ACCESS_TOKEN variable"
    quit 1
  var inp = ""
  var w = newWit(tok)

  while true:
    echo "Enter your query or q to quit > "
    inp = stdin.readLine()
    if inp == "q":
      quit 0
    else:
      echo w.message(inp)
```

```
Enter your query or q to quit >
new vm
{"_text":"new vm","entities":{"vm":[{"confidence":0.97072907352305,"value":"create"}]},"msg_id":"1N6CURN7qaJaSKXSK"}

Enter your query or q to quit >
new machine
{"_text":"new machine","entities":{"vm":[{"confidence":0.90071815565634,"value":"create"}]},"msg_id":"1t8dOpkPbAP6SgW49"}

Enter your query or q to quit >
new docker
{"_text":"new docker","entities":{"container":[{"confidence":0.98475238333984,"value":"create"}]},"msg_id":"1l7ocY7MVWBfUijsm"}
Enter your query or q to quit >

stop machine
{"_text":"stop machine","entities":{"vm":[{"confidence":0.66323929848545,"value":"stop"}]},"msg_id":"1ygXLjnQbEt4lVMyS"}
Enter your query or q to quit >

show my coins
{"_text":"show my coins","entities":{"wallet":[{"confidence":0.75480999601329,"value":"show"}]},"msg_id":"1SdYOY60xXdMvUG7b"}
Enter your query or q to quit >

view coins
{"_text":"view coins","entities":{"wallet":[{"confidence":0.5975926583378,"value":"show"}]},"msg_id":"1HZ3YlfLlr31JlbKZ"}
Enter your query or q to quit >

```
### Speech

```nim
  echo w.speech("/home/striky/startnewvm.wav", {"Content-Type": "audio/wav"}.toTable)
```


```
{
  "_text" : "start new the m is",
  "entities" : {
    "vm" : [ {
      "confidence" : 0.54805678200202,
      "value" : "create"
    } ]
  },
  "msg_id" : "1jHMTJGHEAFh8LHFS"
}
```

## Implementation

### imports

```nim
import strformat, tables, json, strutils, sequtils, hashes, net, asyncdispatch,
    asyncnet, os, strutils, parseutils, deques, options, net
import json
import logging
import httpclient
import uri

var L = newConsoleLogger()
addHandler(L)

```
Here we import utilities we are going to use like string formatters, tables, json, http client .. etc and prepare default logger.


### Crafting wit.ai API

```nim
let WIT_API_HOST = getEnv("WIT_URL", "https://api.wit.ai")
let WIT_API_VERSION = getEnv("WIT_API_VERSION", "20160516")
let DEFAULT_MAX_STEPS = 5
```
To work with `wit.ai` API you will need to generate an API token. 
- `WIT_API_HOST`: base URL for wit.ai API `notice it's https` then we will need `-d:ssl` flag in compile phase.
- `WIT_API_VERSION`: API version in wit.ai


We will be interested in `/message` and `/speech` endpoints in [wit.ai API](https://wit.ai/docs/http/) 


#### Adding authorization to HTTP Headers
```nim
proc getWitAIRequestHeaders*(accessToken: string): HttpHeaders =
  result = newHttpHeaders({
    "authorization": "Bearer " & accessToken,
    "accept": "application/vnd.wit." & WIT_API_VERSION & "+json"
  })

```
To authorize our requests against wit.ai we need to add `authorization` header.


#### Encoding params helper

```nim
proc encodeQueryStringTable(qsTable: Table[string, string]): string =
  result = ""

  if qsTable.len == 0:
    return result

  result = "?"
  var first = true
  for k, v in qsTable.pairs:
    if not first:
      result &= "&"
    result &= fmt"{k}={encodeUrl(v)}"
    first = false
  echo $result
  return result

```
A helper to encode key, value pairs into a query string `?key=val 



### Let's get to the client

Here we define the interesting parts to interact with wit.ai

```nim
type WitException* = object of Exception
```
Generic Exception to use 



```nim
type Wit* = ref object of RootObj
  accessToken*: string
  client*: HttpClient

proc newWit(accessToken: string): Wit =
  var w = new Wit
  w.accessToken = accessToken
  w.client = newHttpClient()
  result = w
```
the entry point for our `Wit.AI` client. the client `Wit` keeps track of 
- `accessToken`: to access the API
- `client`: http client to use underneath


```nim
proc newRequest(this: Wit, meth = HttpGet, path: string, params: Table[string,
    string], body = "", headers: Table[string, string]): string =
  let fullUrl = WIT_API_HOST & path & encodeQueryStringTable(params)
  this.client.headers = getWitAIRequestHeaders(this.accessToken)
  if headers.len > 0:
    for k, v in headers:
      this.client.headers[k] = v

  var resp: Response
  if body == "":
    resp = this.client.request(fullUrl, httpMethod = meth)
  else:
    resp = this.client.request(fullUrl, httpMethod = meth, body = body)
  if resp.code != 200.HttpCode:
    raise newException(WitException, (fmt"[-] {resp.code}: {resp.body} "))

  result = resp.body
```

Generic helper to format/build `wit.ai` requests. It does the following
- Prepares the headers with `authorization` using `getWitAIRequestHeaders`
- Prepares the full URL using the `WIT_API_HOST` and the query `params` sent
- Based on the method `HttpGet` or `HttpPost` it'll issue the request and raises if response's status code is not `200`
- Returns the response body


#### /message endpoint

According to the docs of [wit.ai](https://wit.ai/docs/http/20170307#get__message_link) only `q` param is required.
```
Definition
  GET https://api.wit.ai/message
Example request with single outcome

  $ curl -XGET 'https://api.wit.ai/message?v=20170307&q=how%20many%20people%20between%20Tuesday%20and%20Friday' \
      -H 'Authorization: Bearer $TOKEN'

Example response
  {
    "msg_id": "387b8515-0c1d-42a9-aa80-e68b66b66c27",
    "_text": "how many people between Tuesday and Friday",
    "entities": {
      "metric": [ {
        "metadata": "{'code': 324}",
        "value": "metric_visitor",
        "confidence": 0.9231
      } ],
      "datetime": [
        {
          "confidence": 0.954105,
          "values": [
            {
              "to": {
                "value": "2018-12-22T00:00:00.000-08:00",
                "grain": "day"
              },
              "from": {
                "value": "2018-12-18T00:00:00.000-08:00",
                "grain": "day"
              },
              "type": "interval"
            },
            {
              "to": {
                "value": "2018-12-29T00:00:00.000-08:00",
                "grain": "day"
              },
              "from": {
                "value": "2018-12-25T00:00:00.000-08:00",
                "grain": "day"
              },
              "type": "interval"
            },
            {
              "to": {
                "value": "2019-01-05T00:00:00.000-08:00",
                "grain": "day"
              },
              "from": {
                "value": "2019-01-01T00:00:00.000-08:00",
                "grain": "day"
              },
              "type": "interval"
            }
          ],
          "to": {
            "value": "2018-12-22T00:00:00.000-08:00",
            "grain": "day"
          },
          "from": {
            "value": "2018-12-18T00:00:00.000-08:00",
            "grain": "day"
          },
          "type": "interval"
        }
      ]
    }
  }
  ```

```nim
proc message*(this: Wit, msg: string, context: ref Table[string, string] = nil,
    n = "", verbose = ""): string =
  var params = initTable[string, string]()
  if n != "":
    params["n"] = n
  if verbose != "":
    params["verbose"] = verbose
  if msg != "":
    params["q"] = msg

  if not context.isNil and context.len > 0:
    var ctxNode = %* {}
    for k, v in context.pairs:
      ctxNode[k] = %*v

    params["context"] = ( %* ctxNode).pretty()

  return this.newRequest(HttpGet, path = "/message", params, "", initTable[
      string, string]())
```
here we will allow `msg` as the expression we want to check in wit.ai, and adding some extra params for more close mapping to the official API like `context`, `verbose`, `n`

- `msg`: User’s query. Length must be > 0 and < 280
- `verbose`: A flag to get auxiliary information about entities, like the location within the sentence.
- `n`: The maximum number of n-best trait entities you want to get back. The default is 1, and the maximum is 8
- `context`: Context is key in natural language. For instance, at the same absolute instant, “today” will be resolved to a different value depending on the timezone of the user. (can contain `locale`, `timezone`, `coords` for coordinates)

#### /speech endpoint

```nim
proc speech*(this: Wit, audioFilePath: string, headers: Table[string, string],
    context: ref Table[string, string] = nil, n = "", verbose = ""): string =
  var params = initTable[string, string]()
  if n != "":
    params["n"] = n
  if verbose != "":
    params["verbose"] = verbose

  if not context.isNil and context.len > 0:
    var ctxNode = %* {}
    for k, v in context.pairs:
      ctxNode[k] = %*v

    params["context"] = ( %* ctxNode).pretty()
  let body = readFile(audioFilePath)

  return this.newRequest(HttpPost, path = "/speech", params, body, headers)
```
almost the same as `/message` endpoint except we send audioFile content in body


same as `/message`, but we will send an audio file. 


## Thanks

The complete sources can be found at [nim-witai](https://github.com/xmonader/witai-nim). Please feel free to contribute by opening PR or issue on the repo.
