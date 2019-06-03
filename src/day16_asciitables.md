# Day 16: Ascii Tables

ASCII tables are everywhere, every time you issue SQL select or use tools like docker to see your beloved containers or seeing your todo list in a fancy terminal todo app

## What to expect

Being able to render tables in the terminal, control the widths and the rendering characters.
```nim
 var t = newAsciiTable()
  t.tableWidth = 80
  t.setHeaders(@["ID", "Name", "Date"])
  t.addRow(@["1", "Aaaa", "2018-10-2"])
  t.addRow(@["2", "bbvbbba", "2018-10-2"])
  t.addRow(@["399", "CCC", "1018-5-2"])
  printTable(t)

```

```
+---------------------------+---------------------------+---------------------------+
|ID                         |Name                       |Date                       |
+---------------------------+---------------------------+---------------------------+
|1                          |Aaaa                       |2018-10-2                  |
+---------------------------+---------------------------+---------------------------+
|2                          |bbvbbba                    |2018-10-2                  |
+---------------------------+---------------------------+---------------------------+
|399                        |CCC                        |1018-5-2                   |
+---------------------------+---------------------------+---------------------------+


```
or let nim decides for you 
```nim
  t.tableWidth = 0
  printTable(t)
```

```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
+---+-------+---------+
|2  |bbvbbba|2018-10-2|
+---+-------+---------+
|399|CCC    |1018-5-2 |
+---+-------+---------+

```
or even remote the separators between the rows.

```nim
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
|2  |bbvbbba|2018-10-2|
|399|CCC    |1018-5-2 |
+---+-------+---------+
```

### Why not to do it manually?
Well if you want to write code like this
```nim
      var widths = @[0,0,0,0]  #id, name, ports, root
      for k, v in info:
        if len($v.id) > widths[0]:
          widths[0] = len($v.id)
        if len($v.name) > widths[1]:
          widths[1] = len($v.name)
        if len($v.ports) > widths[2]:
          widths[2] = len($v.ports)
        if len($v.root) > widths[3]:
          widths[3] = len($v.root)
      
      var sumWidths = 0
      for w in widths:
        sumWidths += w
      
      echo "-".repeat(sumWidths)

      let extraPadding = 5
      echo "| ID"  & " ".repeat(widths[0]+ extraPadding-4) & "| Name" & " ".repeat(widths[1]+extraPadding-6) & "| Ports" & " ".repeat(widths[2]+extraPadding-6 ) & "| Root" &  " ".repeat(widths[3]-6)
      echo "-".repeat(sumWidths)
  

      for k, v in info:
        let nroot = replace(v.root, "https://hub.grid.tf/", "").strip()
        echo "|" & $v.id & " ".repeat(widths[0]-len($v.id)-1 + extraPadding) & "|" & v.name & " ".repeat(widths[1]-len(v.name)-1 + extraPadding) & "|" & v.ports & " ".repeat(widths[2]-len(v.ports)+extraPadding) & "|" & nroot & " ".repeat(widths[3]-len(v.root)+ extraPadding-2) & "|"
        echo "-".repeat(sumWidths)
      result = ""
```
be my guest :)


## imports
Not much, but we will deal with lots of strings
```nim
import strformat, strutils

```

## Types
Let's think a bit about the entities of a Table.

well we have `Table`, `headers`, `rows`, `columns` and each row has a `cell`


### Cell

```nim

type Cell* = object
  leftpad*: int
  rightpad: int
  pad*: int
  text*: string

```
Describes the Cell and we define properties like `leftpad` and `rightpad` to set the padding around the text in the cell. Also, we used `pad` general property to create equal `leftpad` and `rightpad`

```
proc newCell*(text: string, leftpad=1, rightpad=1, pad=0): ref Cell =
  result = new Cell
  result.pad = pad
  if pad != 0:
    result.leftpad = pad
    result.rightpad = pad
  else:
    result.leftpad = leftpad
    result.rightpad = rightpad
  result.text = text
```

```nim
proc len*(this:ref Cell): int =
  result = this.leftpad + this.text.len + this.rightpad
```
Cell length is the length of the whitespaces in the paddings `left` and `right` + the text length.

```
proc `$`*(this:ref Cell): string =
  result = " ".repeat(this.leftpad) & this.text & " ".repeat(this.rightpad)
```
String representation of our Cell.

```
proc newCellFromAnother(another: ref Cell): ref Cell =
  result = newCell(text=another.text, leftpad=another.leftpad, rightpad=another.rightpad)

```
Little helper procedure to properties from a cell to another 


### Table 

Now let's talk a bit about the table

```nim

type AsciiTable* = object 
  rows: seq[seq[string]]
  headers: seq[ref Cell]
  rowSeparator*: char
  colSeparator*: char 
  cellEdge*: char 
  widths: seq[int]
  suggestedWidths: seq[int]
  tableWidth*: int
  separateRows*: bool
```
AsciiTable describes a table. 
- headers makes sense to a seq of strings `@["id", "name", ...]` or a list of `Cell`s. we will describe it using a seq of `Cell`.
- tableWidth: you set the total size of the table.
- rowSeparator: character separates rows
- colSeparator: character separates columns
- cellEdge: character on the edge of each cell
Remeber that's how our table looks


```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
+---+-------+---------+
|399|CCC    |1018-5-2 |
+---+-------+---------+

```
We see each row is separated by `rowSeparator` `-` line and `cellEdge` `+` on the edgeof every cell and the columns are separated by `colSeparator` `|`

- separateRows property allows us to remove the separator between rows

without separator
```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
|2  |bbvbbba|2018-10-2|
|399|CCC    |1018-5-2 |
+---+-------+---------+

```
with separator 
```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
+---+-------+---------+
|2  |bbvbbba|2018-10-2|
+---+-------+---------+
|399|CCC    |1018-5-2 |
+---+-------+---------+
```

```nim
proc newAsciiTable*(): ref AsciiTable =
  result = new AsciiTable
  result.rowSeparator='-'
  result.colSeparator='|'
  result.cellEdge='+'
  result.tableWidth=0
  result.separateRows=true
  result.widths = newSeq[int]()
  result.suggestedWidths = newSeq[int]()
  result.rows = newSeq[seq[string]]()
  result.headers = newSeq[ref Cell]()
```
Helper to initialize the table.

```nim
proc columnsCount*(this: ref AsciiTable): int =
  result = this.headers.len
```
helper to get the number of columns.

```nim
proc setHeaders*(this: ref AsciiTable, headers:seq[string]) =
  for s in headers:
    var cell = newCell(s)
    this.headers.add(cell)

proc setHeaders*(this: ref AsciiTable, headers: seq[ref Cell]) = 
  this.headers = headers

```
Allow the usage of strings directly as for headers or customized Cells

```nim
proc setRows*(this: ref AsciiTable, rows:seq[seq[string]]) =
  this.rows = rows

proc addRow*(this: ref AsciiTable, row:seq[string]) =
  this.rows.add(row)

```
Helpers to add rows to the table `data structure`

```nim
proc printTable*(this: ref AsciiTable) =
  echo(this.render())
```
this will print the `rendered` table which is prepared using `render` proc.


```nim
proc reset*(this:ref AsciiTable) =
  this.rowSeparator='-'
  this.colSeparator='|'
  this.cellEdge='+'
  this.tableWidth=0
  this.separateRows=true
  this.widths = newSeq[int]()
  this.suggestedWidths = newSedq[int]()
  this.rows = newSeq[seq[string]]()
  this.headers = newSeq[ref Cell]()
```
Resets table defaults.

#### Rendering the table.

Let's assume for a second that `widths` property has all the information about the size of each column based on its index
e.g `widths => [5, 10, 20]` means 
- column 0 can hold maximum of 5 char cell.
- column 1 can hold maximum of 10 chars cell.
- column 2 can hold maximum of 20 chars cell.

the column `cells` size can't be varied so we set the size to the `LONGEST` item in the column.
it's bit tedious so we will get back to it later.


```nim
proc oneLine(this: ref AsciiTable): string =
  result &= this.cellEdge
  for w in this.widths:
    result &= this.rowSeparator.repeat(w) & this.cellEdge
  result &= "\n"
```
oneLine helps in creating such line
```
+---+-------+---------+
```
So how does it work?
1- add the `cellEdge` `+` on the left
2- add `colSeparator` `-` until you consume the size of the width of the column you are at and then add `cellEdge` again.
3- add new line. `\n`

Steps for each width.
```
+
+---+
+---+-------+
+---+-------+---------+
```

```nim
proc render*(this: ref AsciiTable): string =
  this.calculateWidths()
```
We start by calling our magic function `calculateWidths`


```nim
  # top border
  result &= this.oneline()
```
Generate the top border line of the table.


```nim
  # headers
  for colidx, h in this.headers:
    result &= this.colSeparator & $h & " ".repeat(this.widths[colidx]-len(h) )
  
  result &= this.colSeparator
  result &= "\n"
  # finish headers 

  # line after headers
```
Now the headers

```
|ID |Name   |Date     |
```
So we start with `colSeparator` `|` for each header defined in `this.headers` the print the content of the header (which is a cell so we print the leftpad + text + rightpad ) and add `colSeparator` `|` to the end of the items

```nim
  result &= this.oneline()

```
Add another line, So our table looks like this now.

```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
```

```nim
  # start rows
  for r in this.rows:
    # start row
    for colidx, c in r:
      let cell = newCell(c, leftpad=this.headers[colidx].leftpad, rightpad=this.headers[colidx].rightpad)
      result &= this.colSeparator & $cell & " ".repeat(this.widths[colidx]-len(cell)) 
    result &= this.colSeparator
    result &= "\n"
```
Now exactly the same for each row, we get the row and print it the same way we printed the headers and follow it by a new line.

Our table looks like this now
```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
```

```nim
    if this.separateRows: 
        result &= this.oneLine()
    # finish row
```
Now we need to decide: are all the rows have line separating them or they don't.
In case if they have separators we finish the row by adding another `oneLine`

```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
+---+-------+---------+
```
or if it doesn't have separators and we want our table to look like this in the end

```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
|2  |bbvbbba|2018-10-2|

```
we don't add `oneLine`

```
  # don't duplicate the finishing line if it's already printed in case of this.separateRows
  if not this.separateRows:
      result &= this.oneLine()
  return result
```
if we don't separateRows we add the final `oneLine` to the table
```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
|2  |bbvbbba|2018-10-2|
+---+-------+---------+   <- the final oneLine
```
if we do separateRows we shouldn't add another `oneLine` or our table will be rendered like

```
+---+-------+---------+
|ID |Name   |Date     |
+---+-------+---------+
|1  |Aaaa   |2018-10-2|
+---+-------+---------+
|2  |bbvbbba|2018-10-2|
+---+-------+---------+
+---+-------+---------+
```

### Now back to calculating widths

Back to the magic function. To be honest, it's not magical it's just bit tedious. 
So the basic idea is:





```nim
proc calculateWidths(this: ref AsciiTable) =
  var colsWidths = newSeq[int]()

```
a list of column widths

```
  if this.suggestedWidths.len == 0:
    for h in this.headers:
      colsWidths.add(h.len) 
  else:
    colsWidths = this.suggestedWidths
```
the user might suggest some widths via `suggestedWidths` property, so can use them for guidance.

```nim

  for row in this.rows:
    for colpos, c in row:
      var acell = newCellFromAnother(this.headers[colpos])
      acell.text = c
      if len(acell) > colsWidths[colpos]:
        colsWidths[colpos] = len(acell)
```
we get the size `length` of each column by iterating on all the rows and find the `max` item (the cell with the longest size) in the position of the column in every row and that `max` will be the column width.


We support other options like `totalWidth` of the Table and that will make equal column sizes if the user didn't `suggest widths`
```nim
  let sizeForCol = (this.tablewidth/len(this.headers)).toInt()
  var lenHeaders = 0
  for w in colsWidths:
    lenHeaders += w 
```
Here we calculate the length of each header `equally` using table width specified by the user divided by the number of columns `headers`


```nim
  if this.tablewidth > lenHeaders:
    if this.suggestedWidths.len == 0:
      for colpos, c in colsWidths:
        colsWidths[colpos] += sizeForCol - c
```
if the user didn't suggest any widths then he wants the table columns of equal length

```nim
  if this.suggestedWidths.len != 0:
    var sumSuggestedWidths = 0
    for s in this.suggestedWidths:
      sumSuggestedWidths += s

    if lenHeaders > sumSuggestedWidths:
      raise newException(ValueError, fmt"sum of {this.suggestedWidths} = {sumSuggestedWidths} and it's less than required length {lenHeaders}")      
```
if the user suggested some widths we caculate the sum of what user suggested and check if `greater than` the calculated `lenHeaders` and if it's not we raise an exception.

```nim
  this.widths = colsWidths
```
Phew! We finally set the widths property now 

## nim-asciitable
this day is based on my project [nim-asciitables](https://github.com/xmonader/nim-asciitables) and it's superseded by [nim-terminaltables](https://github.com/xmonader/nim-terminaltables) which provides more customizable styles and unicode box drawing support.

