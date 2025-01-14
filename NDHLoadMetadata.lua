--[[-------------------------------------------------------------------------
NDHLoadMetadata.lua

Exploring LRSDK

---------------------------------------------------------------------------]]

-- local datafile = "/Users/neilhunt/DriveNeil/0 Personal Folders/Lightroom/2010 PhotosWithDatesAndCaptions - Export.csv"
-- local gpsfile = "/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/GPX main/Strava/2023 Test.gpx"

local overwrite = true
local dryrun = false

-- Set the names of root keyword and root collection set - can be edited to taste
local LrApplication = import 'LrApplication'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'
local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'
local LrFileUtils = import "LrFileUtils"
local LrXml = import "LrXml"

local catalog
local photos

require 'NDHutils'
require 'NDHgps'

local prefs = LrPrefs.prefsForPlugin(nil)
if (prefs.dryrun == nil) then
  prefs.dryrun = true
end

local import = false
local progress

verbose = true
verbose_flags["Debug CSV Format"] = true
verbose_flags["willchange"] = true

-- Set up the logger
local logger = LrLogger('NDH')
logger:enable("print") -- set to "logfile" to write to ~/Documents/lrClassicLogs/NDH.log
local log = logger:quickf('info')

local catalog = nil
local photos = nil

local function getkwhierarchy(key)
  local keyname
  -- Iterate up the parent chain
  while (key) do
    if (keyname == nil) then
      keyname = key:getName()
    else
      keyname = key:getName() .. " > " .. keyname
    end
    key = key:getParent()
  end
  return keyname
end

--
-- Load Metadata File into a table
--

local metadatatable = { }
local fieldnames;
local metadataloaded = false
local metadatastart
local metadataend

local function loadcsvfile(filename)

  -- LrFunctionContext.postAsyncTaskWithContext("ProgressContextId", function(context)

  --   LrDialogs.attachErrorDialogToFunctionContext(context)

    -- Load Metadata File
    local line
    local countlines = 0
    local timelocalindex
    local timeutcindex
    -- LrDialogs.message("NDHLoadMetadata", string.format("Loading %s", filename))
    for line in io.lines(filename) do
      countlines = countlines + 1
      line = line:gsub("%c$", "") -- chomp
      if (fieldnames == nil) then
	fieldnames = csvsplit(line)
	if (fieldnames[1] ~= "Pathname") then
	  LrDialogs.message("NDHLoadMetadata", string.format("%s: File does not appear to have the CSV labels beginning with Pathname (%s)", filename, line))
	  return
	end
	for i, f in pairs(fieldnames) do
	  if (f == "TimeLocal") then
	    timelocalindex = i
	  elseif (f == "TimeUTC") then
	    timeutcindex = i
	  end
	end
      else
	local t = csvsplit(line)
	local pathname = t[1]
	metadatatable[pathname] = t
	if (timelocalindex) then
	  local timelocal = t[timelocalindex]
	  if (metadatastart == nil or timelocal < metadatastart) then
	    metadatastart = timelocal
	  end
	  if (metadataend == nil or metadataend < timelocal) then
	    metadataend = timelocal
	  end
	end	  
      end
    end
    -- debugmessage("NDHLoadMetadata", string.format("Loaded %s %d lines from %s to %s", filename, countlines, metadatastart, metadataend), "Debug loaded")
    prefs.csvstatus = string.format("Loaded %d lines from %s to %s", countlines, metadatastart, metadataend)

    metadataloaded = true

--  end)

end

verbose_flags['key parse'] = false
verbose_flags['keyword'] = false
verbose_flags['key0'] = false
verbose_flags['key1'] = false
verbose_flags['key2'] = false
verbose_flags['key3'] = false
verbose_flags['key4'] = false
verbose_flags['PhotoMetadata'] = false
verbose_flags['CSV Format'] = false
verbose_flags['Caption'] = false
verbose_flags['LatLon'] = false
verbose_flags['get or create keyword'] = false
verbose_flags['get or create 2'] = false
verbose_flags['DebugKeywords'] = false
verbose_flags['add keep'] = false
verbose_flags['logging'] = false
verbose_flags['write caption'] = false

local function printKeyword(key)
  local ret = "NIL"
  if (key ~= nil) then
    if (key == false) then
      ret = "FALSE"
    elseif (type(key) ~= "table") then
      ret = "Not an object"
    elseif (key:type() ~= "LrKeyword") then
      ret = "Object not Keyword: " .. key:type() -- Error: Can't get keyword information after creating inside same DoWithWrite etc.
    else
      ret = key.localIdentifier
    end
  end
  return ret
end


-- Work around a bug where attempting to Get the same keyword multiple times within a single context repeatably fails on the second try.
-- eg. Attempting to add _Photography > INat > quality=research; _Photography > INat > INatID=1234 always fails on the second attempt to get "INat"
-- Build a cache of keyword handles against parent and name.
-- Todo: add synonym later.

local keywords = { } -- indexed by "parentname>keywordname"

local function getOrCreateKeyword(kwname, synname, public, parent, parentname, create)
  local handle = parentname .. ">" .. kwname
  local keyword = keywords[handle]
  local synonyms = { }
  if (synname and synname ~= "") then
    synonyms = { synname }
  end
  if (keyword ~= nil) then
    debugmessage("NDHLoadMetadata", string.format("getOrCreateKeyword(%s %s %s %s %s) handle %s returns cached %s", kwname, synonyms, public, parentname, create, handle, keyword), "get or create keyword")
  else
    keyword =  catalog:createKeyword(kwname, synonyms, public, parent, create)
    debugmessage("NDHLoadMetadata", string.format("getOrCreateKeyword(%s %s %s %s %s) handle %s returns create %s", kwname, synonyms, public, parentname, create, handle, keyword), "get or create keyword")
    keywords[handle] = keyword
  end

  -- This fails with keyword:getSynonyms() tripping '?: attempt to index nil' - same problem as elsewhere - seems can't do anything with a keyword once "created" in the same context.
  -- -- See if the synonym is present
  -- if (keyword ~= nil and keyword ~= false and synname ~= nil and synname ~= "") then
  --   debugmessage("NDHLoadMetadata", string.format("Keyword %s: about to get synonyms", kwname), "synonyms0")
  --   synonyms = keyword:getSynonyms()
  --   if (synonyms) then
  --     for _,name in ipairs(synonyms) do
  --       if (name == synname) then
  -- 	  -- Found synname, nothing more to do
  -- 	  debugmessage("NDHLoadMetadata", string.format("Keyword %s: synonym %s already present", keyname, synname), "synonyms1")
  -- 	  return keyword
  -- 	end
  --     end
  --     -- Some synonyms, none match, add it.
  --     debugmessage("NDHLoadMetadata", string.format("Keyword %s: synonym %s to add", keyname, synname), "synonyms2")
  --     table.add(synonyms, synname)
  --   else
  --     -- No synonyms; add one.
  --     debugmessage("NDHLoadMetadata", string.format("Keyword %s: synonym %s to create", keyname, synname), "synonyms3")
  --     synonyms = { synname }
  --   end
  --   keyword:setAttributes({ nil, synonyms, nil})
  -- end

  return keyword
end

local function importmetadata()

  LrFunctionContext.postAsyncTaskWithContext("ProgressContextId", function(context)

    LrDialogs.attachErrorDialogToFunctionContext(context)
    
    progress = LrDialogs.showModalProgressDialog(
      {
        title = "Loading Metadata",
	caption = "",
        cannotCancel = false,
        functionContext = context
      }
    )
    LrTasks.sleep(0)
    
    progress:setIndeterminate()

    if (metadataloaded == false) then
      loadcsvfile(prefs.csvfile)
    end
    
    --
    -- Iterate over all selected photos...
    -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
    local countphotos = 0
    local countmatchedphotos = 0
    local countskipped = 0
    local countunchanged = 0
    local countmodified = 0

    --
    if (#photos == 1) then
      verbose = true
    end
    local finish = 3 -- 0 = show no photos; 1 = show only changed; 2 = show only unchanged; 3 = show all

    local logging = true
    local logfile
    if (logging) then
      local logfilename = prefs.csvfile .. ".log"
      logfile = io.open(logfilename, "w")
      debugmessage("NDHLoadMetadata", string.format("Opened logfile %s %s", logfilename, logfile), "open logfile")
    end

    --
    -- Iterate over selected photos
    -- metadata[k] are the field value strings for e.g.: k=6 for Keywords
    -- values[k] 
    --
    for j, p in ipairs(photos) do
      countphotos = countphotos + 1
      local filename = p:getFormattedMetadata('fileName')
      local path = p:getRawMetadata('path')
      local copyname = p:getFormattedMetadata('copyName')
      if (copyname ~= nil and copyname ~= "") then
	path = path .. "[" .. copyname .. "]"
      end
      local metadata = metadatatable[path]
      debugmessage("NDHLoadMetadata", string.format("Photo %s, %d metadata fields", path, metadata and #metadata or 0), "PhotoMetadata")
      
      if (metadata ~= nil) then

        progress:setCaption(string.format("Processing %d (%s)", countphotos, filename))

	countmatchedphotos = countmatchedphotos + 1

	--
	-- Count changes (if any)
	--

	local debug = filename .. ": "
	local newcaption
	local newtitle
	local newlat, newlong, newgps
	local addkeywords = { } -- hash of keyword > keyword > keyword to add
	local keepkeywords = { } -- hash of keywords that exist and we want to keep
	local delkeywords = { } -- hash of keywords that should be removed (only added if not in add or keep)
	local retainkeywords = { } -- has of keywords matching !keyword but also matching add keyword
	local willchange = false

	-- Iterate over metadata fields
	for k, fieldname in ipairs(fieldnames) do
	  debugmessage("NDHLoadMetadata", string.format("%s: Field %s --> %s", path, fieldname, metadata[k]), "CSV Format")
	  if (fieldname == "Pathname") then
	    -- Matched the correct file
	  elseif (fieldname == "Caption") then
	    local oldcaption = p:getFormattedMetadata("caption")
	    newcaption = metadata[k]
	    debugmessage("NDHLoadMetadata", string.format("%s: Caption %s --> %s", path, newcaption, oldcaption), "Caption")
	    if (newcaption and newcaption ~= "" and newcaption ~= "!") then
	      -- Add newcaption
	      if ((oldcaption == nil) or (oldcaption == "")) then
		-- No current caption - add newcaption
		debug = debug .. string.format("\n%s: LOAD NEW %s", fieldname, newcaption)
		willchange = true
	      elseif (oldcaption == newcaption) then
		-- Caption is same
		debug = debug .. string.format("\n%s: UNCHANGED %s", fieldname, oldcaption)
		newcaption = nil -- don't bother to change it if already set.
	      elseif (overwrite) then
		-- Change current caption
		debug = debug .. string.format("\n%s: OVERWRITE %s<-%s", fieldname, oldcaption, newcaption)
		willchange = true
	      end
	    elseif (newcaption and newcaption == "!") then
	      -- Erase oldcaption if any
	      -- newcaption = "" -- retain this for the second actual write phase
	      if (oldcaption and oldcaption ~= "") then
	        debug = debug .. string.format("\n%s: ERASE %s", fieldname, oldcaption)
	        willchange = true
	      else
	        debug = debug .. string.format("\n%s: ALREADY ERASED", fieldname)
	      end
	    elseif (oldcaption) then
	      -- No new caption
	      debug = debug .. string.format("\n%s: KEEP OLD %s", fieldname, oldcaption)
	    else
	      debug = debug .. "\nNo Caption"
	    end
	  elseif (fieldname == "Title") then
	    newtitle = metadata[k]
	    if (newtitle and newtitle ~= "" and newtitle ~= "!") then
	      local oldtitle = p:getFormattedMetadata("title")
	      if (((oldtitle == nil) or (oldtitle == "")) and (oldtitle ~= newtitle)) then
		debug = debug .. string.format("\n%s: LOAD NEW %s", fieldname, newtitle)
		willchange = true
	      elseif (oldtitle == newtitle) then
		debug = debug .. string.format("\n%s: UNCHANGED %s", fieldname, oldtitle)
		newtitle = nil -- don't bother to change it if already set.
	      elseif (overwrite) then
		debug = debug .. string.format("\n%s: OVERWRITE %s<-%s", fieldname, oldtitle, newtitle)
		willchange = true
	      end
	    elseif (newtitle and newtitle == "!") then
	      -- Erase oldtitle it any
	      -- newtitle = "" -- retain this for the second actual write phase
	      if (oldtitle and oldtitle ~= "") then
	        debug = debug .. string.format("\n%s: ERASE %s<-%s", fieldname, oldtitle, newtitle)
	        willchange = true
	      else
	        debug = debug .. string.format("\n%s: ALREADY ERASED", fieldname)
	      end
	    elseif (oldtitle) then
	      -- No new title
	      debug = debug .. string.format("\n%s: KEEP OLD %s", fieldname, oldtitle)
	    else
	      debug = debug .. "\nNo Title"
	    end
	  elseif (fieldname == "Lat") then
	    if (metadata[k] and metadata[k] ~= "") then
	      newlat = metadata[k]
	    end
	    -- do the work on next pass - "Long"
	  elseif (fieldname == "Long") then
	    newlong = metadata[k]
	    if (newlong and newlong ~= "") then
	      debugmessage("NDHLoadMetadata", string.format("%s (%d): GPS=(%s, %s)", path, countphotos, newlat, newlong), "LatLon")
	      local oldgps = p:getRawMetadata("gps")
	      newgps = { latitude = tonumber(newlat), longitude = tonumber(newlong) }
	      if (newlat ~= nil and newlong ~= nil and newlat ~= "!" and newlon ~= "!") then
		-- Add newlat, newlong
		if (oldgps == nil) then
		  -- No current GPS, load new
		  debug = debug .. string.format("\n%s: LOAD NEW %s %s", fieldname, newlat, newlong)
		  willchange = true
		elseif (NDHgps.gpsdiff(oldgps['latitude'], oldgps['longitude'], newlat, newlong) < 1) then -- 1m diff is store format rounding
		  -- Not materially different
		  debug = debug .. string.format("\ngps: UNCHANGED (%f,%f) (%f,%f)", oldgps['latitude'], oldgps['longitude'], newlat, newlong)
		  newgps = nil -- don't bother to set it if already there
		elseif (overwrite) then
		  debug = debug .. string.format("\ngps: OVERWRITE (%f,%f) (%f,%f) (dist=%f)", oldgps['latitude'], oldgps['longitude'], newlat, newlong, NDHgps.gpsdiff(oldgps['latitude'], oldgps['longitude'], newlat, newlong))
		  willchange = true
		end
	      elseif (newlat ~= nil and newlong ~= nil and newlat == "!" and newlon == "!") then
		-- Have newlat, newlong to write or erase old
		newgps = { } -- For the actual write phase
		if (oldgps ~= nil) then
		  -- Erase old
		  debug = debug .. string.format("\ngps: ERASE (%f,%f)", oldgps['latitude'], oldgps['longitude'])
		  willchange = true
		else
		  -- oldgps is nil
		  debug = debug .. string.format("\ngps: ALREADY ERASED")
		end
	      else
		debug = debug .. string.format("\ngps: KEEP OLD (%f,%f)", oldgps['latitude'], oldgps['longitude'])
	      end
	    else
	      -- empty lat long fields
	      debug = debug .. "\nGPS unchanged"
	    end
	  elseif (fieldname == "Keywords") then -- Counting
	    local keywords = metadata[k]
	    if (keywords ~= nil) then
	      local foundall = true
	      local oldkeywords = p:getRawMetadata('keywords')
	      for kwhierarchy in string.gmatch(keywords, " *([^;]+);? *") do
		local canonicalkwstring
		local erase, kwhstring = string.match(kwhierarchy, "^(!?) *(.*)$")
		-- Processing Add/Remove for kwhstring
		-- LrDialogs.message("NDHLoadMetadata Debug", string.format("Keywords: %s --> %s, %s", kwhierarchy, erase, kwhstring))
		-- KEEP/ADD keyword match
		local foundkeyword = false
		-- Run down the keyword > keyword string removing the synonym specs to build a canonical form
		for kwcomponent in string.gmatch(kwhstring, " *([^>]+)>? *") do
		  local kwname, synname
		  kwname, synname = string.match(kwcomponent, "([^|]+) *|? *(.*)")
		  kwname = string.gsub(kwname, " *$", "")
		  synname = string.gsub(synname, " *$", "")
		  if (synname and synname ~= "") then
		    debugmessage("NDHLoadMetadata", string.format("KeywordHierarchy: '%s' : '%s' from %s", kwname, synname, kwcomponent), "syn pre")
		  end
		  if (canonicalkwstring == nil) then
		    canonicalkwstring = kwname
		  else
		    canonicalkwstring = canonicalkwstring .. " > " .. kwname
		  end
		end
		if (canonicalkwstring ~= nil) then
		  local canonicalkwstringlower = string.lower(canonicalkwstring)
		  -- See if it already exists in the photo
		  debugmessage("NDHLoadMetadata", string.format("Keyword canonical %s %s (%s)", erase, canonicalkwstring, kwhstring), "DebugKeywords")
		  if (erase == "") then -- ADD or KEEP
		    local foundkeyword = false
		    for x, oldkey in ipairs(oldkeywords) do
		      local oldkeyname = getkwhierarchy(oldkey)
		      -- Keyword add/keep? '_Nature > _Common > Bird > Black-crowned Night Heron' <=>
		      --                   '_Nature > _Common > Bird > Black-Crowned Night Heron'
		      debugmessage("NDHLoadMetadata", string.format("Keyword add/keep? '%s' <=> '%s'", canonicalkwstring, oldkeyname), "add keep")
		      if (canonicalkwstringlower == string.lower(oldkeyname)) then
			debugmessage("NDHLoadMetadata Debug", string.format("Keyword FOUND keep '%s' <=> '%s' (%s)", canonicalkwstring, oldkeyname, kwhstring), "DebugKeywords")
			keepkeywords[canonicalkwstring] = kwhstring -- Remember the definition include the synonyms
			if (delkeywords[canonicalkwstringlower]) then
			  retainkeywords[canonicalkwstringlower] = kwhstring
			end
			delkeywords[canonicalkwstringlower] = nil; -- Remove it from the delete list
			foundkeyword = true
		      else
		        -- Keyword NOTYET '_Nature > _Common > Bird > Black-crowned Night Heron' <=>
		        --                '_Nature > _Common > Bird > Black-Crowned Night Heron' (_Nature > _Common > Bird > Black-crowned Night Heron)
		        -- debugmessage("NDHLoadMetadata Debug", string.format("Keyword NOTYET '%s' <=> '%s' (%s)", canonicalkwstring, oldkeyname, kwhstring), "DebugKeywords")
		      end
		    end
		    if (foundkeyword == false) then -- Didn't find it to KEEP, so ADD
		      debugmessage("NDHLoadMetadata Debug", string.format("Keyword ADD %s (%s)", canonicalkwstring, kwhstring), "DebugKeywords")
		      addkeywords[canonicalkwstringlower] = kwhstring -- Remember the definition including the synonyms
		      delkeywords[canonicalkwstringlower] = nil; -- Should be superfluous
		    end
		  else -- REMOVE
		    local foundkeyword = false
		    for x, oldkey in ipairs(oldkeywords) do
		      local oldkeyname = getkwhierarchy(oldkey)
		      local oldkeynamelower = string.lower(oldkeyname)
		      -- LrDialogs.message("NDHLoadMetadata Debug", string.format("Keyword remove? %s <=> %s (%s)", canonicalkwstring, oldkeyname, kwhstring))
		      if (string.find(oldkeynamelower, canonicalkwstringlower, 1, true)) then -- Plaintext match on canonicalkwstring
			-- if strictly chronological:
			  -- addkeywords[oldkeynamelower] = nil -- Remove it from the add list
			  -- keepkeywords[oldkeynamelower] = nil -- Remove it from the keep list
			-- end
			if (addkeywords[oldkeynamelower] or keepkeywords[oldkeynamelower]) then
			  -- Explicitly added - retain, don't remove.
			  retainkeywords[oldkeynamelower] = kwhstring
			  debugmessage("NDHLoadMetadata Debug", string.format("Keyword RETAIN %s <=> %s (%s)", canonicalkwstring, oldkeyname, kwhstring), "DebugKeywords")
			else
			  delkeywords[oldkeynamelower] = oldkey -- Remember the key to delete
			  foundkeyword = true
			  debugmessage("NDHLoadMetadata Debug", string.format("Keyword REMOVE %s <=> %s (%s)", canonicalkwstring, oldkeyname, kwhstring), "DebugKeywords")
			end
		      end
		    end
		    if (not foundkeyword) then
		      debugmessage("NDHLoadMetadata Debug", string.format("Keyword NOT Found to remove %s (%s)", canonicalkwstring, kwhstring), "DebugKeywords")
		    end
		  end
		end
	      end
	      if (countset(addkeywords) > 0 or countset(delkeywords) > 0) then
		willchange = true
	      end
	    else
	      debug = debug .. "\nNo Keywords"
	    end
	  else
	    -- LrDialogs.message("NDHLoadMetadata", string.format("%s: Bad Fieldname %s", path, fieldname))
	  end
	  if (fieldname ~= "Lat") then
	    newlat = nil
	  end
	  debugmessage("NDHLoadMetadata", string.format("%s: fieldname=%s willchange=%s (%d %d)", filename, fieldname, willchange, countset(addkeywords), countset(delkeywords)), "willchange")
	end -- iterate over fieldnames

	local keyname, key
	for keyname, key in pairs (delkeywords) do
	  debug = debug .. string.format("\nKeywords Remove %s", keyname)
	  willchange = true
	end
	for keyname, key in pairs (keepkeywords) do
	  debug = debug .. string.format("\nKeywords Keep %s", keyname)
	end
	for keyname, key in pairs (retainkeywords) do
	  debug = debug .. string.format("\nKeywords Retain %s", keyname)
	end
	for keyname, key in pairs (addkeywords) do
	  local kwhstring = key
	  debug = debug .. string.format("\nKeywords Add %s", keyname, kwhstring)
	  willchange = true
	end

	-- finish: 0 = show no photos; 1 = show only changed; 2 = show only unchanged; 3 = show all
	if (finish ~= 0) then
	  local proceed
	  if (willchange and (finish == 1 or finish == 3)) then
	    -- show changed photos
	    proceed = LrDialogs.confirm("NDHLoadMetadata", debug, "Load", "Cancel", "Finish")
	    if (proceed == "other") then
	      finish = 0
	    end
	  elseif (willchange == false and (finish == 2 or finish == 3)) then
	    proceed = LrDialogs.confirm("NDHLoadMetadata", debug, "Next", "Cancel", "Continue without showing unchanged")
	    if (proceed == "other") then
	      finish = 1
	    end
	  end
	  if (proceed == "cancel") then
	    return
	  end
	end

	--
	-- Now UPDATE the actual metadata
	--
	local logdbg = path
	if (dryrun) then -- "Skip file"
	  countskipped = countskipped + 1
	  -- continue
	elseif (not willchange) then
	  countunchanged = countunchanged + 1
	  logdbg = stringbuild(logdbg, ", unchanged")
	else
	  countmodified = countmodified + 1
	  local haschanged = false
	  for k, fieldname in ipairs(fieldnames) do -- iterate over fielnames
	    -- debugmessage("NDHLoadMetadata", string.format("%s: write field %s", filename, fieldname), "NDH write fieldname")
	    if (fieldname == "Pathname") then
	      -- Matched the correct file
	    elseif (fieldname == "Caption") then
	      if (newcaption ~= nil and newcaption ~= "") then
	        if (newcaption == "!") then
		  newcaption = ""
		end
		local write = catalog:withWriteAccessDo("setRawMetadata1", function()
		  debugmessage("NDHLoadMetadata", string.format("%s: caption='%s'", filename, newcaption), "NDH debug write caption")
		  p:setRawMetadata("caption", newcaption)
		  logdbg = stringbuild(logdbg, string.format("caption=%s", newcaption), ", ")
		end)
		if (write ~= "executed") then
		  debugmessage("NDHLoadMetadata", string.format("Write failed: %s (setRawMetadata1)", write), "writeaccess")
		  logdbg = logdbg .. "write failed"
		else
		  logdbg = logdbg .. "success"
		end
		haschanged = true
	      end
	    elseif (fieldname == "Title") then
	      if (newtitle ~= nil and newtitle ~= "") then
	        if (newtitle == "!") then
		  newtitle = ""
		end
		local write = catalog:withWriteAccessDo("setRawMetadata2", function()
		  -- LrDialogs.message("NDHLoadMetadata", string.format("%s: title=%s", filename, newtitle))
		  p:setRawMetadata("title", newtitle)
		  logdbg = stringbuild(logdbg, string.format("title='%s'", newtitle), ", ")
		end)
		if (write ~= "executed") then
		  debugmessage("NDHLoadMetadata", string.format("Write failed: %s (setRawMetadata2)", write), "writeaccess")
		  logdbg = logdbg .. "write failed"
		else
		  logdbg = logdbg .. "success"
		end
		haschanged = true
	      end
	    elseif (fieldname == "Lat") then
	      -- do the work on next pass - "Long"
	    elseif (fieldname == "Long") then
	      if (newgps ~= nil) then
		local write = catalog:withWriteAccessDo("setRawMetadata3", function()
		  -- debugmessage("NDHLoadMetadata", string.format("%s: write gps=(%f,%f)", filename, newgps['latitude'], newgps['longitude']), "Debug write gps")
		  p:setRawMetadata("gps", newgps)
		  -- debugmessage("NDHLoadMetadata", string.format("%s: wrote gps=(%f,%f)", filename, newgps['latitude'], newgps['longitude']), "Debug write gps")
		  logdbg = stringbuild(logdbg, string.format("gps={%s,%s}", newgps['latitude'], newgps['longitude']), ", ")
		end)
		if (write ~= "executed") then
		  debugmessage("NDHLoadMetadata", string.format("Write failed: %s (setRawMetadata3)", write), "writeaccess")
		  logdbg = logdbg .. "write failed"
		else
		  logdbg = logdbg .. "success"
		end
		-- debugmessage("NDHLoadMetadata", string.format("%s: committed gps=(%f,%f)", filename, newgps['latitude'], newgps['longitude']), "Debug write gps")
		haschanged = true
	      end
	    elseif (fieldname == "Keywords") then  -- APPLY phase
	      -- addkeywords is a set of keywords to add.
	      if (verbose) then
		-- LrDialogs.message("NDHLoadMetadata", string.format("AddKeywordHierarchy APPLY phase"))
	      end
	      local addkey, fullkey
	      if ((countset(addkeywords) > 0) or (countset(delkeywords) > 0)) then
		local write = catalog:withWriteAccessDo("Set keywords", function()
		  -- delkeywords is a set of keywords to delete - the value is the keyword itself
		  local delkey, key
		  for delkey, key in pairs(delkeywords) do
		    logdbg = stringbuild(logdbg, string.format("remove=%s", key), ", ")
		    p:removeKeyword(key)
		    if (verbose) then
		      -- LrDialogs.message("NDHLoadMetadata Debug", string.format("Removed key %s", delkey))
		    end
		  end
		  -- keepkeywords is a set of keywords that should already be there - nothing to do
		  -- addkeywords is a set of keywords to add.
		  --   If we removed "Black-Crowned" above, we'll might add back "Black-crowned" (lowercase "C") here
		  for addkey, fullkey in pairs (addkeywords) do
		    -- addkey is the canonical lower-case only version
		    -- fullkey is the definition with case and synonyms
		    local kwhstring = addkey
		    local lastkey = nil
		    local lastkeyname = "TOP"
		    debugmessage("NDHLoadMetadata", string.format("Adding Keyword %s (%s)", kwhstring, fullkey), "keyword")
		    -- Create keyword tree to attach to changed pics
		    for kwcomponent in string.gmatch(fullkey, " *([^>]+)>? *") do
		      local kwname, synname
		      kwname, synname = string.match(kwcomponent, "([^|]+) *|? *(.*)")
		      debugmessage("NDHLoadMetadata", string.format("Keywords %s: %s -> %s, %s", fullkey, kwcomponent, kwname, synname), "key parse")
		      kwname = string.gsub(kwname, " *$", "")
		      synname = string.gsub(synname, " *$", "")
		      -- local synonyms = { }
		      -- if (synname and synname ~= "") then
			-- synonyms = { synname }
		      -- end
		      assert(lastkey ~= false)
		      debugmessage("NDHLoadMetadata", string.format("Create or get keyword %s syn (%s) sub of %s (%s) for %s",
								     kwname, synname,
								     lastkey, lastkeyname,
								     fullkey
								     ), "key0")
		      -- local thiskey = catalog:createKeyword(kwname, synonyms, true, lastkey, true) -- Create or get existing keyword
		      local thiskey = getOrCreateKeyword(kwname, synname, true, lastkey, lastkeyname, true) -- Create or get existing keyword
		      logdbg = logdbg .. string.format(" createkey %s=%s", kwname, thiskey)
		      if (thiskey == false) then
			debugmessage("NDHLoadMetadata", string.format("Created or got keyword %s syn (%s) sub of %s (%s) --> %s",
								       kwname, synname, lastkey, lastkeyname, "FALSE"
								     ), "key1 fail")
	   		return -- exit the withwriteaccess function
		      else
			debugmessage("NDHLoadMetadata", string.format("Created or got keyword %s syn (%s) sub of %s (%s) --> %s",
								       kwname, synname, lastkey, lastkeyname, thiskey
								     ), "key1")
		      end
		      lastkey = thiskey
		      lastkeyname = kwname
		      if (lastkey == nil or lastkey == false) then
			debugmessage("NDHLoadMetadata", string.format("Failed to create keyword %s of %s", kwname, fullkey), "keyerror")
			return
		      end
		      debugmessage("NDHLoadMetadata", string.format("Created part key = %s", lastkeyname), "key2")
		    end
		    if (lastkey == nil or lastkey == false) then
		      debugmessage("NDHLoadMetadata", string.format("Failed to create keywords %s (%s)", fullkey, lastkeyname), "key3")
		      return
		    else
		      debugmessage("NDHLoadMetadata", string.format("Apply keywords %s (%s)", fullkey, lastkeyname), "key3")
		    end
		    debugmessage("NDHLoadMetadata", string.format("About to apply keyword %s %s to photo %s", lastkey, lastkeyname, p), "get or create 2")
		    p:addKeyword(lastkey)
		    logdbg = stringbuild(logdbg, string.format("addkey=%s,%s", addkey, lastkey), ", ")
		    debugmessage("NDHLoadMetadata", string.format("Added Keyword: %s\n", fullkey), "key4")
		    haschanged = true
		  end
		end)
		if (write ~= "executed") then
		  debugmessage("NDHLoadMetadata", string.format("Write failed: %s (Set keywords)", write), "writeaccess")
		  logdbg = logdbg .. "write failed"
		else
		  logdbg = logdbg .. "success"
		end
	      end
	    else
	      -- debugmessage("NDHLoadMetadata", string.format("%s: Bad Fieldname %s", path, fieldname), "fieldnames")
	      -- There are lots of other fields not handled at present
	    end
	  end
	end
	debugmessage("NDHLoadMetadata", string.format("Logging %s", logdbg), "logging")
	logdbg = logdbg .. "\n"
	logfile:write(logdbg)
      end
      if (progress:isCanceled()) then
	return
      end

    end

    logfile:close()

    LrDialogs.message(string.format("Processed %d photos\n%d matched as\n%d skipped +\n %d modified +\n %d unchanged",
					       countphotos,
							  countmatchedphotos,
								       countskipped,
										    countmodified,
												  countunchanged))
  end)
  
end

local function main ()

  log(" Starting")
  -- LrDialogs.message("NDH", "Starting LoadMetadata")

  if (photos == nil) then
    log("No selected photos")
    LrDialogs.message("NDH", "Usage: Select one or more photos to adjust")
    return
  else
    LrDialogs.message("NDH", "Loading ")
  end

  loadcsvfile(filename)

  local proceed = LrDialogs.confirm("NDHLoadMetadata", string.format("%s: Read %d lines", filename, countlines))
  if (proceed == "cancel") then return end

  readmetadata()

end

--
-- Set up parameters in setupdialog
--
local function setupdialog()

  prefs.csvstatus = 'Not Loaded'

  -- Check that photos are selected.
  catalog = LrApplication.activeCatalog()
  photos = catalog:getTargetPhotos()
  if (photos == nil) then
    log("No selected photos")
    LrDialogs.message("NDH", "Usage: Select one or more photos to export metadata.  Chronological descending order works best.")
    return
  end
  
  verbose = verbose or (#photos < 2) -- 0 or 1 photos selected

  local f = LrView.osFactory()

  LrFunctionContext.callWithContext( "showCustomDialog", function( context )

    -- Create the contents for the dialog.
    local loaded = f:static_text {
      width = 600,
      title = "Not Loaded",
    }


    local c = f:column {

      spacing = f:control_spacing(),

      -- Bind the table to the view.  This enables controls to be bound to the named field of the 'props' table.
      bind_to_object = prefs,

      f:static_text {
        title = 'Load CSV file:',
	alignment = 'left',
      },

      f:row {

	f:edit_field {
	  width = 600,
	  value = LrView.bind("csvfile"),
	},

	f:push_button {
	  title = "Browse",
	  action = function()
	    local files = LrDialogs.runOpenPanel{title = 'CSV File location',
						   allowsMultipleSelection = false,
						   canChooseDirectories = false,
						   initialDirectory = '/Users/neilhunt/DriveNeil/0 Personal Folders/Lightroom/2024PhotosWithCaptions.csv'
						  }
	    if (files) then
	      prefs.csvfile = files[1]
	    else
	      prefs.csvfile = nil
	    end
	  end
	},

      },

      f:static_text {
        width = 600,
        title = LrView.bind("csvstatus"),
      },

      f:row {

        -- fill_horizontal = 800,

	f:push_button {
	  title = "Import CSV Data",
	  place_horizontal = 100,
	  action = function()
	    loadcsvfile(prefs.csvfile)
	  end
	},
      },

      f:separator { 
        width = 600,
	-- place_horizontal = 50,
      },

    }
  
    import = LrDialogs.presentModalDialog {
      title = "Import Metadata",
      contents = c
    }

  end)

  if (import == "ok") then
    importmetadata()
  end

end

-- Run main()
LrTasks.startAsyncTask(setupdialog)
