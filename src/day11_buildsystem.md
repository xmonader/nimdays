# Day 11 ( Bake applications)

I used to work on application 2 years ago, and It was a bit like ansible defining recipes to create applications and managng their dependencies.


## What to expect
Today we will be doing something very simple to track our dependencies and print the bash commands for each task like Makefile.

```makefile
HEADERS = program.h headers.h

default: program

program.o: program.c $(HEADERS)
    gcc -c program.c -o program.o

program: program.o
    gcc program.o -o program

clean:
    -rm -f program.o
    -rm -f program
```

Basically, makefile consists of 

- Variables
- Targets
- Dependencies

`variables` like `HEADERS=...`, `targets` whatever precedes the `:` like `clean`, `program`, `program.o`, `dependencies` are what a target depends on, so for instance `program` target that generates the executable requires `program.o` dependency to be executed first.




## Example API usage

### Normal usage
```Nimrod
  var b = initBake()
  b.add_task("publish", @["build-release"], "print publish")
  b.add_task("build-release", @["nim-installed"], "print exec command to build release mode")
  b.add_task("nim-installed", @["curl-installed"], "print curl LINK | bash")
  b.add_task("curl-installed", @["apt-installed"], "apt-get install curl")
  b.add_task("apt-installed", @[], "code to install apt...")
  b.run_task("publish")
```

OUTPUT:

```
code to install apt...
apt-get install curl
print curl LINK | bash
print exec command to build release mode
print publish
```

### Circular dependencies
```Nimrod
  var b = initBake()
  b.add_task("publish", @["build-release"], "print publish")
  b.add_task("build-release", @["nim-installed"], "print exec command to build release mode")
  b.add_task("nim-installed", @["curl-installed"], "print curl LINK | bash")
  b.add_task("curl-installed", @["publish", "apt-installed"], "apt-get install curl")
  b.add_task("apt-installed", @[], "code to install apt...")
  b.run_task("publish")

```

Output:
```
Found cycle please fix:@["build-release", "nim-installed", "curl-installed", "publish", "build-release"]
```

### Implementation

#### Imports

```Nimrod
import strformat, strutils, tables, sequtils, algorithm
```

#### Graphs
Graphs are very powerful data structure and used to solve lots of problems, like getting the shortest route and detecting circular dependencies in our code today :)

So How to represent graph?
Well, we will use [Adjaceny list](https://en.wikipedia.org/wiki/Adjacency_list) 


#### Objects

```Nimrod

type Task = object
  requires*: seq[string]
  actions*: string
  name*: string

proc `$`(this: Task): string = 
  return fmt("Task {this.name} Requirements: {this.requires} , actions {this.actions}")

```

Task object represnts a `target` in makefile language, and it has a name, actions code and list of dependencies

```Nimrod
type Bake = ref object
  tasksgraph* : Table[string, seq[string]]
  tasks*      : Table[string, Task]
```

Bake object has `tasksgraph` adjaceny list representing the tasks and their dependencies and tasks table that maps taskname to task object

#### Adding a task
```Nimrod

proc addTask*(this: Bake, taskname: string, deps: seq[string], actions:string) : void = 
  var t =  Task(name:taskname, requires:deps, actions:actions)
  this.tasksgraph[taskname] = deps
  this.tasks[taskname] = t
```
- We update the adjacency list with (taskname and its dependencies)
- Add task object to tasks Table with key task name

#### Running tasks
```Nimrod

proc runTask*(this: Bake, taskname: string): void =
  # CODE OMITTED FOR FINIDNG CYCLES..

  var deps = newSeq[string]()
  var seen = newSeq[string]()

  this.runTaskHelper(taskname, deps, seen)      

  for tsk in deps:
      let t = this.tasks.getOrDefault(tsk)
      echo(t.actions)

```
- Before running a task we should check if it has a cycle first.
- Keep track of dependencies and the seen tasks so far so we don't `run seen tasks` again. (for instance if we have target install-wget and target install-curl and both require target `apt-get update`, so we want to run `apt-get update` only once )

for example
```
code to install apt...
apt-get install curl
print curl LINK | bash
print exec command to build release mode
print publish
```

- Call `runTaskHelper` procedure to walk through all the `tasks` and their `dependencies` and get us a list of deps `each will update deps variable as we will be sending it by reference` 
- After getting correct dependencies tasks sorted we execute `in our case we will just echo actions property`


and now to `runTaskHelper` that basically updates our dependencies list and put the task execution in order

```Nimrod

proc runTaskHelper(this: Bake, taskname: string, deps: var seq[string], seen: var seq[string]) : void = 
  if taskname in seen:
    echo "[+] Solved {taskname} before no need to repeat action"
  var tsk = this.tasks.getOrDefault(taskname)

  seen.add(taskname)
  if len(tsk.requires) > 0:
    for c in this.tasksgraph[tsk.name]:
      this.runTaskHelper(c, deps, seen)
  deps.add(taskname)
```

#### Detecting cycles
To detect a cycle we use `DFS` depth first search algorithm basically going from one node as deep as we can go for each of its neigbours and `Graph coloring`. [Youtube Lecture](https://www.youtube.com/watch?v=rKQaZuoUR4M)

Explanation from geeksforgeeks
```
    WHITE : Vertex is not processed yet.  Initially
            all vertices are WHITE.

    GRAY : Vertex is being processed (DFS for this 
        vertex has started, but not finished which means
        that all descendants (ind DFS tree) of this vertex
        are not processed yet (or this vertex is in function
        call stack)

    BLACK : Vertex and all its descendants are 
            processed.

    While doing DFS, if we encounter an edge from current 
    vertex to a GRAY vertex, then this edge is back edge 
    and hence there is a cycle.
```

OK, back to nim

1- Defining colors

```Nimrod
type NodeColor = enum
  ncWhite, ncGray, ncBlack
```

2- Graph has Cycle
```Nimrod
proc graphHasCycle(graph: Table[string, seq[string]]): (bool, Table[string, string]) =
  var colors = initTable[string, NodeColor]()
  for node, deps in graph:
    colors[node] = ncWhite
  
  var parentMap = initTable[string, string]()
  var hasCycle = false 
  for node, deps in graph:
    parentMap[node] = "null"
    if colors[node] == ncWhite:
      hasCycleDFS(graph, node, colors, hasCycle, parentMap)
    if hasCycle:
      return (true, parentMap)
  return (false, parentMap)
```

3- Depth First Function

```Nimrod
proc hasCycleDFS(graph:Table[string, seq[string]] , node: string, colors: var Table[string, NodeColor], has_cycle: var bool, parentMap: var Table[string, string]) =
  if hasCycle:
      return
  colors[node] = ncGray 

  for dep in graph[node]:
    parentMap[dep] = node
    if colors[dep] == ncGray:
      hasCycle = true   
      parentMap["__CYCLESTART__"] = dep
      return
    if colors[dep] == ncWhite:  
      hasCycleDFS(graph, dep, colors, hasCycle, parentMap)
  colors[node] = ncBlack  

```

### What's next?

- support for variables
- recipes maybe using yaml file
- modules like ansible?