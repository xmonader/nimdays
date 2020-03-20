# Day 3: Talking to C (FFI and libmagic)

Libmagic is a magic number recognition library, remember everytime you called `file` utility on a file to know its type?

```
➜  file /usr/bin/rm
/usr/bin/rm: ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 3.2.0, BuildID[sha1]=cbae26b2a032b1ce3129d56aee2bcf70dd8deeb0, stripped
➜  nim-magic file /
/: directory
➜  file /usr/include/stdio.h
/usr/include/stdio.h: C source, ASCII text
```

## What to expect?
```Nimrod
import magic

echo magic.guessFile("/usr/bin/rm")
```
The output should be something like
```
ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 3.2.0, BuildID[sha1]=cbae26b2a032b1ce3129d56aee2bcf70dd8deeb0, stripped
```

## Implementation
[FFI Chapter](https://livebook.manning.com/#!/book/nim-in-action/chapter-8/1) of [Nim in Action](https://www.manning.com/books/nim-in-action) is freely available.

### Step 0: Imports
```Nimrod
from os import fileExists, expandFilename
```

### Step 1: Get the library info
Well, libmagic has `libmagic.so` in your library path `/usr/lib/libmagic.so` and a header file `magic.h` in `/usr/include/magic.h`.
create a constant for the libmagic library name.
```Nimrod
const libName* = "libmagic.so"
```

### Step 2: Extract constants
We should extract the constants from the header

```c
#define MAGIC_NONE              0x0000000 /* No flags */
#define MAGIC_DEBUG             0x0000001 /* Turn on debugging */
#define MAGIC_SYMLINK           0x0000002 /* Follow symlinks */
#define MAGIC_COMPRESS          0x0000004 /* Check inside compressed files */
#define MAGIC_DEVICES           0x0000008 /* Look at the contents of devices */
#define MAGIC_MIME_TYPE         0x0000010 /* Return the MIME type */
#define MAGIC_CONTINUE          0x0000020 /* Return all matches */
#define MAGIC_CHECK             0x0000040 /* Print warnings to stderr */
....

```

So in nim It'd be something like this
```Nimrod
const  MAGIC_NONE*  = 0x000000                 # No flags 
const  MAGIC_DEBUG* = 0x000001                 # Turn on debugging 
const  MAGIC_SYMLINK* = 0x000002                 # Follow symlinks 
const  MAGIC_COMPRESS* = 0x000004                # Check inside compressed files 
const  MAGIC_DEVICES* = 0x000008                 # Look at the contents of devices 
const  MAGIC_MIME_TYPE* = 0x000010            # Return only the MIME type 
const  MAGIC_CONTINUE* = 0x000020             # Return all matches 
const  MAGIC_CHECK* = 0x000040                 # Print warnings to stderr 
const  MAGIC_PRESERVE_ATIME* = 0x000080        # Restore access time on exit 
const  MAGIC_RAW* = 0x000100                    # Don't translate unprint chars 
const  MAGIC_ERROR* = 0x000200                 # Handle ENOENT etc as real errors 
const  MAGIC_MIME_ENCODING* = 0x000400         # Return only the MIME encoding 
const  MAGIC_NO_CHECK_COMPRESS* = 0x001000     # Don't check for compressed files 
const  MAGIC_NO_CHECK_TAR* = 0x002000         # Don't check for tar files 
const  MAGIC_NO_CHECK_SOFT* = 0x004000         # Don't check magic entries 
const  MAGIC_NO_CHECK_APPTYPE* = 0x008000        # Don't check application type 
const  MAGIC_NO_CHECK_ELF* = 0x010000            # Don't check for elf details 
const  MAGIC_NO_CHECK_ASCII* = 0x020000         # Don't check for ascii files 
const  MAGIC_NO_CHECK_TOKENS* = 0x100000         # Don't check ascii/tokens 
```


### Step 3: Extract the types

```typedef struct magic_set *magic_t;```
so the only type we have is a pointer to some struct (object)

```Nimrod
type Magic = object
type MagicPtr* = ptr Magic 
```

### Step 4: Extract procedures
```c
magic_t magic_open(int);
void magic_close(magic_t);

const char *magic_getpath(const char *, int);
const char *magic_file(magic_t, const char *);
const char *magic_descriptor(magic_t, int);
const char *magic_buffer(magic_t, const void *, size_t);

const char *magic_error(magic_t);
int magic_getflags(magic_t);
int magic_setflags(magic_t, int);

int magic_version(void);
int magic_load(magic_t, const char *);
int magic_load_buffers(magic_t, void **, size_t *, size_t);

int magic_compile(magic_t, const char *);
int magic_check(magic_t, const char *);
int magic_list(magic_t, const char *);
int magic_errno(magic_t);
```
we only care about `magic_open`, `magic_load`, `magic_close`, `magic_file`, `magic_error`

```Nimrod
# magic_t magic_open(int);
proc magic_open(i:cint) : MagicPtr {.importc, dynlib:libName.}
```
`magic_open` is a proc declared in dynamic lib `libmagic.so`, that is takes a cint "compatible c int" `i` and returns a `MagicPtr`.

From the manpage 
> The function magic_open() creates a magic cookie pointer and returns it.  It returns NULL if there was an error allocating the magic cookie.  The flags argument specifies how the other magic functions should behave


```Nimrod
# void magic_close(magic_t);
proc magic_close(p:MagicPtr): void {.importc,  dynlib:libName.}
```
`magic_close` is a proc declared in dynlib `libmagic.so` and takes an argumnet p of type `MagicPtr` and returns `void`

From the manpage
> The magic_close() function closes the magic(5) database and deallocates any resources used.

```Nimrod
#int magic_load(magic_t, const char *);
proc magic_load(p:MagicPtr, s:cstring) : cint {.importc, dynlib: libName.}
```
`magic_load` is a proc declared in dynlib `libmagic.so` takes argument p of type `MagicPtr` and a `cstring` "compatible c string" `s` and returns a `cint`

From manpage:
> The magic_load() function must be used to load the colon separated list of database files passed in as filename, or NULL for the default database
     file before any magic queries can performed.

```Nimrod
#int magic_errno(magic_t);
proc magic_error(p: MagicPtr) : cstring  {.importc, dynlib:libName.}
```
`magic_errno` is a proc declared in dynlib `libmagic.so` and takes argument p of type `MagicPtr` and returns a `cstring`

From manpage
> The magic_error() function returns a textual explanation of the last error, or NULL if there was no error.


```Nimrod
#const char *magic_file(magic_t, const char *);
proc magic_file(p:MagicPtr, filepath: cstring): cstring {.importc, dynlib: libName.} 
```
`magic_file` is proc declared in dynlib `libmagic.so` takes argument p of type `MagicPtr` and a filepath of type `cstring` and returns a `cstring`

From manpage:
> The magic_file() function returns a textual description of the contents of the filename argument, or NULL if an error occurred.  If the filename is NULL, then stdin is used.


### Step 5: Friendly API
It'd be annoying for people to write C code and take care of pointers and such in a higher level language like nim

So let's expose a proc `guessFile` takes a filepath and flags and internally use the functions we exposed through the FFI in the previous step.

```Nimrod
proc guessFile*(filepath: string, flags: cint = MAGIC_NONE): string =
    var mt : MagicPtr
    mt = magic_open(flags)
    discard magic_load(mt, nil)

    if fileExists(expandFilename(filepath)):
        result = $magic_file(mt, cstring(filepath))
    magic_close(mt)
```
Only one note here to convert from `cstring` to `string` we use the `toString` operator `$` 
```
        result = $magic_file(mt, cstring(filepath))
```
