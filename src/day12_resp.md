# Day 12: Implementing Redis Protocol
Today we will implement RESP (REdis Serialization Protocol) in Nim. Hopefully you read Day 2 on bencode data format (encoding/parsing) because we will be using the same techniques.

## RESP

From [redis protocol page](https://redis.io/topics/protocol).

```
Redis clients communicate with the Redis server using a protocol called RESP (REdis Serialization Protocol). While the protocol was designed specifically for Redis, it can be used for other client-server software projects.

RESP is a compromise between the following things:

Simple to implement.
Fast to parse.
Human readable.
RESP can serialize different data types like integers, strings, arrays. There is also a specific type for errors. Requests are sent from the client to the Redis server as arrays of strings representing the arguments of the command to execute. Redis replies with a command-specific data type.
```

So, basically we have 5 types (ints, strings, bulkstrings, errors, arrays)

## What do we expect?

- able to decode strings into Reasonable structures in Nim

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

- able to encode Nim structures representing Redis values into RESP 

```Nimrod
  echo $encodeValue(RedisValue(kind:vkStr, s:"Hello, World"))
  # # +Hello, World
  echo $encodeValue(RedisValue(kind:vkInt, i:341))
  # # :341
  echo $encodeValue(RedisValue(kind:vkError, err:"Not found"))
  # # -Not found
  echo $encodeValue(RedisValue(kind:vkArray, l: @[RedisValue(kind:vkStr, s:"Hello World"), RedisValue(kind:vkInt, i:23)]  ))
  # #*2
  # #+Hello World
  # #:23

  echo $encodeValue(RedisValue(kind:vkBulkStr, bs:"Hello, World THIS IS REALLY NICE"))
  # #$32
  # # Hello, World THIS IS REALLY NICE  

```

## Implementation

### Imports and constants

Let's starts with main imports

```
import strformat, strutils, sequtils,
const CRLF = "\r\n"
const REDISNIL = "\0\0"
```

- CRLF is really important because lots of the protocol depends on that separator `\r\n`
- REDISNIL `\0\0` to represent `Nil` values

### Data types
Again, as in Bencode chapter we will define a variant `RedisValue` that represents All redis datatypes `strings, errors, bulkstrings, ints, arrays`

```Nimrod

  ValueKind = enum
    vkStr, vkError, vkInt, vkBulkStr, vkArray

  RedisValue* = ref object
    case kind*: ValueKind
    of vkStr: s*: string
    of vkError : err*: string
    of vkInt: i*: int
    of vkBulkStr: bs*: string
    of vkArray: l*: seq[RedisValue]

```

Let's add `$`, `hash`, `==` procedures

```Nimrod

import hashes

proc `$`*(obj: RedisValue): string = 
  result = case obj.kind
  of vkStr : obj.s
  of vkBulkStr: obj.bs
  of vkInt : $obj.i
  of vkArray: $obj.l
  of vkError: obj.err

proc hash*(obj: RedisValue): Hash = 
  result = case obj.kind
  of vkStr : !$(hash(obj.s))
  of vkBulkStr: !$(hash(obj.bs))
  of vkInt : !$(hash(obj.i))
  of vkArray: !$(hash(obj.l))
  of vkError: !$(hash(obj.err))

proc `==`* (a, b: RedisValue): bool =
  ## Check two nodes for equality
  if a.isNil:
      result = b.isNil
  elif b.isNil or a.kind != b.kind:
      result = false
  else:
      case a.kind
      of vkStr:
          result = a.s == b.s
      of vkBulkStr:
          result = a.s == b.s
      of vkInt:
          result = a.i == b.i
      of vkArray:
          result = a.l == b.l
      of vkError:
          result = a.err == b.err

```

### Encoder
Encoding is just converting the variant `RedisValue` to the correct representation according to RESP

#### Encode simple strings

To encode simple strings specs says `OK` should be `+OK\r\n`

```Nimrod

proc encodeStr(v: RedisValue) : string =
  return fmt"+{v.s}{CRLF}"
```


#### Encode Errors

To encode errors we should precede it with `-` and end it with `\r\n`. So `Notfound` should be encoded as `-Notfound\r\n`

```Nimrod
proc encodeErr(v: RedisValue) : string =
  return fmt"-{v.err}{CRLF}"
```

#### Encode Ints
Ints are encoded `:NUM\r\n` so 95 is `:95\r\n`

```Nimrod
proc encodeInt(v: RedisValue) : string =
  return fmt":{v.i}{CRLF}"
```

#### Encode Bulkstrings

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

```Nimrod
proc encodeBulkStr(v: RedisValue) : string =
  return fmt"${v.bs.len}{CRLF}{v.bs}{CRLF}"

```

#### Encode Arrays

To encode an array we do `*` followed by array length then `\r\n` then encode each element then end the array encoding with `\r\n`

- As we are calling `encode` `we should forward declared it`


```Nimrod

proc encode*(v: RedisValue) : string 
proc encodeArray(v: RedisValue): string = 
  var res = "*" & $len(v.l) & CRLF
  for el in v.l:
    res &= encode(el)
  res &= CRLF
  return res

```

So for instance to encode `encodeValue(RedisValue(kind:vkArray, l: @[RedisValue(kind:vkStr, s:"Hello World"), RedisValue(kind:vkInt, i:23)]  ))`
The result should be
```
*2\r\n
+Hello World\r\n
:23\r\n
\r\n
```

#### Encode any data type

Here we switch on the passed variant and dispatch the encoding to the reasonable encoder.

```Nimrod
proc encode*(v: RedisValue) : string =
  case v.kind 
  of vkStr: return encodeStr(v)
  of vkInt:    return encodeInt(v)
  of vkError:  return encodeErr(v)
  of vkBulkStr: return encodeBulkStr(v)
  of vkArray: return encodeArray(v)

```

### Decoder
Decoding is converting RESP representation into the correct Nim structures `RedisValue`, Basically the reverse of what we did in the previous chapter

Please note: Basic strategy is Returning the `RedisValue` and the `length of processed characters`

#### Decode simple string

```Nimrod
proc decodeStr(s: string): (RedisValue, int) =
  let crlfpos = s.find(CRLF)
  return (RedisValue(kind:vkStr, s:s[1..crlfpos-1]), crlfpos+len(CRLF))
```
So, Here we are creating RedisValue of kind `vkStr` of the string between `+` and `\r\n`

#### Decode errors

```Nimrod
proc decodeError(s: string): (RedisValue, int) =
  let crlfpos = s.find(CRLF)
  return (RedisValue(kind:vkError, err:s[1..crlfpos-1]), crlfpos+len(CRLF))
```
Here we are creating RedisValue of kind `vkError` of the string between `-` and `\r\n`

#### Decode ints

Nums as we said are the values between `:` and `\r\n` so we `parseInt` of the characters between `:` and `\r\n` and create RedisValue of kind `vkInt` with that parsed int.

```Nimrod
proc decodeInt(s: string): (RedisValue, int) =
  var i: int
  let crlfpos = s.find(CRLF)
  let sInt = s[1..crlfpos-1]
  if sInt.isDigit():
    i = parseInt(sInt)
  return (RedisValue(kind:vkInt, i:i), crlfpos+len(CRLF))
```

#### Decode bulkstrings

Bulkstrings are between `$` followed by the string length and `\r\n`

- string length == 0: empty string
- string length == -1: nil
- string length > 0: string with data

```Nimrod

proc decodeBulkStr(s:string): (RedisValue, int) = 
  let crlfpos = s.find(CRLF)
  var bulklen = 0
  let slen = s[1..crlfpos-1]
  bulklen = parseInt(slen)
  var bulk: string
  if bulklen == -1:
      bulk = nil
      return (RedisValue(kind:vkBulkStr, bs:REDISNIL), crlfpos+len(CRLF))
  else:
    let nextcrlf = s.find(CRLF, crlfpos+len(CRLF))
    bulk = s[crlfpos+len(CRLF)..nextcrlf-1] 
    return (RedisValue(kind:vkBulkStr, bs:bulk), nextcrlf+len(CRLF))
```


#### Decode arrays

This is the trickiest part is to decode array
- first we need to get the length between `*` and `\r\n`
- then decode objects `array length` times, and add them to `arr`
- As we are calling `decode` `we should forward declared it`

```Nimrod
proc decode(s: string): (RedisValue, int)
proc decodeArray(s: string): (RedisValue, int) =
  var arr = newSeq[RedisValue]()
  var arrlen = 0
  var crlfpos = s.find(CRLF)
  var arrlenStr = s[1..crlfpos-1]
  if arrlenStr.isDigit():
     arrlen = parseInt(arrlenStr)
  
  var nextobjpos = s.find(CRLF)+len(CRLF)
  var i = nextobjpos 
  
  if arrlen == -1:
    
    return (RedisValue(kind:vkArray, l:arr), i)
  
  while i < len(s) and len(arr) < arrlen:
    var pair = decode(s[i..len(s)])
    var obj = pair[0]
    arr.add(obj)
    i += pair[1]
  return (RedisValue(kind:vkArray, l:arr), i+len(CRLF))
```

So this RESP 
```
*2\r\n
+Hello World\r\n
:23\r\n
\r\n
```

Should be decoded to `RedisValue(kind:vkArray, l: @[RedisValue(kind:vkStr, s:"Hello World"), RedisValue(kind:vkInt, i:23)]  )`

#### Decode any object

Based on the first character we dispatch to the correct decoder then we skip `the processed count` in the string to decode the next object.

```Nimrod
proc decode(s: string): (RedisValue, int) =
  var i = 0 
  while i < len(s):
    var curchar = $s[i]
    if curchar == "+":
      var pair = decodeStr(s[i..s.find(CRLF, i)+len(CRLF)])
      var obj =  pair[0]
      var count =  pair[1]
      i += count
      return (obj, i)
    elif curchar == "-":
      var pair = decodeError(s[i..s.find(CRLF, i)+len(CRLF)])
      var obj =  pair[0]
      var count =  pair[1]
      i += count
      return (obj, i)
    elif curchar == "$":
      var pair = decodeBulkStr(s[i..len(s)])
      var obj =  pair[0]
      var count =  pair[1]
      i += count
      return (obj, i)
    elif curchar == ":":
      var pair = decodeInt(s[i..s.find(CRLF, i)+len(CRLF)])
      var obj =  pair[0]
      var count =  pair[1]
      i += count
      return (obj, i)
    elif curchar == "*":
      var pair = decodeArray(s[i..len(s)])
      let obj = pair[0]
      let count =  pair[1]
      i += count 
      return (obj, i)
    else:
      echo fmt"Unrecognized char {curchar}"
      break
```

### Preparing commands 
In redis, commands are sent as List of `RedisValues`

so `GET USER` is converted to `*2\r\n$3\r\nGET\r\n$4\r\nUSER\r\n\r\n`

```Nimrod
proc prepareCommand*(this: Redis, command: string, args:seq[string]): string =
  let cmdArgs = concat(@[command], args)
  var cmdAsRedisValues = newSeq[RedisValue]()
  for cmd in cmdArgs:
    cmdAsRedisValues.add(RedisValue(kind:vkBulkStr, bs:cmd))
  var arr = RedisValue(kind:vkArray, l: cmdAsRedisValues)

  return encode(arr)
```

### nim-resp
That day is based on [nim-resp](https://github.com/xmonader/nim-resp) project, and on-going effort to create a redis client in Nim, it supports pipelining feature and all of the previous code. Feel free to send PRs or open issues 
