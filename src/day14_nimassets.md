# Day 14: Nim Assets (bundle your assets into single binary)

Today we will implement `nimassets` project heavily inspired by [go-bindata](https://github.com/jteeuwen/go-bindata) 

## nimassets

Typically while developing projects we have assets like (icons, images, template files, css, javascript..etc) and It can be annoying to distribute them with your application or even risk losing them or misconfiguring paths or messed-up packaging script, so packaging all of them into the same binary would be an interesting option to have. these concerns were the reason to have something like `go-bindata` or  [Qt resource system](http://doc.qt.io/qt-5/resources.html)

## What do we expect?

- Having single binary that has the actually resources into the executable.
- Generating nim file out of the `resources` we want to bundle. Maybe something like `nimassets -d=templatesdir -o=assetsfile.nim`
- Easy access to these bundled resources using `getAsset` proc
```Nimrod
import assetsfile

echo assetsfile.getAsset("templatesdir/index.html")
```

## The plan
So from a very highlevel 

```
[ Resource1 ]                                
[ Resource2 ]   -> converter (nimassets) ->  [Nim file Representing the resources list]
[ Resource3 ]                                

```

The generated file should look like

```Nimrod

import os, tables, strformat, base64, ospaths

var assets = initTable[string, string]()

proc getAsset*(path: string): string = 
  result = assets[path].decode()

assets[RESOURCE1_PATH] = BASE64_ENCODE(RESOURCE1_CONTENT)
assets[RESOURCE2_PATH] = BASE64_ENCODE(RESOURCE2_CONTENT)
assets[RESOURCE3_PATH] = BASE64_ENCODE(RESOURCE3_CONTENT)
...
...
...
...

```

- We store the resource path and its base64 encoded content in `assets` table
- We will expose 1 proc `getAsset` that takes `path` and returns the content by `decoding base64` content


## Implementation
Let's go top down approach for the implementation 


### Command line arguments
```Nimrod
const buildBranchName* = staticExec("git rev-parse --abbrev-ref HEAD") ## \
const buildCommit* = staticExec("git rev-parse HEAD")  ## \
# const latestTag* = staticExec("git describe --abbrev=0 --tags") ## \

const versionString* = fmt"0.1.0 ({buildBranchName}/{buildCommit})"

proc writeHelp() = 
    echo fmt"""
nimassets {versionString} (Bundle your assets into nim file)
    -h | --help         : show help
    -v | --version      : show version
    -o | --output       : output filename
    -f | --fast         : faster generation
    -d | --dir          : dir to include (recursively)
"""

proc writeVersion() =
    echo fmt"nimassets version {versionString}"

proc cli*() =
  var 
    compress, fast : bool = false
    dirs = newSeq[string]()
    output = "assets.nim"
  
  if paramCount() == 0:
    writeHelp()
    quit(0)
  
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
        case key
        of "help", "h": 
            writeHelp()
            quit()
        of "version", "v":
            writeVersion()
            quit()
        of "fast", "f": fast = true
        of "dir", "d": dirs.add(val)
        of "output", "o": output = val 
        else:
          discard
    else:
      discard 
  for d in dirs:
    if not dirExists(d):
      echo fmt"[-] Directory doesnt exist {d}"
      quit 2 # 2 means dir doesn't exist.
  # echo fmt"compress: {compress} fast: {fast} dirs:{dirs} output:{output}"
  createAssetsFile(dirs, output, fast, compress)

when isMainModule:
  cli()
```
Pretty simple, we accept list of directories (using `-d` or `--dir` flag) to bundle into a nim file defined using `output` flag (`assets.nim` by default)

`--fast` flag indicates if we should use threading or not to speed up a little
`compress` used to allow compression we will pass it always as `false`

> for version information (branch and commit id) we used some git commands combined with `staticExec` to ensure these values are available at compile time

### createAssetsFile
this proc is the entry to our application as it receives seq of the directories we want to bundle, the output filename, code optimization, and will make use of compress flag in the future

```Nimrod
proc createAssetsFile(dirs:seq[string], outputfile="assets.nim", fast=false, compress=false) =
  var generator: proc(s:string): string
  var data = assetsFileHeader

  if fast:
    generator = generateDirAssetsSpawn
  else:
    generator = generateDirAssetsSimple

  for d in dirs:
    data &= generator(d)
  
  writeFile(outputfile, data)

```

Here we write (the header of the assets file and the result of generating the bundle of each directory) to the `outputfile`

and either we bundle files one by one (using `generateDirAssetsSimple`) or separately (using `generateDirAssetsSpawn`)

### generateDirAssetsSimple

```Nimrod
proc generateDirAssetsSimple(dir:string): string =
  var key, val, valString: string

  for path in expandTilde(dir).walkDirRec():
    key = path
    val = readFile(path).encode()
    valString = " \"\"\"" & val & "\"\"\" "
    result &= fmt"""assets.add("{path}", {valString})""" & "\n\n"
```

We walk recursively on the directory using `walkDirRec` and write down the part `assets[RESOURECE_PATH] = ENCODE_BASE64(RESOURCE CONTENT)` for each file in the directory.

### generateDirAssetsSpawn

```Nimrod
proc handleFile(path:string): string {.thread.} =
  var val, valString: string
  val = readFile(path).encode()
  valString = " \"\"\"" & val & "\"\"\" "
  result = fmt"""assets.add("{path}", {valString})""" & "\n\n"

proc generateDirAssetsSpawn(dir: string): string = 
  var results = newSeq[FlowVar[string]]()
  for path in expandTilde(dir).walkDirRec():
    results.add(spawn handleFile(path))

  # wait till all of them are done.
  for r in results:
    result &= ^r
```
the same but as `generateDirAssetsSimple` but using spawn to do generate the `assets table entry` 

And that's basically it. 

## nimassets
All of the code is based on [nimassets](https://github.com/xmonader/nimassets) project. Feel free to send a PR or report issues.

