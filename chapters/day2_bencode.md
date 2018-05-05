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
TODO