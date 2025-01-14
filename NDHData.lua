--[[-------------------------------------------------------------------------
NdhUTCFromGPS.lua

Exploring LRSDK

---------------------------------------------------------------------------]]

--[[
This is the entry point function that's called when the Lightroom menu item is selected
]]

-- Set the names of root keyword and root collection set - can be edited to taste
local LrApplication = import 'LrApplication'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'
 
require 'NDHutils'

-- Set up the logger
local logger = LrLogger('NDH')
logger:enable("print") -- set to "logfile" to write to ~/Documents/lrClassicLogs/NDH.log
local log = logger:quickf('info')

local trygps = false

local function main ()

  log(" Starting")
  -- LrDialogs.message("NDH", "Starting Data")
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  if (photos == nil) then
    log("No selected photos")
    LrDialogs.message("NDH", "Usage: Select one or more photos to adjust")
    return
  end

  verbose = true
  
  -- Iterate over all selected photos...
  -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
  for j, p in ipairs(photos) do
    local filename = p:getFormattedMetadata('fileName')
    local path = p:getRawMetadata('path')
    local camera = p:getFormattedMetadata('cameraMake')

    local rawmetadata = p:getRawMetadata(nil)
    local formattedmetadata = p:getFormattedMetadata(nil)
    local developdata = p:getDevelopSettings()
    -- Explore custom metadata
    -- local custommetadata = rawmetadata['customMetadata']
    -- local gpsdata = custommetadata['info.regex.lightroom.gps.data']
    -- local gpstime = epochdate(gpsdata['time'])
    -- Print
    debugmessage("NDHData",
	 string.format("%s:\nRAW metadata=%s", pathcopy, format_table(rawmetadata, true)) ..
		 string.format("\nFORMATTED metadata=%s", format_table(formattedmetadata, true)) ..
		 string.format("\nDEVELOP data=%s", format_table(developdata, true)) ..
		 "", "Metadata")
  end

  return
end


-- Run main()
LrTasks.startAsyncTask(main)
