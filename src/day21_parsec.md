# Parser combinators


Today, is one of the most interesting days in my Nim journey, we will learn about Parser Combinators and Nim. Parser is something accepts some text and creates a decent structure out of it (that's not formal definition by any means). First time I learned about Parser combinator when I was (still for sure) [learning haskell](http://book.realworldhaskell.org/read/using-parsec.html), I was amazed by the expressiveness and composebility. Lots of languages has libraries based on parser combinators e.g [python pyparsing](https://github.com/pyparsing/pyparsing)


```python
from pyparsing import Word, alphas
greet = Word(alphas) + "," + Word(alphas) + "!"
hello = "Hello, World!"
print(hello, "->", greet.parseString(hello))


```
The program outputs the following:

```
Hello, World! -> ['Hello', ',', 'World', '!']
```
Here in this program we literally said we want to create a `greet` parser that's the combination of a `Word of alphas` followed by a literal comma `,` then followed by another `Word of alphas` then followed by a literal exclamation point `!`. That greet parser is only capable of parsing a text that can be broken down to the small chunks (parsable parts) we mentioned.

Imagine in python you could express that [json grammar using pyparsing](https://github.com/pyparsing/pyparsing/blob/master/examples/jsonParser.py) in around 25 lines?


```python
import pyparsing as pp
from pyparsing import pyparsing_common as ppc


def make_keyword(kwd_str, kwd_value):
    return pp.Keyword(kwd_str).setParseAction(pp.replaceWith(kwd_value))


TRUE = make_keyword("true", True)
FALSE = make_keyword("false", False)
NULL = make_keyword("null", None)

LBRACK, RBRACK, LBRACE, RBRACE, COLON = map(pp.Suppress, "[]{}:")

jsonString = pp.dblQuotedString().setParseAction(pp.removeQuotes)
jsonNumber = ppc.number()

jsonObject = pp.Forward()
jsonValue = pp.Forward()
jsonElements = pp.delimitedList(jsonValue)
jsonArray = pp.Group(LBRACK + pp.Optional(jsonElements, []) + RBRACK)
jsonValue << (
    jsonString | jsonNumber | pp.Group(jsonObject) | jsonArray | TRUE | FALSE | NULL
)
memberDef = pp.Group(jsonString + COLON + jsonValue)
jsonMembers = pp.delimitedList(memberDef)
jsonObject << pp.Dict(LBRACE + pp.Optional(jsonMembers) + RBRACE)

jsonComment = pp.cppStyleComment
jsonObject.ignore(jsonComment)

```

A more formal definition According to wikipedia, In computer programming, a parser combinator is a higher-order function that accepts several parsers as input and returns a new parser as its output. In this context, a parser is a function accepting strings as input and returning some structure as output, typically a parse tree or a set of indices representing locations in the string where parsing stopped successfully. Parser combinators enable a recursive descent parsing strategy that facilitates modular piecewise construction and testing. This parsing technique is called combinatory parsing. 

So today, we will try to create a small parser combinators (parsec library) in nim with the following expectation

## What to expect



### parsing just one letter
```nim

  let aParser = charp('a')
  let bParser = charp('b')
  echo $aParser.parse("abc")
  # <Right parsed: @["a"], remaining: bc >
  echo $bParser.parse("bca")
  # <Right parsed: @["b"], remaining: ca >

```

### parsing a letter followed by another letter

```nim
  let abParser = charp('a') >> charp('b')
  echo $abParser.parse("abc")
  # <Right parsed: @["a", "b"], remaining: c >

```

### parsing one or the other

```nim
  let aorbParser = charp('a') | charp('b')
  echo $aorbParser.parse("acd")
  # <Right parsed: @["a"], remaining: cd >

  echo $aorbParser.parse("bcd")
  # <Right parsed: @["b"], remaining: cd >

```


### parsing abc

```nim
  let abcParser = parseString("abc")
  echo $abcParser.parse("abcdef")
  # <Right parsed: @["abc"], remaining: def >

```


### parsing many a's

```nim
  let manyA = many(charp('a'))
  echo $manyA.parse("aaab")
  # <Right parsed: @["a", "a", "a"], remaining: b >

  echo $manyA.parse("bbb")
  # <Right parsed: @[], remaining: bbb >

```


### parsing at least 1 a

```nim
  let manyA1 = many1(charp('a'))
  echo $manyA1.parse("aaab")
  # <Right parsed: @["a", "a", "a"], remaining: b >
  echo $manyA1.parse("bbb")
    Left Expecting '$a' and found 'b'
  # 
```

### parsing many digits


```nim
  let manyDigits = many1(digit)
  echo $manyDigits.parse("1234")
  # <Right parsed: @["1", "2", "3", "4"], remaining:  >

```

### parsing digits separated by comma


```nim
  let commaseparatednums = sep_by(charp(',').suppress(), digit)
  echo $commaseparatednums.parse("1,2,4")
  # <Right parsed: @["1", "2", "4"], remaining:  >

```


### Creating the greet parser from pyparsing 

```nim
  let greetparser = word >> charp(',').suppress() >> many(ws).suppress() >> word
  echo $greetparser.parse("Hello,   World")
  # <Right parsed: @["Hello", "World"], remaining:  >

```

### Multiply parser

```nim
  echo $(letter*3).parse("abc")
  # <Right parsed: @["a", "b", "c"], remaining:  >

```

### parsing UUIDs

```nim
  let uuidsample = "db9674c4-72a9-4ab9-9ddd-1d641a37cde4"
  let uuidparser =(hexstr*8).map(smashtransformer) >> charp('-') >> (hexstr*4).map(smashtransformer) >> charp('-') >>  (hexstr*4).map(smashtransformer) >> charp('-') >> (hexstr*4).map(smashtransformer) >> charp('-') >> (hexstr*12).map(smashtransformer)
  echo $uuidparser.parse(uuidsample)
  # <Right parsed: @["db9674c4", "-", "72a9", "-", "4ab9", "-", "9ddd", "-", "1d641a37cde4"], remaining:  >

```


### parsing recursive nested structures (ints or list of  [ints or lists])

```nim
  var listp: Parser
  var valref = (proc():Parser =digits|listp)
  listp = charp('[') >> sep_by(charp(',').suppress(), many(valref)) >> charp(']')
  var valp = valref()

  echo $valp.parse("1")
  # <Right parsed: @["1"], remaining:  >
  echo $valp.parse("[1,2]")
  # <Right parsed: @["[", "1", "2", "]"], remaining:  >
  echo $valp.parse("[1,[1,2]]")
  #<Right parsed: @["[", "1", "[", "1", "2", "]", "]"], remaining:  >
```


## Implementation 
the idea of a parser is something that accepts a text and returns Either an success (with the info of what got consumed of the text and what is still remaining) or a failure with some error messages

``` 
                                        -> success( parsed, remaining)
stream of characters ->  [  parser  ]
                                        -> failure (what went wrong message)
```

and 
- if it was a failure we abort the parsing operation
- if it was a success we try to continue with the next parser

that's the basic idea


### imports

```nim
import strformat, strutils, sequtils
```
well, we will be dealing with lots of strings and lists, so probably we need `strformat`, `strutils`, and `sequtils`

### Either and its friends


Either is one of my favorite types, bit more advanced than a `Maybe` or [Option](https://nim-lang.org/docs/options.html), because it allows returning specific error message instead of just none that gives us no idea what went wrong.

```haskell
data Either a b = Left a | Right b
```
Either a success `Right` with data of type `b` or failure `Left` with data of type `a`

we can try to describe it in Nim as variant as follows

```nim
type 
  EitherKind = enum
    ekLeft, ekRight
  Either = ref object
    case kind*: EitherKind 
    of ekLeft: msg*: string
    of ekRight: val*: tuple[parsed: seq[string], remaining:string]
```
Here we defined the kind `EitherKind` that can be `ekLeft` or `ekRight` and on the variant `Either` we define msg in case if `kind` was `ekLeft` for `error message msg` and in case of `ekRight` we define `val` which is the "parsed and the remaining" parts of the input string. 


```nim
proc map*(this: Either, f: proc(l:seq[string]):seq[string]): Either =
  case this.kind
  of ekLeft: return this
  of ekRight: 
    return Either(kind:ekRight, val:(parsed:f(this.val.parsed), remaining:this.val.remaining))
```
Here we define the `map` function for the type either, basically what happens when we apply a function on the either type, it should unwrap the data in `Right`, pass it to the function and return a new Either (transformed either) and in case of `Left` we return the same Either


```nim
proc `$`*(this:Either): string =
  case this.kind
  of ekLeft: return fmt"<Left {this.msg}>"
  of ekRight: return fmt("<Right parsed: {this.val.parsed}, remaining: {this.val.remaining} >")
```
converting the either to string by defining `$` function

```nim
proc `==`*(this: Either, other: Either): bool =
  return this.kind == other.kind
```

here we define simple comparison for the either objects (basically checking if both are `ekRight` or both are `ekLeft`)


### Now to the parsers

We can exploit the feature of the objects to hold some more instructions for the parser, but typically parser combinators are about `composing` higher order functions together to parse a text, we can try to emulate that with objects and taking a short cut 

```nim
type
  Parser = ref object
    f* : proc(s:string):Either
    suppressed*: bool

```
Here we define a Parser type that
- holds a function `f` (real parser that consumes the input string and returns an Either)
- `suppressed` a flag to indicate we want to ignore the parsed text

suppressed can be very useful in ignoring/discarding dashes in a string (e.g uuid text) or commas in a CSV row.


```nim
proc newParser(f: proc(s:string):Either, suppressed:bool=false): Parser =
  var p = Parser()
  p.suppressed = suppressed
  p.f = f 
  return p

```
helper to create a new parser, from a real parsing function `function proc(s:string):Either` and suppressed flag, 


```nim
proc `$`*(this:Parser): string =
  return fmt("<Parser:>")
```
allowing our parser to convert to string by defining `$`


```nim
proc parse*(this: Parser, s:string): Either =
  return this.f(s)


```
- `parse` is a function that receives a string then executes the underlying parser in `f` from that input string to Either type.


```nim
proc map*(this:Parser, transformer:proc(l:seq[string]):seq[string]):Parser =
  proc inner(s:string):Either = 
    return this.f(s).map(transformer)
  return newParser(f=inner)
```
Here we define a map function to transform the underlying parser result once executed
the idea here is we return a new parser wrapping an `inner function` with all transformation knowledge (if bit tricky move to next)


```
proc suppress*(this: Parser): Parser = 
    this.suppressed = true 
    return this

```
here we change the suppressed flag to true, should be used as in the examples mentioned in what to expect section
```nim
  let commaseparatednums = sep_by(charp(',').suppress(), digit)
  echo $commaseparatednums.parse("1,2,4")
```
Here we will be interested in the digits 1 and 2 and 4 and want to ignore the `commas` in the input string, so that's what suppress helps us with.

#### Parsing a single character 


now we would like to be able to parse a single character and get parsed value and the remaining characters

```nim
  let aParser = charp('a')
  echo $aParser.parse("abc")
  # (parsed a, remaining bc)
```

```nim

proc charp*(c: char): Parser =
  proc curried(s:string):Either =
      if s == "":
          let msg = "S is empty"
          return Either(kind:ekLeft, msg:msg)
      else:
          if s[0] == c:
            let rem = s[1..<s.len]
            let parsed_string = @[$c]
            return Either(kind:ekRight, val:(parsed:parsed_string, remaining:rem))
          else:
              return Either(kind:ekLeft, msg:fmt"Expecting '${c}' and found '{s[0]}'")
  return newParser(curried)

```
here we defined a `charp` function that takes a character to parse and returns a Parser only capable of parsing that character
- we check if empty string, we return Left `Either with ekLeft kind`
- we check if the string starts with the character we want to parse, if so we return a an Either with a Right of that characater and the rest of the string or we return a Left if the string doesn't start with the character we plan to parse 
- all of the parsing logic we define in a function `curried` that we pass to `newParser`


#### Sequential parsers
now we would like to parse `a` then `b` sequentially. possible if we create parser for `a` and a parser for `b` and try to (parse `a` `andThen` parse `b`).
the statement can be converted to proc `andThen(parserForA, parserForB). let's define that function

```nim

  let abParser = charp('a') >> charp('b')
  echo $abParser.parse("abc")
  # parse: [a, b] and remaining c

```


```nim
proc andThen*(p1: Parser, p2: Parser): Parser =
    proc curried(s: string) : Either= 
        let res1 = p1.parse(s)
        case res1.kind
        of ekLeft:
          return res1
        of ekRight:
            let res2 = p2.parse(res1.val.remaining) # parse remaining chars.
            case res2.kind
            of ekLeft:
              return res2
            of ekRight:
                let v1 = res1.val.parsed
                let v2 = res2.val.parsed
                var vs: seq[string] = @[]
                if not p1.suppressed: #and _isokval(v1):
                    vs.add(v1) 
                if not p2.suppressed: #and _isokval(v2):
                    vs.add(v2)
                return Either(kind:ekRight, val:(parsed:vs, remaining:res2.val.remaining)) 
            return res2

    return newParser(f=curried)


proc `>>`*(this: Parser, rparser:Parser): Parser =
  return andThen(this, rparser)
```
Straight forward
- if parsing with `p1` fails, we fail with Left
- if parsing with `p1` succeed, we try to parse with `p2`
  - if parsing `p2` works the whole thing returns `Right`
  - if it doesn't we return `Left`
- we create `>>` function to a more pleasing api


#### alternate parsing
Now we want to try parsing with one parse or the other and only fail if both can't parse

```nim
  let aorbParser = charp('a') | charp('b')
  echo $aorbParser.parse("acd")
  echo $aorbParser.parse("bcd")
```
Here we want to be able to parse `a` or `b`

```nim

proc orElse*(p1, p2: Parser): Parser =
    proc curried(s: string):Either=
        let res = p1.parse(s)
        case res.kind
        of ekRight:
          return res
        of ekLeft:
          let res = p2.parse(s)
          case res.kind
          of ekLeft:
            return Either(kind:ekLeft, msg:"Failed at both")
          of ekRight:
            return res

    return newParser(curried)

proc `|`*(this: Parser, rparser: Parser): Parser =
  return orElse(this, rparser)


```
- if we are able to parse with `p1` we return with Right
- if we can't parse with `p1` we try to parse with `p2`
  - if we succeed we return a Right
  - if we can't we return failure with Left

- we define more pleasing syntax `|`  

#### Parsing `n` times 


we want to parse with a parsers `n` times so instead of doing this

```nim
threetimesp1 = p1 >> p1 >> p1
```
we want to write

```nim
threetimesp1 = p1*3

```

```nim
proc n*(parser:Parser, count:int): Parser = 
    proc curried(s: string): Either =
        var mys = s
        var fullparsed: seq[string] = @[]
        for i in countup(1, count):
            let res = parser.parse(mys)
            case res.kind
            of ekLeft:
                return res
            of ekRight:
                let parsed = res.val.parsed
                mys = res.val.remaining
                fullparsed.add(parsed) 

        return Either(kind:ekRight, val:(parsed:fullparsed, remaining:mys))
    return newParser(f=curried)
    

proc `*`*(this:Parser, times:int):Parser =
       return n(this, times) 
```
- here we try to apply the parser `count` times
- we create `*` function for more pleasing api


#### parsing letters, upper, lower, digits
now we want to be able to parse any alphabet letter and digits with something like 

```nim
let letter = anyOf(strutils.Letters)
let lletter = anyOf({'a'..'z'})
let uletter = anyOf({'A'..'Z'})
let digit = anyOf(strutils.Digits)
```
for digit we can do 

```nim
digit = charp("1") | charp("2") | charp("3") | charp("4") ...
```
but definitely it looks much nicer with `anyOf` syntax, so the idea is we create parsers for the elements in the set and try to `orElse` between them

Here we define choice

```nim

proc choice*(parsers: seq[Parser]): Parser = 
    return foldl(parsers, a | b)

proc anyOf*(chars: set[char]): Parser =
    return choice(mapIt(chars, charp(it)))

```
- choice is generic function over any `Parser`s seq that tries them in order
- anyOf takes in `characters` that then gets converted to parser using `mapIt` and `charp` parser generator (from character to a Parser)

#### Parsing a complete string
Now we would like to parse complete string "abc" from "abcdef" instead of doing 

```nim
abcParser = charp('a') >> charp('b') >> charp('c')
```
we want an easier syntax that gets expanded to that have

```nim
abcParser = parseString("abc)
```

##### parseString parser

```nim

proc parseString*(s:string): Parser =
  var parsers: seq[Parser] = newSeq[Parser]()
  for c in s:
    parsers.add(charp(c))
  var p = foldl(parsers, a >> b)
  return p.map(proc(l:seq[string]):seq[string] = @[join(l, "")])
```

#### Optionally

What if we want to mark a parser as optional to exist? for example if we are parsing a `greet` statement and it's valid to not to have `!` for instance ("Hello World" and "Hello World !") both should be parsable without greet parser.

We probably want to define it like that
```nim
  let greetparser = word >> charp(',').suppress() >> many(ws).suppress() >> word >> optionally(charp('!'))
  echo $greetparser.parse("Hello,   World")
  #<Right parsed: @["Hello", "World", ""], remaining:  >
  echo $greetparser.parse("Hello,   World!")
  # <Right parsed: @["Hello", "World", "!"], remaining:  >
```
Notice the `optionally(charp('!'))` it marks a parser as an option.

```nim

proc optionally*(parser: Parser): Parser =
    let myparsed = @[""]
    let nonproc = proc(s:string):Either = Either(kind:ekRight, val:(parsed:myparsed, remaining:""))
    let noneparser = newParser(f=nonproc)
    return parser | noneparser
```
What we basically do is we fake a success parser that we try to parse with the `parser` passed and if we can't we `succeed` with `noneparser`

```
#### many: zero or more

Here we try to parse as many as we can of a specific parser, e.g parse as many `a`s as we can from a string.


```nim
proc parseZeroOrMore(parser: Parser, inp:string): Either = #zero or more
    let res = parser.parse(inp)
    case res.kind
    of ekLeft:
      let myparsed: seq[string] = @[]
      return Either(kind:ekRight, val:(parsed:myparsed, remaining:inp))
    of ekRight:
      let firstval = res.val.parsed
      let restinpafterfirst = res.val.remaining
      # echo "REST INP AFTER FIRST " & restinpafterfirst
      let res = parseZeroOrMore(parser, restinpafterfirst)
      case res.kind
      of ekRight:
        let subseqvals = res.val.parsed
        let remaining = res.val.remaining
        var values:seq[string] = newSeq[string]()
        # echo "FIRST VAL: " & firstval
        # echo "SUBSEQ: " & $subseqvals
        values.add(firstval)
        values.add(subseqvals)
        return Either(kind:ekRight, val:(parsed:values, remaining:remaining))
      of ekLeft:
        let myparsed: seq[string] = @[]
        return Either(kind:ekRight, val:(parsed:myparsed, remaining:inp))

proc many*(parser:Parser):Parser =
    proc curried(s: string): Either =
        return parse_zero_or_more(parser,s)
```

#### many1: one or more

```nim
proc many1*(parser:Parser): Parser =
    proc curried(s: string): Either =
        let res = parser.parse(s)
        case res.kind
        of ekLeft:
          return res
        of ekRight:
          return many(parser).parse(s)
    return newParser(f=curried)
```
- Here we try to parse once manually
  - if parsing succeed we invoke the `many` parser
  - if parsing fails we return a left


#### Separated by parser


Most of the times the data we parse are `separated` by something a comma, space, a dash.. etc and we would like to have a simple way to parse data without hassling with commas, .. etc To make something like that possible

```nim
  let commaseparatednums = sep_by(charp(',').suppress(), digit)
  echo $commaseparatednums.parse("1,2,4")
```

```nim
proc sep_by1*(sep: Parser, parser:Parser): Parser =
    let sep_then_parser = sep >> parser
    return (parser >> many(sep_then_parser))

proc sep_by*(sep: Parser, parser:Parser): Parser =
  let myparsed = @[""]
  let nonproc = proc(s:string):Either = Either(kind:ekRight, val:(parsed:myparsed, remaining:""))
  return (sep_by1(sep, parser) | newParser(f=nonproc))


```
How does that work? Lets assume the example `a,b,c` we want to describe it as `sepBy commaParser letterParser`. perfect. then how do we mentally reason about parts? well we start with parsing a `letter` then `comma` then `letter` then `comma` then `letter`

so `letter` then `(separator >> letter) many times`, that's exactly this line in sep_by1
```nim
    return (parser >> many(sep_then_parser))
```

#### Surrounded By

if we want to make sure something is surrounded by something e.g single quotes or `|`  we can use surroundedBy helper
```nim
  let sur3pipe = surroundedBy(charp('|'), charp('3'))
  echo $sur3pipe.parse("|3|")
  #<Right parsed: @["|", "3", "|"], remaining:  >
```

Implementation should be as easy as 

```nim
let surroundedBy = proc(surparser, contentparser: Parser): Parser =
    return surparser >> contentparser >> surparser

```

#### Between

between is more generic that surroundedBy because the opening and closing can be different e.g `(3)`


```nim
  let paren3 = between(charp('('), charp('3'), charp(')') )
  echo paren3.parse("(3)")
  # <Right parsed: @["(", "3", ")"], remaining:  >
```

Implementation should be as easy as

```nim
let between = proc(p1, p2, p3: Parser): Parser =
    return p1 >> p2 >> p3
```


#### Parsing recursive nested structures

Next, we have a very simple language where you can have 
- chars
- list of chars or list


It's going to be very easy to express


```nim
  var listp: Parser
  var valref = (proc():Parser =letters|listp)

  listp = charp('[') >> sep_by(charp(',').suppress(), many(valref)) >> charp(']')
  var valp = valref()


  var inps = @["a", "[a,b]", "[a,[b,c]]"]
  for inp in inps:
      echo &"inp : {inp}"
      let parsed = valp.parse(inp)
      if parsed.kind == ekRight:
          let data = parsed.val.parsed
          echo inp, " => ", $parseToNimData(data)

```

we only need a function `parseToNimData` to convert, typically we should be able to use enhance the usage of maps to actually convert the data to the desired type "in the same time of the parsing"

Before defining `parseToNimData`, let's define the language elements first

```nim
  # recursive lang ints and list of ints or lists
  type 
    LangElemKind = enum
        leChr, leList
    LangElem = ref object
        case kind*: LangElemKind 
        of leChr: c*: char
        of leList: l*: seq[LangElem]
  

  proc `$`*(this:LangElem): string =
    case this.kind
    of leChr: return fmt"<Char {this.c}>"
    of leList: return fmt("<List: {this.l}>")

  proc `==`*(this: LangElem, other: LangElem): bool =
    return this.kind == other.kind
```
We state that our language can have two kind of LangElemKind
- leChr: for chracters
- leList: for lists of any langauge element.

```nim

  proc parseToNimData(data: seq[string]) : LangElem =
    result = LangElem(kind:leList, l: @[])
    let dataIsList = data[0][0] == '['
    for el in data:
      var firstchr = el[0]
      if firstchr.isAlphaAscii():
        var elem = LangElem(kind:leChr, c:firstchr)
        if dataIsList == false:
            return elem
        else:
             result.l[result.l.len-1].l.add(LangElem(kind:leChr, c:firstchr))

      elif firstchr == '[':
          result.l.add(LangElem(kind:leList, l: @[]))
```

`parseToNimData` is a simple transformer that builds the tree of the suceessfully parsed strings converting them into `LangElem`s
This is how the final result looks like

```
inp : a
@["parsed data: ", "a"]
a => <Char a>
inp : [a,b]
@["parsed data: ", "[", "a", "b", "]"]
[a,b] => <List: @[<List: @[<Char a>, <Char b>]>]>
inp : [a,[b,c]]
@["parsed data: ", "[", "a", "[", "b", "c", "]", "]"]
[a,[b,c]] => <List: @[<List: @[<Char a>]>, <List: @[<Char b>, <Char c>]>]>

```

## That's it!

Thank you for reading! and please feel free to open an issue or a PR to improve to content of Nim Days or improving the very young [nim-parsec](github.com/xmonader/nim-parsec) :)
