# minitest 

I'm a big fan of [Practical Common Lisp](http://www.gigamonkeys.com/book/) and It has a chapter on [building a unittest framework using macros](http://www.gigamonkeys.com/book/practical-building-a-unit-test-framework.html) and I didn't get the chance to tinker with nim macros just yet, So today we will be building almost the same thing in nim.


## So what's up?

Imagine you want to check for some expression and print a specific message donating the expression
```nim
  doAssert(1==2, "1 == 2 failed")
```
Here we want to assure that 1==2 or show a message with `1==2 failed` and it goes on for whatever we want to check for

```nim
  doAssert(1+2==3, "1+2 == 3 failed")
  doAssert(5*2==10, "5*2 == 10 failed")

```
We can already see the boilerplate here, repeating the expression twice one for the check and one for the message itself.


## What to expect?
We expect having a DSL to remove the boilerplate we're suffering from in the prev. section.

```nim
  check(3==1+2)
  check(6+5*2 == 16)
```
And this will print
```
3 == 1 + 2 .. passed
6 + 5 * 2 == 16 .. passed
```

And it should evolve to allow grouping of test checks

```nim
  check(3==1+2)
  check(6+5*2 == 16)
  
  suite "Arith":
    check(1+2==3)
    check(3+2==5)

  suite "Strs":
    check("HELLO".toLowerAscii() == "hello")
    check("".isNilOrEmpty() == true)

```

Resulting something like this
```
3 == 1 + 2 .. passed
6 + 5 * 2 == 16 .. passed
==================================================
Arith
==================================================
 1 + 2 == 3 .. passed
 3 + 2 == 5 .. passed
==================================================
Strs
==================================================
 "HELLO".toLowerAscii() == "hello" .. passed
 "".isNilOrEmpty() == true .. passed

```

## Implementation


So nim has two way to do macros

###  templates 

Which are like functions that called in compilation time like `preprocessor`

From the nim manual
```nim
template `!=` (a, b: untyped): untyped =
  # this definition exists in the System module
  not (a == b)

assert(5 != 6) # the compiler rewrites that to: assert(not (5 == 6))
```
so in compile time `5 != 6` will be converted into `not ( 5 == 6)` and the whole expression will be `assert(not ( 5== 6))`


So what're we gonna do is check for the passed expression to convert it to a string to be printed in the terminal output and if the expression fails we append `failed` message or any other custom failure message

```nim
template check*(exp:untyped, failureMsg:string="failed", indent:uint=0): void =
  let indentationStr = repeat(' ', indent) 
  let expStr: string = astToStr(exp)
  var msg: string
  if not exp:
    if msg.isNilOrEmpty():
      msg = indentationStr & expStr & " .. " & failureMsg
  else:
    msg = indentationStr & expStr & " .. passed"
      
  echo(msg)
```

- `untyped` means the expression doesn't have to have a type yet, imagine passing variable name that doesn't exist yet `defineVar(myVar, 5)` so here `myVar` needs to be untyped or the compiler will complain. check the manual for more info https://nim-lang.org/docs/manual.html#templates

- `astToStr` converts the AST `exp` to a string
- `indent` amount of spaces prefixing the message.

### Macros
Nim provides us with a way to access the AST in a very low level when we templates don't cut it.

What we expected is having a `suite` macro
```
  suite "Strs":
    check("HELLO".toLowerAscii() == "hello")
    check("".isNilOrEmpty() == true)
```
that takes a `name` for the suite and bunch of `statements` 
- Please note there're two kind of macros and we're interested in the `statements macro` here
- Statments macro is a macro that has `colon` `:` operator followed by bunch of statements


#### dumpTree
dumpTree is amazing to debug the ast and print them in a good visual way

```nim

  dumpTree:
    suite "Strs":
      check("HELLO".toLowerAscii() == "hello")

```

```
Ident ident"suite"
    StrLit Strs
    StmtList
      Call
        Ident ident"check"
        Infix
          Ident ident"=="
          Call
            DotExpr
              StrLit HELLO
              Ident ident"toLowerAscii"
          StrLit hello

```

- `dumpTree` says it got `Identifier Ident` named `suite`
- `suite` contains `StringLiteral` node with value `Strs` 
- `suite` contains `StmtList` node
- first statement in `StmtList` is a `call` statement 
- `call` statement consist of `procedure` name `check` in this case and args list and so on..


```nim
macro suite*(name:string, exprs: untyped) : typed = 
```
Here, we define a macro `suite` takes `name` and bunch of statements `exprs`
- Macro must return an AST in our case will be list of statements of `check` call statemenets
- Need the messages to be indented

To achieve the indentation we can either print tab before calling `check` or overwrite check to pass `indent` option, we will go with overwrite the `check` call ASTs 

```nim
  var result = newStmtList()
```
We will be returning a list of statments right?

```
  let equline = newCall("repeat", newStrLitNode("="), newIntLitNode(50))
```
statement node that equals `repeat("=", 50)`

```nim
  let writeEquline = newCall("echo", equline)
```
statement node the equals `echo repeat("=", 50)`

```nim
  add(result, writeEquline, newCall("echo", name))
  add(result, writeEquline)
```
this will generate
```
================
$name
================
```

Now we iterate over the passed statements to `suite` macro and check for its kind
```nim
  for i in 0..<exprs.len:
    var exp = exprs[i]
    let expKind = exp.kind
    case expKind
    of nnkCall:
      case exp[0].kind
      of nnkIdent:
        let identName = $exp[0].ident
        if identName == "check":
```

- If we're in a `check` call we will convert it from `check(expr)` => `check(expr, "", 1)` 


```nim
          var checkWithIndent = exp
          checkWithIndent.add(newStrLitNode(""))
          checkWithIndent.add(newIntLitNode(1))
          add(result, checkWithIndent)
```

otherwise we add any other statement as is unprocessesed.

```nim
      else:
        add(result, exp) 
    else:
      discard
        
  return result
```