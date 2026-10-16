-- tinyfiles.lua
-- Tiny file operations + simple YAML and JSON + wait, in one file.
--
-- In another file:
--   require("tinyfiles")
--   writefile("data.txt", "Hello!")
--
-- Functions: wait, createfile, writefile, appendfile, readfile,
--            writekey, addvalue, readvalue, removekey,
--            selectyaml, selectjson, file


---------------------------------------------------------------
-- WAIT
---------------------------------------------------------------

-- wait(1) pauses for 1 second, wait(0.5) for half a second.
-- Plain Lua has no sleep, so this loops until the time is up.
-- It freezes the script and uses CPU while waiting.
function wait(seconds)
    seconds = seconds or 0
    local stop = os.clock() + seconds
    while os.clock() < stop do end
    return seconds
end


---------------------------------------------------------------
-- BASIC FILES
---------------------------------------------------------------

-- Make an empty file (never wipes an existing one)
function createfile(filename)
    local f = assert(io.open(filename, "a"))
    f:close()
end

-- Overwrite a file (creates it if missing)
function writefile(filename, content)
    local f = assert(io.open(filename, "w"))
    f:write(content)
    f:close()
end

-- Add to the end of a file (creates it if missing)
function appendfile(filename, content)
    local f = assert(io.open(filename, "a"))
    f:write(content)
    f:close()
end

-- Read a whole file and return it as a string
function readfile(filename)
    local f = assert(io.open(filename, "r"))
    local content = f:read("*a")
    f:close()
    return content
end


---------------------------------------------------------------
-- YAML (internal)
---------------------------------------------------------------

local function readlines(filename)
    local t = {}
    local f = io.open(filename, "r")
    if f then
        for line in f:lines() do t[#t + 1] = line end
        f:close()
    end
    return t
end

local function savelines(filename, t)
    local f = assert(io.open(filename, "w"))
    if #t > 0 then f:write(table.concat(t, "\n"), "\n") end
    f:close()
end

local function findkey(t, key)
    for i, line in ipairs(t) do
        if line:match("^([%w_-]+):") == key then return i end
    end
end

local function tovalue(v)
    if v == "true" then return true end
    if v == "false" then return false end
    if tonumber(v) then return tonumber(v) end
    local q = v:match('^"(.*)"$')
    if q then
        return (q:gsub("\\(.)", function(c) return c == "n" and "\n" or c end))
    end
    return v:match("^'(.*)'$") or v
end

-- Turns a Lua value into the text written after "key: "
--   "Mahi"      -> Mahi        (no quotes, unless they're needed)
--   '"Mahi"'    -> "Mahi"      (you typed the quotes, so they're kept)
local function tostr(v)
    if type(v) ~= "string" then return tostring(v) end

    -- you wrote the quotes yourself: keep exactly what you typed
    if v:match('^"[^"]*"$') or v:match("^'[^']*'$") then return v end

    -- quotes are needed or it would be read back as something else
    local needsQuotes =
        v == "" or v == "true" or v == "false" or tonumber(v) ~= nil
        or v:match("^%s") or v:match("%s$")
        or v:find("[#\n]") or v:find(": ", 1, true) or v:match(":$")
        or v:match("^[\"']")

    if needsQuotes then
        v = v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
        return '"' .. v .. '"'
    end
    return v
end

local yaml = {}

function yaml.writekey(filename, key)
    local t = readlines(filename)
    if not findkey(t, key) then
        t[#t + 1] = key .. ":"
        savelines(filename, t)
    end
end

function yaml.addvalue(filename, key, value)
    local t = readlines(filename)
    local line
    if type(value) == "table" then
        line = key .. ":"
    else
        line = key .. ": " .. tostr(value)
    end
    local i = findkey(t, key)
    if i then t[i] = line else t[#t + 1] = line end
    savelines(filename, t)
end

function yaml.readvalue(filename, key)
    local t = readlines(filename)
    local i = findkey(t, key)
    if not i then return nil end
    local v = t[i]:match("^[%w_-]+:%s*(.-)%s*$")
    if v == "" then return nil end
    return tovalue(v)
end

function yaml.removekey(filename, key)
    local t = readlines(filename)
    local i = findkey(t, key)
    if i then
        table.remove(t, i)
        savelines(filename, t)
    end
end


---------------------------------------------------------------
-- JSON (internal)
---------------------------------------------------------------

local json = {}

local function jsonescape(s)
    return (s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        if c == "\n" then return "\\n" end
        if c == "\r" then return "\\r" end
        if c == "\t" then return "\\t" end
        return string.format("\\u%04x", c:byte())
    end))
end

local escapes = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function jsonunescape(s)
    local out, i = {}, 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == "\\" then
            local n = s:sub(i + 1, i + 1)
            local hex = s:sub(i + 2, i + 5)
            if n == "u" and hex:match("^%x%x%x%x$") then
                out[#out + 1] = utf8 and utf8.char(tonumber(hex, 16)) or "?"
                i = i + 6
            else
                out[#out + 1] = escapes[n] or n
                i = i + 2
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Reads a flat JSON object into an ordered list of { key = ..., raw = ... }.
-- "raw" is the value's JSON text, so nested values are kept untouched on save.
local function jsonparse(filename)
    local f = io.open(filename, "r")
    local text = f and f:read("*a") or ""
    if f then f:close() end

    local entries = {}
    local pos = 1

    local function fail()
        error("tinyfiles: invalid JSON in " .. filename, 0)
    end
    local function skip()
        pos = text:find("%S", pos) or #text + 1
    end
    local function readstring() -- pos is on the opening quote
        local i = pos + 1
        while true do
            local ch = text:sub(i, i)
            if ch == "" then fail() end
            if ch == "\\" then
                i = i + 2
            elseif ch == '"' then
                break
            else
                i = i + 1
            end
        end
        local raw = text:sub(pos, i)
        pos = i + 1
        return raw
    end
    local function readraw()
        local ch = text:sub(pos, pos)
        if ch == '"' then return readstring() end
        if ch == "{" or ch == "[" then
            local start, depth = pos, 0
            repeat
                local c = text:sub(pos, pos)
                if c == "" then fail() end
                if c == '"' then
                    readstring()
                else
                    if c == "{" or c == "[" then
                        depth = depth + 1
                    elseif c == "}" or c == "]" then
                        depth = depth - 1
                    end
                    pos = pos + 1
                end
            until depth == 0
            return text:sub(start, pos - 1)
        end
        local raw = text:match("^[^,}%s]+", pos)
        if not raw then fail() end
        pos = pos + #raw
        return raw
    end

    skip()
    if pos > #text then return entries end -- empty file
    if text:sub(pos, pos) ~= "{" then fail() end
    pos = pos + 1
    skip()
    if text:sub(pos, pos) == "}" then return entries end

    while true do
        skip()
        if text:sub(pos, pos) ~= '"' then fail() end
        local key = jsonunescape(readstring():sub(2, -2))
        skip()
        if text:sub(pos, pos) ~= ":" then fail() end
        pos = pos + 1
        skip()
        entries[#entries + 1] = { key = key, raw = readraw() }
        skip()
        local c = text:sub(pos, pos)
        pos = pos + 1
        if c == "}" then break end
        if c ~= "," then fail() end
    end
    return entries
end

local function jsonsave(filename, entries)
    local out = {}
    for _, e in ipairs(entries) do
        out[#out + 1] = '  "' .. jsonescape(e.key) .. '": ' .. e.raw
    end
    local f = assert(io.open(filename, "w"))
    if #out == 0 then
        f:write("{}\n")
    else
        f:write("{\n", table.concat(out, ",\n"), "\n}\n")
    end
    f:close()
end

local function jsonencode(v)
    local t = type(v)
    if t == "string" then return '"' .. jsonescape(v) .. '"' end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return tostring(v)
    end
    return "null" -- a table ({}) makes an empty key
end

local function jsondecode(raw)
    if raw == "true" then return true end
    if raw == "false" then return false end
    if raw == "null" then return nil end
    local n = tonumber(raw)
    if n then return n end
    if raw:sub(1, 1) == '"' then return jsonunescape(raw:sub(2, -2)) end
    return nil -- nested objects and arrays can't be read, only kept
end

local function jsonfind(entries, key)
    for i, e in ipairs(entries) do
        if e.key == key then return i end
    end
end

function json.writekey(filename, key)
    local e = jsonparse(filename)
    if not jsonfind(e, key) then
        e[#e + 1] = { key = key, raw = "null" }
        jsonsave(filename, e)
    end
end

function json.addvalue(filename, key, value)
    local e = jsonparse(filename)
    local raw = jsonencode(value)
    local i = jsonfind(e, key)
    if i then e[i].raw = raw else e[#e + 1] = { key = key, raw = raw } end
    jsonsave(filename, e)
end

function json.readvalue(filename, key)
    local e = jsonparse(filename)
    local i = jsonfind(e, key)
    if not i then return nil end
    return jsondecode(e[i].raw)
end

function json.removekey(filename, key)
    local e = jsonparse(filename)
    local i = jsonfind(e, key)
    if i then
        table.remove(e, i)
        jsonsave(filename, e)
    end
end


---------------------------------------------------------------
-- KEYS AND VALUES (YAML or JSON, picked by the file name)
---------------------------------------------------------------

-- A file ending in .json is treated as JSON, anything else as YAML.
local function backend(filename, force)
    if force == "json" then return json end
    if force == "yaml" then return yaml end
    if filename:lower():match("%.json$") then return json end
    return yaml
end

-- Add an empty key
function writekey(filename, key)
    return backend(filename).writekey(filename, key)
end

-- Set a key's value (creates the key if it's missing)
-- addvalue(file, "name", {}) makes an empty key
function addvalue(filename, key, value)
    return backend(filename).addvalue(filename, key, value)
end

-- Get a key's value (nil if missing or empty)
function readvalue(filename, key)
    return backend(filename).readvalue(filename, key)
end

-- Delete a key
function removekey(filename, key)
    return backend(filename).removekey(filename, key)
end

local function selectfile(filename, force)
    createfile(filename)
    local b = backend(filename, force)
    return setmetatable({}, {
        __index = function(_, key)
            return b.readvalue(filename, key)
        end,
        __newindex = function(_, key, value)
            if value == nil then
                b.removekey(filename, key)
            else
                b.addvalue(filename, key, value)
            end
        end,
    })
end

-- Variable linked to a file:
--   config = selectyaml("config.yml")   (or selectjson("config.json"))
--   config.name = "Mahi"     -- saves to the file
--   print(config.name)       -- reads from the file
--   config.name = {}         -- makes an empty key
--   config.name = nil        -- deletes the key
function selectyaml(filename) return selectfile(filename, "yaml") end
function selectjson(filename) return selectfile(filename, "json") end


---------------------------------------------------------------
-- FILE.PARENT (like script.Parent in Roblox)
---------------------------------------------------------------

-- "file" is the script you are writing in, and file.parent is its folder.
-- Call a folder with a file name to get the path to that file:
--
--   file.parent("data.txt")                -- data.txt next to your script
--   file.parent.parent("data.txt")         -- one folder above your script
--   file.parent.parent.parent("data.txt")  -- add as many .parent as you want
--
-- Use it anywhere a file name goes:
--   writefile(file.parent("data.txt"), "Hi")
--   config = selectyaml(file.parent.parent("config.yml"))
--
-- This follows where your script file is, not where you ran "lua" from.
local function makefolder(dir, levels)
    return setmetatable({}, {
        __index = function(_, k)
            if k == "parent" then return makefolder(dir, levels + 1) end
        end,
        __call = function(_, path)
            return dir .. "/" .. string.rep("../", levels) .. (path or "")
        end,
    })
end

file = setmetatable({}, {
    __index = function(_, k)
        if k ~= "parent" then return nil end
        local dir = "."
        if debug and debug.getinfo then
            local info = debug.getinfo(2, "S") -- the script that used file.parent
            local src = info and info.source or ""
            if src:sub(1, 1) == "@" then
                dir = src:sub(2):match("^(.*)[/\\]") or "."
                if dir == "" then dir = "/" end
            end
        end
        return makefolder(dir, 0)
    end,
})


---------------------------------------------------------------
-- EXPORT
---------------------------------------------------------------

-- The functions above are global, so require("tinyfiles") is enough.
-- They are also returned, so this works too:
--   local tf = require("tinyfiles")
--   tf.writefile("data.txt", "Hello!")
return {
    wait = wait,
    createfile = createfile,
    writefile = writefile,
    appendfile = appendfile,
    readfile = readfile,
    writekey = writekey,
    addvalue = addvalue,
    readvalue = readvalue,
    removekey = removekey,
    selectyaml = selectyaml,
    selectjson = selectjson,
    file = file,
}
