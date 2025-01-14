--[[-------------------------------------------------------------------------
NDHLoadCaptions.lua

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

local function csvsplit (inputstr)
  local t={}
  local i = 20;
  local field
  while (inputstr and inputstr:len() > 0 and i > 0) do
    if (inputstr:sub(1, 1) == "\"") then
      field, inputstr = inputstr:match("\"([^\"]*)\",?(.*)")
      table.insert(t, field)
    else
      field, inputstr = inputstr:match("([^,]*),?(.*)")
      table.insert(t, field)
    end
    i = i - 1
  end
  return t
end

local captionsfile = "/Users/neilhunt/DriveNeil/0 Personal Folders/Lightroom/2023 CSV for Captions - Export.csv"

--[[
This is the entry point function that's called when the Lightroom menu item is selected
]]

local function main ()
  log(" Starting")
  -- LrDialogs.message("NDH", "Starting LoadCaptions")
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  if (photos == nil) then
    log("No selected photos")
    LrDialogs.message("NDH", "Usage: Select one or more photos to adjust")
    return
  end

  -- Load Captions File
  local captionstable = { }
  local line
  local first = true
  local countlines = 0
  local countcaptions = 0
  for line in io.lines(captionsfile) do
    countlines = countlines + 1
    line = line:gsub("%c$", "") -- chomp
    if (first) then
      if (line:find("Filename,New Caption") ~= 1) then
      	LrDialogs.message("NDH Set Captions", "File does not appear to have the right CSV")
	return
      end
      first = false
    else
      local t = csvsplit(line)
      local filename = t[1]
      local newcaption = t[2]
      if (newcaption and newcaption:len() > 3) then
      	captionstable[filename] = newcaption
	countcaptions = countcaptions + 1
      end
    end
  end

  LrDialogs.message("NDH", string.format("Read %d lines %d captions", countlines, countcaptions))

  -- Iterate over all selected photos...
  -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
  local countphotos = 0
  local countmodified = 0
  local countunchanged = 0
  for j, p in ipairs(photos) do
    countphotos = countphotos + 1
    local filename = p:getFormattedMetadata('fileName')
    local path = p:getRawMetadata('path')
    if (captionstable[path]) then
      local caption = captionstable[path]
      -- LrDialogs.message("NDH", string.format("Found file %s caption = %s (%d)", path, caption, caption:len()))
      local oldcaption = p:getFormattedMetadata("caption")
      if (oldcaption and oldcaption ~= "" and oldcaption ~= caption) then
        -- LrDialogs.message("NDH", string.format("For %s: BLOCK changing %s (%d) to %s (%d)", path, oldcaption, oldcaption:len(), caption, caption:len()))
	countunchanged = countunchanged + 1
      else
        catalog:withWriteAccessDo("Create keyword", function()
	  p:setRawMetadata("caption", caption)
        end)
        -- LrDialogs.message("NDH", string.format("For %s: Added caption %s", path, caption))
	countmodified = countmodified + 1
      end
    end
  end


  --  LrDialogs.resetDoNotShowFlag()



  LrDialogs.message(string.format("Processed %d photos: %d added captions, %d unchanged",
    					       	countphotos, countmodified, countunchanged))

  return
end

-- Run main()
LrTasks.startAsyncTask(main)






