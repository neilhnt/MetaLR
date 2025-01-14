--
-- Utilities for NDH plugin
--

local LrApplication = import 'LrApplication'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'

verbose = false
verbose_flags = { }

-- returns true if continue, false to exit
-- Assumption that os.exit will kill the whole thing.
function debugmessage (module, str, flagname)
  if (verbose)  then
    if (flagname ~= nil) then
      if (verbose_flags[flagname] == nil) then
        verbose_flags[flagname] = true
      end
      if (verbose_flags[flagname]) then
	local proceed = LrDialogs.confirm(module .. " " .. flagname, str,  "Continue", "Cancel", "Finish " .. flagname)
	--                                      returns "continue"  "cancel", "other"
	if (proceed == "other") then -- "Finish"
	  verbose_flags[flagname] = false
	elseif (proceed == "cancel") then
	  assert(false, "Debug cancel " .. flagname)
	  return false
	end
      end
    else
      local proceed = LrDialogs.confirm(module, str,  "Continue", "Cancel", "Finish")
      --                                      returns "continue"  "cancel", "other"
      if (proceed == "other") then
	verbose = false
	return true
      elseif (proceed == "cancel") then
	assert(false, "Debug cancel")
	-- error("Debug cancel")
	return false
      end
    end
  end
  return true
end

function round(v)
  return math.floor(v+0.5)
end

function stringbuild(base, rest, join)
  if (join == nil) then
    join = "\n"
  end
  if (base == nil or base == "") then
    return rest
  else
    return base .. join .. rest
  end
end

function decimal(v)
  local sign = (v < 0) and -1 or 1
  local abs = v * sign
  local int = math.floor(abs)
  local frac = abs - int
  if (frac == 0) then
    return string.format("%+03d", int*sign)
  else
    return string.format("%+d.%02d", int*sign, frac*100)
  end
end

-- LrDialogs.message("NDH debug format", string.format("-1 %s, +2 %s, -1.5 %s, +2.75 %s, -10 %s, 22 %s",
-- 		       	     	      			decimal(-1.0),
-- 							       decimal(2.0),
-- 							               decimal(-1.5),
-- 								                 decimal(2.75),
-- 										          decimal(-10.0),
-- 											      decimal(22.0)))



local cocoaepoch = 978307200 -- Cocoa Core Data epoch correction - probably different for Windows?

function epochdate(d)
  if (d == nil) then
    return nil
  else
    return d + cocoaepoch
  end
end

local dbg = string.format("{ %f\n", 3.1415)

function format_table (metadata, all)
  if (metadata == nil) then
    return ""
  end
  local dbg = ' {\n'
  for k, v in pairs(metadata) do
    if (all or
        string.find(string.lower(k), "time") or
        string.find(string.lower(k), "gps") or
	string.find(string.lower(k), "date") or
	string.find(string.lower(k), "offset") or
	string.find(string.lower(k), "tude") or -- latitude longitude
	false) then
      if (type(v) == 'string') then
	dbg = dbg .. string.format("  %s=%s\n", k, v)
      elseif (type(v) == 'number') then
	dbg = dbg .. string.format("  %s=%f\n", k, v)
      elseif (type(v) == 'boolean') then
	if (v == true) then
	  dbg = dbg .. string.format("  %s=true\n", k)
	else
	  dbg = dbg .. string.format("  %s=false\n", k)
	end
      elseif (type(v) ~= 'table') then
        dbg = dbg .. "  [" .. type(v) .. "]\n"
      end
    end
    if (type(v) == 'table') then
      dbg = dbg .. string.format("%s=%s", k, format_table(v, all))
    end
  end
  dbg = dbg .. "}\n"
  return dbg
end

-- Parse time strings into epoch-times
-- "2020-09-11"
-- "2020-01-27T09:57:44-08:00"
-- "2018-01-01T00:35:57.962"
-- "2018-01-01T00:35:57.962+01
-- "2022-01-01T08:15:44Z"
-- "2022-11-06T16:41-05:00"
-- "6/1/2023 5:30 PM"
-- "6/1/2023"

-- These don't work, because they fail to account for os.date converting some dates with DST.
-- local utcoffset = os.time()-os.time(os.date("!*t"))
-- local utcoffset = -os.time({year=1970, month=1, day=1, hour=0, min=0, sec=0})

-- Copy to a main file...
-- for i, s in ipairs({"6/1/2023 5:30 PM", "2/1/2023 5:30 PM", "2/1/2023", "6/1/2023", "2020-09-11", "2020-01-27T09:57:44-08:00", "2018-01-01T00:35:57.962", "2018-01-01T00:35:57.962+01", "2022-01-01T08:15:44Z", "2022-11-06T16:41-05:00" }) do
--   local t, o = timefromstring(s)
--   local tt, oo = timefromisostring(s)
--   local whole = math.mod(t, (3600 * 24))
--   debugmessage("NDHutils", string.format("time %s --> %s %s / %s %s (%s) remains %d", s, t, o, tt, oo, stringfromtime(t), whole), "debug")
-- end


--
-- datetime (in !UTC) into string
function stringfromtime(t)
  -- return os.date("!%m/%d/%Y %H:%M:%S", t or 0) -- some dates have DST, so need instead to work in localtime.
  return os.date("%m/%d/%Y %H:%M:%S", t or 0)
end

function isdst(t)
  if (t == nil) then
    return false, 0
  end
  local tt1 = os.date("*t", t)
  local tt2 = os.date("!*t", t)
  local offset = os.time(tt1) - os.time(tt2)
  return tt1['isdst'], offset
end


-- Returns time and tzoffset (if available)
  -- Now UTC.
  -- Was Returns LOCALtime since epoch, but as long as execution doesn't span time change, won't matter.
  -- This would be the fix:  Corresponding fix is prefix os.date formats with a !
  -- From https://stackoverflow.com/questions/4105012/convert-a-string-date-to-a-timestamp
  -- local utcoffset = os.time()-os.time(os.date("!*t"))
  -- rt = t['year'] and os.time(t)+utcoffset) or nil

function timefromisostring (str, defaulttime)

  if (str == nil) then
    return nil, nil
  end

  -- Parse timestamp (returns LOCALtime since epoch, but as long as execution doesn't span time change, won't matter)
  local rt, ro, rest
  local t = { }

  -- Parse timestamp (returns LOCALtime since epoch, but as long as execution doesn't span time change, won't matter)
  t['year'], t['month'], t['day'], rest = string.match(str, "(%d%d%d%d)[\-\/](%d%d?)[\-\/](%d%d?)(.*)")
  t['hour'] = 0
  t['min'] = 0
  t['sec'] = 0
  if (defaulttime ~= nil) then
    t['hour'], t['min'], t['sec'] = string.match(defaulttime, "(%d%d):(%d%d):(%d%d)")
  end
  if (rest and rest ~= "") then
    local r
    t['hour'], r = string.match(rest, "[T ](%d%d)(.*)") 
    -- debugmessage("NDH", string.format("isostring1: %s; %s-%s-%sT%s:%s:%s + %s %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r, rest), "iso1")
    rest = r or rest
  end
  if (rest and rest ~= "") then
    local r
    t['min'], r = string.match(rest, ":(%d%d)(.*)")
    -- debugmessage("NDH", string.format("isostring2: %s; %s-%s-%sT%s:%s:%s + %s %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r, rest), "iso2")
    rest = r or rest
  end
  if (rest and rest ~= "") then
    local r
    -- t['sec'], r = string.match(rest, ":([%d%.]+)(.*)")
    t['sec'], r = string.match(rest, ":(%d+%.?%d*)(.*)")
    -- debugmessage("NDH", string.format("isostring3: %s; %s-%s-%sT%s:%s:%s + %s %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r, rest), "iso3")
    rest = r or rest
  end

  rt = (t['year'] and os.time(t)) or nil -- local time
  if (rt == nil) then
    debugmessage("NDHutils", string.format("Bad format ISO time %s", str), "NDH debug iso time")
    rt = 0
  end
  -- debugmessage("NDH", string.format("isostring: %s; %s-%s-%sT%s:%s:%s -> %s [%s]", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], rt, rest), "time offset")

  -- Parse offset (if any)
  -- Rest is the TimeOffset:
  -- 'Z' means 0
  if (rest ~= nil) then
    if (string.match(rest, "Z$")) then
      ro = 0 -- Remember to distinguish between unset and set to 0...
    else
      local os, oh, om = string.match(rest, "([%+%-])([%d]+):?(%d*)")
      if (os and oh and om) then
        ro = ((((os == '+') and 1) or ((os == '-') and -1)) * (oh * 3600 + ('0'..om) * 60))
      end
      -- debugmessage("NDH", string.format("isostringoffset: %s (%s): %s %s %s -> %s", str, rest, os, oh, om, ro), "time offset")
    end
  end

  -- Debug time parsing
  -- local dbg = str .. ' t = {'
  -- for k, v in pairs(t) do
  --    Dbg = Dbg .. String.Format("%s=%s ", k, v)
  -- end
  -- dbg = dbg .. '}'
  -- debugmessage("NDH debug timefromisostring", string.format("%s\ntime --> (%s) %d, offset %s%s%s --> %d",
  --                                                              str,          dbg,rt or 0,   os or '*', oh or '', om or '', ro or 0), "iso debug")

  return rt, ro
end

function timefromgpsstring(str,ostr)

  if (str == nil or ostr == nil) then
    return nil, nil
  end

  -- Parse timestamp (returns LOCALtime since epoch, but as long as execution doesn't span time change, won't matter
  local t = { }
  t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'] = string.match(str, "(%d%d%d%d):(%d%d):(%d%d) (%d%d):(%d%d):(%d%d)")
  local rt = t['year'] and os.time(t) or nil -- t['year'] ? os.time(t)+utcoffset : nil -- local time

  -- Parse offset (if any)
  local os, oh, om = string.match(ostr, "([%+%-])([%d]+):*(%d*)")
  local ro = os and ((((os == '+') and 1) or ((os == '-') and -1)) * (oh * 3600 + ('0'..om) * 60))

  -- Debug time parsing
  -- local dbg = str .. ' t = {'
  -- for k, v in pairs(t) do
  --    dbg = dbg .. string.format("%s=%s ", k, v)
  -- end
  -- dbg = dbg .. '}'
  -- debugmessage("NDH debug timefromgpsstring", string.format("%s\ntime --> (%s) %d, offset %s%s%s --> %d",
  --                                                              str,          dbg,rt or 0,   os or '*', oh or '', om or '', ro or 0), "isodebug")

  return rt, ro
end

-- timefromisostring("2020-01-27T09:57:44-01:15")
-- timefromisostring("2018-01-01T00:35:57.962")
-- timefromisostring("2018-01-01T00:35:57.962+01")

verbose_flags["time1"] = false
verbose_flags["time2"] = false
verbose_flags["time3"] = false
verbose_flags["offset"] = false

-- "2022-01-01T08:15:44Z"
-- "2022-11-06T16:41-05:00"
-- "6/1/2023 5:30 PM"
-- "6/1/2023"

function timefromstring (str, defaulttime)

  if (str == nil) then
    return nil, nil
  end
  if (defaulttime == nil) then
    defaulttime = "00:00:00"
  end

  local rt, ro, rest
  local t = { }

  -- "2022-01-01T08:15:44Z"
  -- "2022-11-06T16:41-05:00"

  -- Parse timestamp (returns LOCALtime since epoch, but as long as execution doesn't span time change, won't matter)
  t['year'], t['month'], t['day'], rest = string.match(str, "(%d%d%d%d)[\-\/](%d%d?)[\-\/](%d%d?)(.*)")
  if (t['year']~= nil) then
    t['hour'] = 0
    t['min'] = 0
    t['sec'] = 0
    if (rest == nil or rest == "") then
      rest = defaulttime
    end
    if (rest and rest ~= "") then
      local r
      t['hour'], r = string.match(rest, "[T ](%d%d)(.*)") 
      -- debugmessage("NDH", string.format("isostring1: %s; %s-%s-%sT%s:%s:%s + %s %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r, rest), "iso1")
      rest = r or rest
    end
    if (rest and rest ~= "") then
      local r
      t['min'], r = string.match(rest, ":(%d%d)(.*)")
      -- debugmessage("NDH", string.format("isostring2: %s; %s-%s-%sT%s:%s:%s + %s %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r, rest), "iso2")
      rest = r or rest
    end
    if (rest and rest ~= "") then
      local r
      t['sec'], r = string.match(rest, ":(%d+%.?%d*)(.*)")
      -- debugmessage("NDH", string.format("isostring3: %s; %s-%s-%sT%s:%s:%s + %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r), "iso3")
      rest = r or rest
    end

    rt = (t['year'] and os.time(t)) or nil -- local time
    if (rt == nil) then
      debugmessage("NDHutils", string.format("Bad format ISO time %s", str), "debug iso time")
      rt = 0
    end
    -- debugmessage("NDH", string.format("isostring: %s; %s-%s-%sT%s:%s:%s -> %s + %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], rt, rest), "iso time")

    -- Parse offset (if any)
    -- Rest is the TimeOffset:
    -- 'Z' means 0
    if (rest ~= nil) then
      if (string.match(rest, "Z$")) then
	ro = 0 -- Remember to distinguish between unset and set to 0...
	-- debugmessage("NDH", string.format("isostringoffset: %s (%s): Z -> %s", str, rest, ro), "iso offset")
      else
	local os, oh, om = string.match(rest, "([%+%-])([%d]+):?(%d*)")
	if (os and oh and om) then
	  ro = ((((os == '+') and 1) or ((os == '-') and -1)) * (oh * 3600 + ('0'..om) * 60))
	end
	-- debugmessage("NDH", string.format("isostringoffset: %s (%s): %s %s %s -> %s", str, rest, os, oh, om, ro), "iso offset")
      end
    end
    return rt, ro
  end

  -- "6/1/2023 5:30 PM"
  -- "6/1/2023"
  -- Parse timestamp (returns LOCALtime since epoch, but as long as execution doesn't span time change, won't matter)
  t['month'], t['day'], t['year'], rest = string.match(str, "(%d%d?)/(%d%d?)/(%d%d%d+)(.*)")
  if (t['year']~= nil) then
    t['hour'] = 0
    t['min'] = 0
    t['sec'] = 0
    if (rest == nil or rest == "") then
      rest = defaulttime
    end
    if (rest and rest ~= "") then
      local r
      t['hour'], r = string.match(rest, " *(%d%d?)(.*)") 
      -- debugmessage("NDH", string.format("isostring1: %s; %s-%s-%sT%s:%s:%s + %s %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r, rest), "time1")
      rest = r or rest
    end
    if (rest and rest ~= "") then
      local r
      t['min'], r = string.match(rest, ":(%d%d)(.*)")
      -- debugmessage("NDH", string.format("isostring2: %s; %s-%s-%sT%s:%s:%s + %s %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r, rest), "time2")
      rest = r or rest
    end
    if (rest and rest ~= "") then
      local r
      t['sec'], r = string.match(rest, ":([%d%.]+)(.*)")
      debugmessage("NDH", string.format("isostring3: %s (%s); %s-%s-%sT%s:%s:%s + %s %s", str, rest, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], r, rest), "time3")
      rest = r or rest
    end
    if (rest and rest ~= "") then
      local r
      local ampm
      ampm, r = string.match(rest, " ([AP]M)(.*)")
      if (ampm == "PM" and tonumber(t['hour']) ~= 12) then
        t['hour'] = t['hour'] + 12
      elseif (ampm == "AM" and t['hour'] == 12) then
        t['hour'] = t['hour'] - 12
      end
      debugmessage("NDH", string.format("h '%s' ampm '%s' r '%s' rest '%s'", t['hour'], ampm, r, rest), "offset")
      rest = r or rest
    end

    rt = (t['year'] and os.time(t)) or nil -- local time
    if (rt == nil) then
      debugmessage("NDHutils", string.format("Bad format time %s", str), "NDH debug time")
      rt = 0
    end
    -- debugmessage("NDH", string.format("timestring: %s; %s-%s-%sT%s:%s:%s %s -> %s", str, t['year'], t['month'], t['day'], t['hour'], t['min'], t['sec'], rest, rt), "offset")

    -- Parse offset (if any)
    -- Rest is the TimeOffset:
    -- 'Z' means 0
    if (rest ~= nil) then
      if (string.match(rest, "Z$")) then
	ro = 0 -- Remember to distinguish between unset and set to 0...
      else
	local os, oh, om = string.match(rest, "([%+%-])([%d]+):*(%d*)")
	if (os and oh and om) then
	  ro = ((((os == '+') and 1) or ((os == '-') and -1)) * (oh * 3600 + ('0'..om) * 60))
	end
	-- debugmessage("NDH", string.format("stringoffset: %s (%s): %s %s %s -> %s", str, rest, os, oh, om, ro), "offset")
      end
    end
    return rt, ro
  end

  debugmessage("NDHutils", string.format("Bad timestring \"%s\"", str), "timestring")
  return nil, nil
end

verbose_flags["NDH debug csvsplit"] = false

function csvsplit (inputstr, linecount)
  local t={}
  local i = 500;
  local field
  local rest
  local originput = inputstr
  debugmessage("NDHutils", string.format("CSVSplit(%s)", inputstr), "NDH debug csvsplit")
  while (inputstr and inputstr:len() > 0 and i > 0) do
    if (inputstr:sub(1, 1) == "\"") then			-- Opens with a quote
      field, rest = inputstr:match("\"([^\"]*)\"(.*)")	       	-- consume everything up to but not including the next quote.  Leave a comma
      inputstr = rest
      while (inputstr and inputstr:sub(1,1) == "\"") do	-- and glue on anything which starts with quotequote
        rest, inputstr = inputstr:match("\"([^\"]*)\"(.*)")
	field = field .. "\"" .. rest
      end
      field = string.gsub(field, '%s$', '')			-- chop off space characters at end
      table.insert(t, field)
    else
      field, rest = inputstr:match(" ?([^,]*)(.*)")		-- Hack to remove leading spaces - really that should be malformatted CSV.
      inputstr = rest
      table.insert(t, field)
    end
    if (inputstr == nil) then
      debugmessage("NDHutils", string.format("CSVSplit(%s) --> %s", originput, format_table(t)), "NDH debug csvsplit abort")
      return t
    end
    inputstr = inputstr:match(", *(.*)")			-- Swallow comma to move to next field.
    i = i - 1
  end
  return t
end

-- Only called for strings wrapped in quotes.
function csvprotect(str)
  if (str == nil) then
    return nil
  else
    return string.gsub(string.gsub(str, '[\r\n]+', ' '), '\"', '\"\"')
  end
end

function countset(set)
  local count = 0
  local i, j
  for i, j in pairs(set) do
    count = count + 1
  end
  return count
end


-- From: http://lua-users.org/wiki/StringRecipes
local function tchelper(first, rest)
   return first:upper()..rest:lower()
end
-- Add extra characters to the pattern if you need to. _ and ' are
--  found in the middle of identifiers and English words.
-- We must also put %w_' into [%w_'] to make it handle normal stuff
-- and extra stuff the same.
-- This also turns hex numbers into, eg. 0Xa7d4

function titlecaps(str)
  return str:gsub("(%a)([%w_'-]*)", tchelper) .. "" -- "Hyphen_joined Plural's Dash-joined"
end
