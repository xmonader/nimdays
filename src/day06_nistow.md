# Day 6: Manage your dotfiles easily with nistow
Today we will create a tool to manage our dotfiles easily.

## Dotfiles layout
```
        i3
        `-- .config
            `-- i3
                `-- config
```
So we have here a directory named i3 in the very top `indicates APP_NAME` and under it a tree of config paths. Here it means `config` file is supposed to be linked under `.config/i3/config` relative to `destination directory` 
> Home directory is the default destination.

## What do we expect?
```
➜  ~ nistow --help
    Stow 0.1.0
        -h | --help     : show help
        -v | --version  : show version
        --verbose       : verbose messages
        -s | --simulate : simulate stow operation
        -f | --force    : override old links
        -a | --app      : application path to stow
        -d | --dest     : destination to stow to
```
- `--simulate` flag used to simulate on the filesystem without actual linking
- `--app` application directory that's compatible with the dotfiles layoud described above.
- `--dest` destination to symlink files under, defaults to home dir.

```
nistow --app=/home/striky/wspace/dotfiles/localdir --dest=/tmp/tmpconf --verbose
```


## Implementation

```Nimrod
proc writeHelp() = 
    echo """
Stow 0.1.0 (Manage your dotfiles easily)

Allowed arguments:
    -h | --help     : show help
    -v | --version  : show version
    --verbose       : verbose messages
    -s | --simulate : simulate stow operation
    -f | --force    : override old links
    -a | --app      : application path to stow
    -d | --dest     : destination to stow to

    """
```
`writeHelp` is a simple proc to write help string to the stdout

```Nimrod
proc writeVersion() =
    echo "Stow version 0.1.0"
```
To write version

```Nimrod
proc cli*() =
```
Entry point for out commandline application

```Nimrod
  var 
    simulate, verbose, force: bool = false
    app, dest: string = ""
```
Variables represents various options we allow in the application.

```Nimrod
  if paramCount() == 0:
    writeHelp()
    quit(0)
```
If no arguments passed we will write the help string and `exit` or `quit` according to nim with `exit status` 0

```Nimrod
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
        of "simulate", "s": simulate = true
        of "verbose": verbose = true
        of "force", "f": force = true
        of "app", "a": app = val
        of "dest", "d": dest = val 
        else:
          discard
    else:
      discard 
```
Here we parse the commandline string using `getopt`.
```Nimrod
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
```
So for `--app=/home/striky/dotfiles/i3 -f`
kind for `--app` is `cmdLongOption` and for `-f` is `cmdShortOption`
key for `--app` is `app` and for `-f` is `f`
val for `--app` is `/home/striky/dotfiles/i3`
val for `-f` we set to `true` in our parsing, because it's mainly like a switch `boolean` if it exists it means we want it set to true.

```Nimrod
  if dest.isNilOrEmpty():
    dest = getHomeDir()
```
Here we set default `dest` to homeDir
```Nimrod
  if app.isNilOrEmpty():
    echo "Make sure to provide --app flags"
    quit(1)
```
Here we exit with error `exit status` 1 if app isn't set.

```Nimrod
  try:
    stow(getLinkableFiles(appPath=app, dest=dest), simulate=simulate, verbose=verbose, force=force)
  except ValueError:
    echo "Error happened: " & getCurrentExceptionMsg()
```
Here we try to stow all the linkable files in `app` dir to `dest` dir and pass all the options we collected from the command line arguments `simulate`, `verbose`, `force`, and wrapped around `try/except` to show error to the user

```Nimrod
when isMainModule:
  cli()
```
invoke our entry point `cli` if this module is the main module.


OK! back to stow and getLinkableFiles

We start with `getLinkableFiles`. Remember the dotfiles hierarchy?
```
    # appPath: application's dotfiles directory
    #     we expect dir to have the hierarchy.
    #     i3
    #     `-- .config
    #         `-- i3
    #         `-- config
```
We want to get all the files in there with full path and the link file to each one will be exactly the same except for the `appPath` name will be changed to `dest` path

```
[/home/striky/wspace/dotfiles/i3]/.config/i3/config -> [/home/striky]/.config/i3/config
__________________appPath________                      _____dest____
```

```Nimrod
type
  LinkInfo = tuple[original:string, dest:string] 
```
Simple type to represent the original path and where to symlink to

```Nimrod
proc getLinkableFiles*(appPath: string, dest: string=expandTilde("~")): seq[LinkInfo] =

    # collects the linkable files in a certain app.

    # appPath: application's dotfiles directory
    #     we expect dir to have the hierarchy.
    #     i3
    #     `-- .config
    #         `-- i3
    #         `-- config

    # dest: destination of the link files : default is the home of user.
```
`getLinkableFiles` is a proc takes `appPath` and `dest` and returns a `seq` of LinkInfo contains this transformation for each file.

```
[/home/striky/wspace/dotfiles/i3]/A_FILE_PATH -> [/home/striky]A_FILE_PATH
__________________apppath________                _____dest____
```

```Nimrod
  var appPath = expandTilde(appPath)
  if not dirExists(appPath):
    raise newException(ValueError, fmt("App path {appPath} doesn't exist."))
  var linkables = newSeq[LinkInfo]()
  for filepath in walkDirRec(appPath, yieldFilter={pcFile}):
    let linkpath = filepath.replace(appPath, dest)
    var linkInfo : LinkInfo = (original:filepath, dest:linkpath)
    linkables.add(linkInfo)
  return linkables
```
Here, we walk over the `appPath` dir using `walkDirRec` and specify in `yieldFilter` argument that we're interested in `pcFile` "file path component", just call it entries of type regular file.


```Nimrod
proc stow(linkables: seq[LinkInfo], simulate: bool=true, verbose: bool=true, force: bool=false) = 
    # Creates symoblic links and related directories

    # linkables is a list of tuples (filepath, linkpath) : List[Tuple[file_path, link_path]]
    # simulate does simulation with no effect on the filesystem: bool
    # verbose shows log messages: bool

  for linkinfo in linkables:
    let (filepath, linkpath) = linkinfo
    if verbose:
      echo(fmt("Will link {filepath} -> {linkpath}"))

    if not simulate:
      createDir(parentDir(linkpath))
      if not fileExists(linkpath):
        createSymlink(filepath, linkpath)
      else:
        if force:
          removeFile(linkpath)
          createSymlink(filepath, linkpath)
        else:
          if verbose:
            echo(fmt("Skipping linking {filepath} -> {linkpath}"))
```
stow is pretty easy procedure, it takes in a list of `LinksInfo` that has all the information (original filename and destination symlink) and does the symlinking based on if it's not a simulation and prints the messages if verbose is set to true

Feel free to send improvements to this tutorial or nistow :)

[Complete source code](https://github.com/xmonader/nistow) available here https://github.com/xmonader/nistow