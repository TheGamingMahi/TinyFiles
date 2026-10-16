# TinyFiles

A tiny Lua library for files, simple YAML and JSON, and Roblox-style `wait()` and `file.parent`.
One file, no dependencies, plain Lua.

## Install

Copy `tinyfiles.lua` into your project, next to your script. Then at the top of your script:

```lua
require("tinyfiles")
```

Run your script from its folder:

```
lua main.lua
```

## Files

```lua
createfile("data.txt")              -- empty file (never wipes an existing one)
writefile("data.txt", "Hello!")     -- overwrite (creates the file if missing)
appendfile("data.txt", "\nWorld!")  -- add to the end (creates the file if missing)

local text = readfile("data.txt")   -- read it into a variable
print(text)
```

## YAML

The easiest way is `selectyaml`. It gives you a variable that is linked to the file,
so assigning saves straight to the file and reading pulls from the file.

```lua
config = selectyaml("config.yml")   -- creates the file if missing

config.name = "Mahi"                -- name: Mahi
config.quoted = '"Mahi"'            -- quoted: "Mahi"   (you typed the quotes, so they stay)
config.version = 2                  -- version: 2
config.enabled = true               -- enabled: true
config.empty = {}                   -- empty:           (empty key)

print(config.name)                  -- Mahi
local v = config.version            -- save it as a variable
print(v + 1)                        -- 3

config.enabled = nil                -- deletes the key
```

Strings only get quotes when they need them, so they read back as the same thing:
`"true"`, `"123"`, `""`, and values containing `: ` or `#` are quoted automatically.

The same thing as plain functions:

```lua
writekey("config.yml", "title")             -- empty key
addvalue("config.yml", "title", "Cool")     -- title: Cool
local t = readvalue("config.yml", "title")  -- Cool
```

## JSON

JSON works the same way as YAML. Use `selectjson`:

```lua
config = selectjson("config.json")  -- creates the file if missing

config.name = "Mahi"                -- "name": "Mahi"
config.version = 2                  -- "version": 2
config.enabled = true               -- "enabled": true
config.empty = {}                   -- "empty": null   (empty key)

print(config.name)                  -- Mahi
config.enabled = nil                -- deletes the key
```

The plain functions pick the format from the file name. A file ending in `.json` is JSON,
anything else is YAML:

```lua
addvalue("config.json", "name", "Mahi")      -- JSON
addvalue("config.yml", "name", "Mahi")       -- YAML
print(readvalue("config.json", "name"))      -- Mahi
removekey("config.json", "name")             -- delete a key
```

If a JSON file has nested objects or lists, they are kept as they are when you save,
but you can only read and change the simple top-level values.

## wait

```lua
wait(2)     -- pause 2 seconds
wait(0.5)   -- half a second
```

## file.parent

Works like `script.Parent` in Roblox. `file` is the script you are writing in,
and `file.parent` is its folder. Add `.parent` again to go up another folder.
Call it with a file name to get the path.

```lua
writefile(file.parent("data.txt"), "Hi")          -- next to your script
writefile(file.parent.parent("data.txt"), "Hi")   -- one folder above
print(readfile(file.parent.parent.parent("data.txt")))  -- as many as you want

config = selectyaml(file.parent("config.yml"))
```

It follows where your script is, not where you ran `lua` from.

## Functions

| Function | What it does |
|---|---|
| `createfile(file)` | Make an empty file |
| `writefile(file, text)` | Overwrite a file |
| `appendfile(file, text)` | Add text to the end of a file |
| `readfile(file)` | Return the file's contents |
| `selectyaml(file)` | Variable linked to a YAML file |
| `selectjson(file)` | Variable linked to a JSON file |
| `writekey(file, key)` | Add an empty key (YAML or JSON, by file name) |
| `addvalue(file, key, value)` | Set a key's value |
| `readvalue(file, key)` | Get a key's value |
| `removekey(file, key)` | Delete a key |
| `wait(seconds)` | Pause the script |
| `file.parent` | Folder of your script (chain `.parent` to go up) |

You can also keep everything out of your global names:

```lua
local tf = require("tinyfiles")
tf.writefile("data.txt", "Hello!")
```

## Limits

- **YAML and JSON are flat only.** Simple `key: value` pairs. No nesting, lists, or multiline values. (Nested JSON is kept untouched when you save, but can't be read or edited.)
- **Saving JSON rewrites the file** with one key per line, so your own spacing is reformatted. Key order stays the same.
- **Inline comments aren't understood.** `name: Mahi # hi` reads as the whole text.
- **`selectyaml` and `selectjson` can't be looped.** `pairs(config)` won't list keys, because the data stays in the file.
- **Strings need quotes in Lua**, as usual. `config.name = Mahi` looks for a variable called `Mahi`.
- **`wait` freezes your script while it waits** and uses CPU, because plain Lua has no sleep.
- **`file` is a name this library uses.** A local variable called `file` in your own code hides it.

## License

Do whatever you want with it. Made for fun.
