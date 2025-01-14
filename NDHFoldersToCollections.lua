--[[-------------------------------------------------------------------------
NDHFoldersToCollections.lua
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
  local catalog = LrApplication.activeCatalog()
  local sources = catalog:getActiveSources()
  if (sources == nil) then
    log("No sources")
    LrDialogs.message("NDH", "Usage: Select one or more folders against which to create keywords")
    return
  end

HERE
1. Iterate over folders
2. Skip subfolders (or subfolders with canonical names)
3. Iterate over Slides folders and flag corresponding images.

  -- Create or get rootkey and rootcollection
  local rootkey
  catalog:withWriteAccessDo("Create keyword", function()
    rootkey = catalog:createKeyword('NDHKeywords', {}, true, nil, true) -- Create or get existing keyword
  end)
  
  -- Iterate over all selected collections...
  for i, s in ipairs(sources) do
    local t
    if (type(s) == 'string') then t = s else t = s:type() end
    if (t == 'LrCollection') then
      local keyword = string.format("Collection:%s", s:getName())
      local collection = string.format("%s",s:getName())
      local key = nil
      local photos = s:getPhotos();
      local msg = string.format("Source %d: %s, contains %d photos; applying keyword: %s", i, s:getName(), #photos, keyword)
      local proceed = LrDialogs.confirm("NDH", msg, 'OK', 'Cancel', 'Skip')
      if (proceed == 'ok') then
	-- Get or Create the keyword in the catalog.
	catalog:withWriteAccessDo("Create keyword", function()
	  key = catalog:createKeyword(keyword, {}, true, rootkey, true) -- Create or get existing keyword
	  -- LrDialogs.message("NDH", string.format("Keyword %s created %s", keyword, key:getName()))
	end)
	-- Do the work on each photo:
	catalog:withWriteAccessDo("Add Keyword", function()
	  for k, photo in ipairs(photos) do
	    photo:addKeyword(key)
	  end
	end)
      elseif (proceed == 'skip') then
	-- loop around for next collection if any
      elseif (proceed == 'cancel') then
	return
      end	
    else
      LrDialogs.message("NDH", string.format("Usage: Selected source %s is not a collection", t))
      return
    end

  end
 
end

-- Run main()
LrTasks.startAsyncTask(main)
