--[[-------------------------------------------------------------------------
NDHLoadKeywords.lua

Exploring LRSDK

---------------------------------------------------------------------------]]

-- Set the names of root keyword and root collection set - can be edited to taste
local LrApplication = import 'LrApplication'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'
 
-- Set up the logger
local logger = LrLogger('NDH')
logger:enable("print") -- set to "logfile" to write to ~/Documents/lrClassicLogs/NDH.log
local log = logger:quickf('info')



--[[
This is the entry point function that's called when the Lightroom menu item is selected
]]

local function main ()
  log(" Starting")
  -- LrDialogs.message("NDH", "Starting LoadKeywords")
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  if (photos == nil) then
    log("No selected photos")
    LrDialogs.message("NDH", "Usage: Select one or more photos to adjust")
    return
  end

  -- Test popen
  -- local pipe = io.popen("date")
  -- local datestring = pipe:read()
  -- LrDialogs.message(datestring)
  -- pipe:close()
  
  -- Load Keywords File
  local keywordstable = { }
  local line
  local first = true
  local countkeywords = 0
  for line in io.lines("/Users/neilhunt/DriveNeil/0 Personal Folders/Lightroom/2018 Keywords.csv") do
    if (first) then
      -- Skip definition line of CSV
      -- TODO - verify that it is "Path,Keywords"
      first = false
    else
      local imagefile = line:match("([^,]+),") -- Match through first comma
      -- line = string.gsub(line, imagefile .. ",", "")   -- Strip leading filename and comma
      local keywords = line:match("[^,]+, *\"?([^\"%c]*)\"?")
      keywordstable[imagefile] = keywords
      countkeywords = countkeywords+1
    end
  end

  LrDialogs.message(string.format("Read %d keyword entries", countkeywords))
  
  -- Create TimeZ keyword to attach to changed pics
  local rootkey, keyTimeZ
  catalog:withWriteAccessDo("Create keyword", function()
    rootkey = catalog:createKeyword('_Photography', {}, true, nil, true) -- Create or get existing keyword
    keyTimeZ = catalog:createKeyword('TimeZ', {}, true, rootkey, true) -- Create or get existing keyword
  end)
  
  -- Iterate over all selected photos...
  -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.

  --  LrDialogs.resetDoNotShowFlag()

  local countfiles = 0
  local countmodified = 0
  local countunchanged = 0

  --
  DONTUSE
  Check for keyword formatting
  Todo:
    Non-hierarchical keywords
    Keywords with spaces
    Loading the file from a different place
  
    for j, p in ipairs(photos) do
      countfiles = countfiles + 1
      local filename = p:getFormattedMetadata('fileName')
      local path = p:getRawMetadata('path')

      -- local pipecommand = string.format('/usr/local/bin/exiftool -f -p \'$FileName: $GPSDateTime\' %s', path)
      -- LrDialogs.message(pipecommand)
      -- local pipe = io.popen(pipecommand)
      -- local datestring = pipe:read()
      -- LrDialogs.message(datestring)
      -- pipe:close()

      local keywords = keywordstable[path]
      if (keywords) then
	-- LrDialogs.message("NDH", string.format("MATCH %s %s %s", path, filename, keywords))
	for kwhierarchy in keywords:gmatch("([^;]+);? *") do
	  -- LrDialogs.message("NDH", string.format("For %s kwhierarchy = %s", filename, kwhierarchy))
	  local lastkw;
	  for kw in kwhierarchy:gmatch(" *([^> ]+)>?") do
	    lastkw = kw
	  end
	  -- LrDialogs.message("NDH", string.format("KW >%s< for %s", lastkw, filename))

	  catalog:withWriteAccessDo("Create keyword", function()
	    kwhandle = catalog:createKeyword(lastkw, {}, true, rootkey, true) -- Create or get existing keyword
	    p:addKeyword(kwhandle)
	  end)
	end
	countmodified = countmodified + 1
      else
	-- LrDialogs.message("NDH", string.format("NOMATCH %s %s", path, filename))
	countunchanged = countunchanged + 1
      end

    end


  LrDialogs.message(string.format("Processed %d files: %d added keywords, %d unchanged",
    					       	countfiles, countmodified, countunchanged))

  return
end

-- Run main()
LrTasks.startAsyncTask(main)

