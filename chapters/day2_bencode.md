# Day 2: Parsing Bencode
nim-bencode is a library to encode/decode torrent files [Bencode](https://en.wikipedia.org/wiki/Bencode)


## What to expect? 
```nim
import bencode, tables, strformat

let encoder = newEncoder()
let decoder = newDecoder()

let btListSample1 = @[BencodeType(kind:btInt, i:1), BencodeType(kind:btString, s:"hi") ]
var btDictSample1 = initOrderedTable[BencodeType, BencodeType]()
btDictSample1[BencodeType(kind:btString, s:"name")] = BencodeType(kind:btString, s:"dmdm")
btDictSample1[BencodeType(kind:btString, s:"lang")] = BencodeType(kind:btString, s:"nim")
btDictSample1[BencodeType(kind:btString, s:"age")] = BencodeType(kind:btInt, i:50)
btDictSample1[BencodeType(kind:btString, s:"alist")] = BencodeType(kind:btList, l:btListSample1)

var testObjects = initOrderedTable[BencodeType, string]()
testObjects[BencodeType(kind: btString, s:"hello")] = "5:hello"
testObjects[BencodeType(kind: btString, s:"yes")] = "3:yes"
testObjects[BencodeType(kind: btInt, i:55)] = "i55e"

testObjects[BencodeType(kind: btInt, i:12345)] = "i12345e"
testObjects[BencodeType(kind: btList, l:btListSample1)] = "li1e2:hie"
testObjects[BencodeType(kind:btDict, d:btDictSample1)] = "d4:name4:dmdm4:lang3:nim3:agei50e5:alistli1e2:hiee"


for k, v in testObjects.pairs():
    echo $k & " => " & $v
    doAssert(encoder.encodeObject(k) == v)
    doAssert(decoder.decodeObject(v) == k)

```


## Implementation

So according to Bencode we have some datatypes
- strings and those are encoded with the string length followed by a colon and the string itself `length:string`, e.g yes will be encoded into `3:yes`
- ints those are encoded between `i`, `e` letters, e.g 59 will be encoded into `i59e`
- lists can contain any of the bencode types and it's encoded with `l`, `e`,  e.g list of 1, 2 numbers is encoded into `li1ei2e` or with spaces for verbosity `l i1e i2e e`
- dicts are mapping from strings to any type and encoded between letters `d`, `e`, e.g name => hi and num => 3 is encoded into `d4:name2:hi3:numi3ee` or with spaces for verbosity `d 4:name 2:hi 3:num i3e e`
 
### Imports
```nim
import strformat, tables, json, strutils, hashes
```

As we will be dealing a lot with strings, tables

### Types

```nim
type 
    BencodeKind* = enum
        btString, btInt, btList, btDict
```

So as we mentioned about bencode data types we can define an enum to represents the kinds

```nim
    BencodeType* = ref object
        case kind*: BencodeKind 
        of BencodeKind.btString: s* : string 
        of BencodeKind.btInt: i*    : int
        of BencodeKind.btList: l*   : seq[BencodeType]
        of BencodeKind.btDict: d*  : OrderedTable[BencodeType, BencodeType]

    Encoder* = ref object
    Decoder* = ref object 
```

- `Encoder` a simple class to represent encoding operations
- `Decoder` a simple class to represent decoding operations
- For `BencodeType` we make use of variant objects `case classes` in other languages. worth noticing variant objects are the same technique used for `json` module.

So we can use it like this 

```nim
BencodeType(kind: btString, s:"hello")
BencodeType(kind: btInt, i:55)
let btListSample1 = @[BencodeType(kind:btInt, i:1), BencodeType(kind:btString, s:"hi") ]
BencodeType(kind: btList, l:btListSample1)
```

So general rule for the case classes is you have a kind defined in an enum and a constructor value u create the object with.

If you're coming from Haskell or a similar language

```haskell
data BValue = BInt Integer
            | BStr B.ByteString
            | BList [BValue]
            | BDict (M.Map BValue BValue)
            deriving (Show, Eq, Ord)
```

Please, note if you define your own variant you should define `hash`, `==` procs to be able to compare or hash the values.

```nim
proc hash*(obj: BencodeType): Hash = 
    case obj.kind
    of btString : !$(hash(obj.s))
    of btInt : !$(hash(obj.i))
    of btList: !$(hash(obj.l))
    of btDict: 
        var h = 0
        for k, v in obj.d.pairs:
            h = hash(k) !& hash(v)
        !$(h)
```

- `hash` proc returns `Hash`  and depending on the `kind` we return the hash of the underlying stored objects, strings, ints, lists or calculate a new hash if needed
- `!&` consider it like merging the two hashes together
- `!$` is used to finalize the Hash object

```nim
proc `==`* (a, b: BencodeType): bool =
    ## Check two nodes for equality
    if a.isNil:
        if b.isNil: return true
        return false
    elif b.isNil or a.kind != b.kind:
        return false
    else:
        case a.kind
        of btString:
            result = a.s == b.s
        of btInt:
            result = a.i == b.i
        of btList:
            result = a.l == b.l
        of btDict:
            if a.d.len != b.d.len: return false
            for key, val in a.d:
                if not b.d.hasKey(key): return false
                if b.d[key] != val: return false
            result = true
```

define equality operator on BencodeTypes to determine when they're equal by defining proc for operator `==`

```nim
proc `$`* (a: BencodeType): string = 
    case a.kind
    of btString:  fmt("<Bencode {a.s}>")
    of btInt: fmt("<Bencode {a.i}>")
    of btList: fmt("<Bencode {a.l}>")
    of btDict: fmt("<Bencode {a.d}")
```

Define a simple `toString` proc using the `$` operator.

### Encoding
```nim
proc encode(this: Encoder,  obj: BencodeType) : string
```
we add forward declarating to encode proc because to encode a list we might encode another values `strings`, or even `lists` so we will recursively call encode if needed, feel free to skip to the next part.


```nim
proc encode_s(this: Encoder, s: string) : string=
    # TODO: check len
    return $s.len & ":" & s
```

To encode a string we said we will put encoded with its length + `:` + string itself

```nim
proc encode_i(this: Encoder, i: int) : string=
    # TODO: check len
    return fmt("i{i}e") 
```
To encode an int we put it between `i`, `e` chars

```nim
proc encode_l(this: Encoder, l: seq[BencodeType]): string =
    var encoded = "l"
    for el in l:
        encoded &= this.encode(el)
    encoded &= "e"
    return encoded
```
- To encode a list of elements of type `BencodeType` we put their encoded values between `l`, `e` chars
- Notice the call to `this.encode` that's why we needed the forward declaration.

```nim
proc encode_d(this: Encoder, d: OrderedTable[BencodeType, BencodeType]): string =
    var encoded = "d"
    for k, v in d.pairs():
        assert k.kind == BencodeKind.btString
        encoded &= this.encode(k) & this.encode(v)

    encoded &= "e"
    return encoded
```
- To encode a dict we enclose the encoded value of the pairs between `d`, `e`
- Notice the recursive call to `this.encode` to the keys and values
- Notice the assertion the kind of the keys `must` be a `btString` according to `Bencode` specs.

```nim
proc encode(this: Encoder,  obj: BencodeType) :  string =
    case obj.kind
    of BencodeKind.btString:  result =this.encode_s(obj.s)
    of BencodeKind.btInt :  result = this.encode_i(obj.i)
    of BencodeKind.btList : result = this.encode_l(obj.l)
    of BencodeKind.btDict : result = this.encode_d(obj.d)
```
Simple proxy to encode `obj` of `BencodeType`


### Decoding

```nim
proc decode(this: Decoder,  source: string) : (BencodeType, int)
```
Forward declaration for `decode` same as `decode`

```nim
proc decode_s(this: Decoder, s: string) : (BencodeType, int) =
    let lengthpart = s.split(":")[0]
    let sizelength = lengthpart.len
    let strlen = parseInt(lengthpart)
    return (BencodeType(kind:btString, s: s[sizelength+1..strlen+1]), sizelength+1+strlen)
```
Create a BencodeType of after decoding a string `reverse operation of encode_s`
Basically and read string of length `sizelength` after the `colon` and construct a `BencodeType` of kind `btString` out of it

```nim
proc decode_i(this: Decoder, s: string) : (BencodeType, int) =
    let epos = s.find('e')
    let i = parseInt(s[1..<epos])
    return (BencodeType(kind:btInt, i:i), epos+1)

```

Extract the number between `i`, `e` chars and construct `BencodeType` of kind `btInt` out of it    


```nim
proc decode_l(this: Decoder, s: string): (BencodeType, int) =
    # l ... e
    var els = newSeq[BencodeType]()
    var curchar = s[1]
    var idx = 1
    while idx < s.len:
        curchar = s[idx]
        if curchar == 'e':
            idx += 1
            break
    
        let pair = this.decode(s[idx..<s.len])
        let obj = pair[0]
        let nextobjpos = pair[1] 
        els.add(obj)
        idx += nextobjpos
    return (BencodeType(kind:btList, l:els), idx)
```

Decoding the list can be bit tricky
- Its elements are between `l`, `e` chars
- So we start trying to decode objects starting from the first letter `after` the `l` until we reach the final `e`
e.g
```
li1ei2ee
```
will be parsed like the following
```
li120ei492ee
 $   $
```

- will consume the object `i120e` and set the cursor to the beginning of the second object `i492e`
- after all the objects are consumed we consume the end character `e` and we are done
- That's why all decode procs return `int` value to let us now how much characters to skip

```nim
proc decode_d(this: Decoder, s: string): (BencodeType, int) =
    var d = initOrderedTable[BencodeType, BencodeType]()
    var curchar = s[1]
    var idx = 1
    var readingKey = true
    var curKey: BencodeType
    while idx < s.len:
        curchar = s[idx]
        if curchar == 'e':
            break
        let pair = this.decode(s[idx..<s.len])
        let obj = pair[0]
        let nextobjpos = pair[1]
        if readingKey == true:
            curKey = obj
            readingKey = false
        else:
            d[curKey] = obj
            readingKey = true
        idx += nextobjpos
    return (BencodeType(kind:btDict, d: d), idx)
```

- Same technique as above 
- Basically we read one object if we don't have a current key then we set it as the current key
- If we have a current key object then the object we read is the value, so we set the currentKey to that value and `change` mode to readingKey again.

```nim
proc decode(this: Decoder,  source: string) : (BencodeType, int) =
    var curchar = source[0]
    var idx = 0
    while idx < source.len:
        curchar = source[idx]
        case curchar
        of 'i':
            let pair = this.decode_i(source[idx..source.len])
            let obj = pair[0]
            let nextobjpos = pair[1] 
            idx += nextobjpos
            return (obj, idx)
        of 'l':
            let pair = this.decode_l(source[idx..source.len])
            let obj = pair[0]
            let nextobjpos = pair[1] 
            idx += nextobjpos
            return (obj, idx)
        of 'd':
            let pair = this.decode_d(source[idx..source.len])
            let obj = pair[0]
            let nextobjpos = pair[1] 
            idx += nextobjpos
            return (obj, idx)
        else: 
            let pair = this.decode_s(source[idx..source.len])
            let obj = pair[0]
            let nextobjpos = pair[1] 
            idx += nextobjpos
            return (obj, idx)
```

Starts decoding based on the beginning of character encoding object `i` for int, `l` for lists, `d` for dicts and otherwise tries to parse string

```nim
proc newEncoder*(): Encoder =
    new Encoder

proc newDecoder*(): Decoder = 
    new Decoder
```

Simple constructor procs for newEncoder, newDecoder


```nim
proc encodeObject*(this: Encoder, obj: BencodeType) : string =
    return this.encode(obj)
```

`encodeObject` dispatch the call to `encode` proc.

```nim
proc decodeObject*(this: Decoder, source:string) : BencodeType =
    let p = this.decode(source)
    return p[0]
```

`decodeObject` provides a friendlier API to return the BencodeType from decode instead of `BencodeType`, `how many to read` int 


