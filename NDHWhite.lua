--[[-------------------------------------------------------------------------
NDHUTCFromGPS.lua

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

verbose = true
verbose_flags["Metadata"] = false

-- Set up the logger
local logger = LrLogger('NDH')
logger:enable("print") -- set to "logfile" to write to ~/Documents/lrClassicLogs/NDH.log
local log = logger:quickf('info')

local trygps = false
local dofix = false

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

  
  -- Iterate over all selected photos...
  -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
  local brokenimages
  
  -- local setAsShot = { WhiteBalance = "As Shot" }
  -- applyDevelopSettings doesn't work for Auto stuff - does work for CropAngle.
  -- local setAsShot = { CropAngle = 10 }
  -- local setAuto =   { WhiteBalance = "Auto" }
  -- debugmessage("NDHData", string.format("setAsShot=%s\nsetAuto=%s", setAsShot, setAuto), "develop")
  
  local countfixed = 0
  
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
		 string.format("%s:\n", path) ..
	 	 -- string.format("RAW metadata=%s\n", format_table(rawmetadata, true)) ..
 	 	 -- string.format("FORMATTED metadata=%s\n", format_table(formattedmetadata, true)) ..
	 	 string.format("DEVELOP data=%s", format_table(developdata, true)) ..
	 	 "", "Metadata")

    if (developdata['Temperature'] == 2000) then
    
      if ((formattedmetadata['cameraModel'] == "NIKON 1 J5") and
	  (developdata['WhiteBalance'] == "Auto") and
          (developdata['Temperature'] == 2000) and
	  (developdata['Tint'] == -150)) then
	  
	brokenimages = stringbuild(brokenimages, path, "\n")

	if (dofix) then
	  local write = catalog:withWriteAccessDo("setRawMetadata1", function()
	    debugmessage("NDHLoadMetadata", string.format("Fixed %s", path), "fix")
	    -- p:applyDevelopSettings(setAsShot, nil, true) -- doesn't work
	    -- p:applyDevelopSettings(setAuto, nil, true) -- doesn't work
	    p:quickDevelopSetWhiteBalance("As Shot")
	    p:quickDevelopSetWhiteBalance("Auto")
	  end)
	  if (write ~= "executed") then
	    debugmessage("NDHLoadMetadata", string.format("Write failed: %s (setRawMetadata1)", write), "writeaccess")
	  else
	    countfixed = countfixed + 1
	  end
	end

      else
        debugmessage("NDHData", string.format("%s: Outlier: Cam=%s, WB=%s, Temp=%s, Tint=%s AutoWhite=%s",
				path,
      				formattedmetadata['cameraModel'],
	  			developdata['WhiteBalance'],
          			developdata['Temperature'],
	  			developdata['Tint'],
				developdata['AutoWhite']), "data")
	
      end
    else
      if (developdata['AutoWhiteVersion'] == "134348800") then
        debugmessage("NDHData", string.format("%s: AutoWhite: Cam=%s, WB=%s, Temp=%s, Tint=%s AutoWhite=%s",
				path,
      				formattedmetadata['cameraModel'],
	  			developdata['WhiteBalance'],
          			developdata['Temperature'],
	  			developdata['Tint'],
				developdata['AutoWhite']), "data")
      end
    end
  end

  debugmessage("NDHData", string.format("Fixed: %d\n%s", countfixed, brokenimages), "fix")

  return
end


-- Run main()
LrTasks.startAsyncTask(main)
