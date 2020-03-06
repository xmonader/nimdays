# Day 20: CacheTable


Today we will implement an expiry feature on keys over nim tables


## What to expect

```nim
  var c = newCacheTable[string, string](initDuration(seconds = 2))
  c.setKey("name", "ahmed", initDuration(seconds = 10))
  c.setKey("color", "blue", initDuration(seconds = 5))
  c.setKey("akey", "a value", DefaultExpiration)
  c.setKey("akey2", "a value2", DefaultExpiration)

  c.setKey("lang", "nim", NeverExpires)
```
- Here will will create a new Table from `string` to `string`
- we are allowed to set the default expiration to `2 seconds` using Duration object globally on the Table `newCacheTable[string, string](initDuration(seconds = 2))`
- We are allowed to override the default expiration when `setKey` by passing a duration object
- We are allowed to set a key to `NeverExpires`


Here's a small example to see the internals of execution
```nim

  for i in countup(0, 20):
    echo "has key name? " & $c.hasKey("name")
    echo $c.getCache
    echo $c.get("name")
    echo $c.get("color")
    echo $c.get("lang")
    echo $c.get("akey")
    echo $c.get("akey2")
    os.sleep(1*1000)

```


### Implementation

#### Imports

```nim
import tables, times, os, options, locks
```


```nim
type Expiration* = enum NeverExpires, DefaultExpiration
```
We have to types of Expiration
- `NeverExpires` basically the key stays there forever.
- `DefaultExpiration` to use whatever global expiration value defined on the Table

```nim
type Entry*[V] = object
  value*: V
  ttl*: int64

type CacheTable*[K, V] = ref object
  cache: Table[K, Entry[V]]
  lock*: locks.Lock
  defaultExpiration*: Duration

proc newCacheTable*[K, V](defaultExpiration = initDuration(
    seconds = 5)): CacheTable[K, V] =
  ## Create new CacheTable
  result = CacheTable[K, V]()
  result.cache = initTable[K, Entry[V]]()
  result.defaultExpiration = defaultExpiration
```
The only difference between our `CacheTable` and Nim's Table is the entries are keeping track of `Time To Live TTL`

- Entry is a Generic entry we store in the CacheTable that has a value of a type `V` and keeps track of its `ttl`
- CacheTable is a Table from keys of type `K` to values of of type `Entry[V]` and keeps track of default expiration
- newCacheTable is a helper to create a new CacheTable.


```nim
proc getCache*[K, V](t: CacheTable[K, V]): Table[K, Entry[V]] =
  result = t.cache
```
a helper to get the underlying Table



```nim
proc setKey*[K, V](t: CacheTable[K, V], key: K, value: V, d: Duration) =
  ## Set ``Key`` of type ``K`` (needs to be hashable) to ``value`` of type ``V`` with duration ``d``
  let rightnow = times.getTime()
  let rightNowDur = times.initDuration(seconds = rightnow.toUnix(),
      nanoseconds = rightnow.nanosecond)

  let ttl = d.inNanoseconds + rightNowDur.inNanoseconds
  let entry = Entry[V](value: value, ttl: ttl)
  t.cache.add(key, entry)
```
a helper to set a new key in the CacheTable with a specific Duration


```nim
proc setKey*[K, V](t: CacheTable[K, V], key: K, value: V,
    expiration: Expiration = NeverExpires) =
  ## Sets key with `Expiration` strategy
  var entry: Entry[V]
  case expiration:
  of NeverExpires:
    entry = Entry[V](value: value, ttl: 0)
    t.cache.add(key, entry)
  of DefaultExpiration:
    t.setKey(key, value, d = t.defaultExpiration)
```
a helper to set key based on an Expiration strategy
- if `NeverExpires` : ttl should be 0
- if `DefaultExpiration`: ttl will be the same as the Cachetable `defaultExpiration` duration


```nim
proc setKeyWithDefaultTtl*[K, V](t: CacheTable[K, V], key: K, value: V) =
  ## Sets a key with default Ttl duration.
  t.setKey(key, value, DefaultExpiration)
```
sets a key to value with default expiration

```nim
proc hasKey*[K, V](t: CacheTable[K, V], key: K): bool =
  ## Checks if `key` exists in cache
  result = t.cache.hasKey(key)
```
Check if the cache underneath has a specific key

```nim
proc isExpired(ttl: int64): bool =
  if ttl == 0:
    # echo "duration 0 never expires."
    result = false
  else:
    let rightnow = times.getTime()
    let rightNowDur = times.initDuration(seconds = rightnow.toUnix(),
        nanoseconds = rightnow.nanosecond)
    # echo "Now is : " & $rightnow
    result = rightnowDur.inNanoseconds > ttl
```
Helper to check if a `ttl` expired relative to the time right now.

```nim
proc get*[K, V](t: CacheTable[K, V], key: K): Option[V] =
  ## Get value of `key` from cache
  var entry: Entry[V]
  try:
      entry = t.cache[key]
  except:
    return none(V)

  # echo "getting entry for key: " & key  & $entry
  if not isExpired(entry.ttl):
    # echo "k: " & key & " didn't expire"
    return some(entry.value)
  else:
    # echo "k: " & key & " expired"
    del(t.cache, key)
    return none(V)
```

Getting a key from the cache to returns an `Option[V]` of the value of type `V` stored in the `Entry[V]`.

Thank you for reading! and please feel free to open an issue or a PR to improve to content of Nim Days :)