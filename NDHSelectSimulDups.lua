--[[-------------------------------------------------------------------------
NDHSelectSimulDups.lua
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
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  local newselphotos = {}
  if (photos == nil) then
    log("No selected photos")
    LrDialogs.message("NDH", "Usage: Select set of photos; the first in each timegroup will be unselected allowing the rest to be UnPicked")
    return
  end
  local lasttime = nil

  -- Iterate over all selected photos...
  -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
  for j, photo in ipairs(photos) do
    local filename = photo:getFormattedMetadata('fileName')
    local thistime = photo:getRawMetadata('dateTimeOriginal')
--    local msg = string.format("Photo %s: Time = %d = %s (%s)", filename, thistime, os.date("%c", thistime), os.date("%Y-%m-%dT%H:%M:%S", lasttime))
--    LrDialogs.message("NDH", msg)
    if (thistime == lasttime) then
--        photo:setRawMetadata('pickStatus', -1)
	table.insert(newselphotos, photo)
    end
    lasttime = thistime
  end

  local firstsel = newselphotos[1]
  if (firstsel) then
   -- catalog:withWriteAccessDo("Set Offset Keyword", function()
      catalog:setSelectedPhotos(firstsel, newselphotos)
   -- end)
  end
    

  LrDialogs.message("NDH", "Done")
 
end

-- Run main()
LrTasks.startAsyncTask(main)
