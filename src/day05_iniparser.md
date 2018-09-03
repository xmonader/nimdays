# Day 5: Creating INI Parser
this is a pure [Ini](https://en.wikipedia.org/wiki/Ini_file) parser for nim

> Nim has advanced [parsecfg](https://nim-lang.org/docs/parsecfg.html)

## What to expect ? 

```Nimrod
let sample1 = """

[general]
appname = configparser
version = 0.1

[author]
name = xmonader
email = notxmonader@gmail.com


"""

var d = parseIni(sample1)

# doAssert(d.sectionsCount() == 2)
doAssert(d.getProperty("general", "appname") == "configparser")
doAssert(d.getProperty("general","version") == "0.1")
doAssert(d.getProperty("author","name") == "xmonader")
doAssert(d.getProperty("author","email") == "notxmonader@gmail.com")

d.setProperty("author", "email", "alsonotxmonader@gmail.com")
doAssert(d.getProperty("author","email") == "alsonotxmonader@gmail.com")
doAssert(d.hasSection("general") == true)
doAssert(d.hasSection("author") == true)
doAssert(d.hasProperty("author", "name") == true)
d.deleteProperty("author", "name")
doAssert(d.hasProperty("author", "name") == false)

echo d.toIniString()
let s = d.getSection("author")
echo $s
```


## Implementation
You can certainly use regular expressions, like pythons configparser, but we will go for a simpler approach here, also we want to keep it pure so we don't depend on `pcre`

### Ini sample
```ini

[general]
appname = configparser
version = 0.1

[author]
name = xmonader
email = notxmonader@gmail.com
```
Ini file consists of one or more sections and each section consists of one or more key value pairs separated by `=`


### Define your data types

```Nimrod
import tables, strutils

```
We will use tables extensively
```Nimrod
type Section = ref object
    properties: Table[string, string]
```
`Section` type contains `properties` table represents key value pairs 

```Nimrod
proc setProperty*(this: Section, name: string, value: string) =
    this.properties[name] = value
```
To set property in the underlying `properties` table

```Nimrod
proc newSection*() : Section =
    var s = Section()
    s.properties = initTable[string, string]()
    return s
```
To create new Section object

```Nimrod
proc `$`*(this: Section) : string =
    return "<Section" & $this.properties & " >"
```
Simple `toString` proc using `$` operator
```Nimrod
type Ini = ref object
    sections: Table[string, Section]
```
`Ini` type represents the whole document and contains a table `section` from `sectionName` to `Section` object.

```
proc newIni*() : Ini = 
    var ini = Ini()
    ini.sections = initTable[string, Section]()
    return ini
```
To create new Ini object
```Nimrod
proc `$`*(this: Ini) : string = 
    return "<Ini " & $this.sections & " >"
```
define friendly `toString` proc using `$` operator


### Define API
```
proc setSection*(this: Ini, name: string, section: Section) =
    this.sections[name] = section

proc getSection*(this: Ini, name: string): Section =
    return this.sections.getOrDefault(name)

proc hasSection*(this: Ini, name: string): bool =
    return this.sections.contains(name)

proc deleteSection*(this: Ini, name:string) =
    this.sections.del(name)

proc sectionsCount*(this: Ini) : int = 
    echo $this.sections
    return len(this.sections)
```
Some helper procs around Ini objects for manipulating sections.

```Nimrod

proc hasProperty*(this: Ini, sectionName: string, key: string): bool=
    return this.sections.contains(sectionName) and this.sections[sectionName].properties.contains(key)

proc setProperty*(this: Ini, sectionName: string, key: string, value:string) =
    echo $this.sections
    if this.sections.contains(sectionName):
        this.sections[sectionName].setProperty(key, value)
    else:
        raise newException(ValueError, "Ini doesn't have section " & sectionName)

proc getProperty*(this: Ini, sectionName: string, key: string) : string =
    if this.sections.contains(sectionName):
        return this.sections[sectionName].properties.getOrDefault(key)
    else:
        raise newException(ValueError, "Ini doesn't have section " & sectionName)


proc deleteProperty*(this: Ini, sectionName: string, key: string) =
    if this.sections.contains(sectionName) and this.sections[sectionName].properties.contains(key):
        this.sections[sectionName].properties.del(key)
    else:
        raise newException(ValueError, "Ini doesn't have section " & sectionName)
```
More helpers around properties in the section objects managed by `Ini` object

```Nimrod
proc toIniString*(this: Ini, sep:char='=') : string =
    var output = ""
    for sectName, section in this.sections:
        output &= "[" & sectName & "]" & "\n"
        for k, v in section.properties:
            output &= k & sep & v & "\n" 
        output &= "\n"
    return output
```
Simple proc `toIniString` to convert the nim structures into Ini text string

### Parse!
OK, here comes the cool part

#### Parser states
```Nimrod
type ParserState = enum
    readSection, readKV
```
Here we have two states
- readSection: when we are supposed to extract section name from the current line
- readKV: when we are supposed to read the line in key value pair mode

#### ParseIni proc

```Nimrod
proc parseIni*(s: string) : Ini = 
```

Here we define a proc `parseIni` that takes a string `s` and creates an `Ini` object

```Nimrod
    var ini = newIni()
    var state: ParserState = readSection
    let lines = s.splitLines
    
    var currentSectionName: string = ""
    var currentSection = newSection()
```

- `ini` is the object to be returned after parsing
- `state` the current parser state (weather it's `readSection` or `readKV`)
- `lines` input string splitted into lines `as we are a lines based parser`
- `currentSectionName` to keep track of what section we are currently in
- `currentSection` to populate `ini.sections` with `Section` object using `setSection` proc

```Nimrod
   for line in lines:
```
for each line 
```Nimrod
         if line.strip() == "" or line.startsWith(";") or line.startsWith("#"):
            continue
```
We continue if line is safe to igore `empty line` or starts with `;` or `#`

```Nimrod
        if line.startsWith("[") and line.endsWith("]"):
            state = readSection
```
if line startswith `[` and ends with `]` then we set parser state to `readSection`

```Nimrod
        if state == readSection:
            currentSectionName = line[1..<line.len-1]
            ini.setSection(currentSectionName, currentSection)
            state = readKV
            continue
```
if parser `state` is `readSection`
- extract section name `between [ and ]`
- add section object to the ini under the current section name
- change `state` to `readKV` to read key value pairs
- continue the loop on the nextline as we're done processing the section name.

```Nimrod
        if state == readKV:
            let parts = line.split({'='})
            if len(parts) == 2:
                let key = parts[0].strip()
                let val = parts[1].strip()
                ini.setProperty(currentSectionName, key, val)
```
if `state` is `readKV` 
- extract `key` and `val` by splitting the line on `=`
- `setProperty` under the `currentSectionName` using `key` and `val`
```Nimrod
    return ini
```
Here we return the populated `ini` object.
