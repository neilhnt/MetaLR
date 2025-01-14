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
verbose_flags["Metadata1"] = false
verbose_flags["Metadata2"] = false
verbose_flags["Metadata3"] = true
verbose_flags["presets"] = false
verbose_flags["folders"] = false

-- Set up the logger
local logger = LrLogger('NDH')
logger:enable("print") -- set to "logfile" to write to ~/Documents/lrClassicLogs/NDH.log
local log = logger:quickf('info')

local trygps = false
local dofix = true

local function main ()

  log(" Starting")
  -- LrDialogs.message("NDH", "Starting Auto")
  local catalog = LrApplication.activeCatalog()
  local photos = catalog:getTargetPhotos()
  if (photos == nil) then
    log("No selected photos")
    LrDialogs.message("NDH", "Usage: Select one or more photos to adjust")
    return
  end

  LrFunctionContext.postAsyncTaskWithContext("ProgressContextId", function(context)
  
    LrDialogs.attachErrorDialogToFunctionContext(context)
    progress = LrDialogs.showModalProgressDialog(
      {
        title = "Auto Developing Unedited Photos",
	caption = "",
        cannotCancel = false,
        functionContext = context
      }
    )
    LrTasks.sleep(0)
    
    progress:setIndeterminate()
    progress:setCaption(string.format("Loading settings to process %d photos", #photos))

    -- Setup edit settings
    local setProcess = { ProcessVersion = "15.4" } -- This is Process Version 6 (2024)

    -- Find presets
    local presetNDHAuto
    local presetNDHAutoClarity
    local presetNDHAutoTexture
    local presetNDHAutoClarityTexture
    local presetNDHClarity
    local presetNDHTexture
    local presetNDHClarityTexture
    local dbg
    local presetfolders = LrApplication.developPresetFolders()
    debugmessage("NDHAuto", string.format("developPresetFolders() = %s (%s)", presetfolders, type(presetfolders)), "folders")
    if (presetfolders ~= nil) then
      for i, folder in ipairs(presetfolders) do
	local foldername = folder:getName()
	if (foldername == "User Presets") then
	  local presets = folder:getDevelopPresets()
	  dbg = stringbuild(dbg, foldername, " + ")
	  if (presets ~= nil) then
	    for j, preset in ipairs(presets) do
	      local presetname = preset:getName()
	      dbg = stringbuild(dbg, presetname, ", ")
	      if (presetname == "NDH: Auto") then
		presetNDHAuto = preset
	      elseif (presetname == "NDH: Auto + Clarity + Texture") then
		presetNDHAutoClarityTexture = preset
	      elseif (presetname == "NDH: Auto + Clarity") then
		presetNDHAutoClarity = preset
	      elseif (presetname == "NDH: Auto + Texture") then
		presetNDHAutoTexture = preset
	      elseif (presetname == "NDH: Clarity") then
		presetNDHClarity = preset
	      elseif (presetname == "NDH: Texture") then
		presetNDHTexture = preset
	      elseif (presetname == "NDH: Clarity + Texture") then
		presetNDHClarityTexture = preset
	      end
	    end
	  end
	end
      end
    else
      dbg = "No folders"
    end
    debugmessage("NDHAuto", string.format("Preset folders: %s", dbg), "folders")
    if (presetNDHAuto ~= nil and presetNDHAutoClarity ~= nil and presetNDHAutoTexture ~= nil and presetNDHAutoClarityTexture ~= nil
                             and presetNDHClarity ~= nil     and presetNDHTexture ~= nil     and presetNDHClarityTexture ~= nil) then
      debugmessage("NDHAuto", "Presets found", "presets")
    else
      debugmessage("NDHAuto", string.format("Some Presets missing %s %s %s %s %s %s %s",
      			                    presetNDHAuto, presetNDHAutoClarity, presetNDHAutoTexture, presetNDHAutoClarityTexture,
					    presetNDHClarity, presetNDHTexture, presetNDHClarityTexture), "presets")
      return
    end

    local countfixprocess = 0
    local countfixpreset = 0
    local countfixexposure = 0
    local countfixclarity = 0
    local countfixtexture = 0
    local countfixnoise = 0

    -- The outer wrap of withWriteAccessDo seems even slower than the internal...
    -- local write = catalog:withWriteAccessDo("setRawMetadata", function()
    --
    
    -- Iterate over all selected photos...
    -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
    for j, p in ipairs(photos) do
      local filename = p:getFormattedMetadata('fileName')
      progress:setCaption(string.format("Processing %d (%s)", j, filename))
      local path = p:getRawMetadata('path')
      local camera = p:getFormattedMetadata('cameraMake')
      local rawmetadata = p:getRawMetadata(nil)
      local formattedmetadata = p:getFormattedMetadata(nil)
      local developdata = p:getDevelopSettings()

      local isvideo = rawmetadata['isVideo']
      if (not isvideo) then

	debugmessage("NDHData",
		     string.format("%s:\n", path) ..
		     string.format("RAW data=%s", format_table(rawmetadata, true)) ..
		     string.format("FORMATTED data=%s", format_table(formattedmetadata, true)) ..
		     string.format("DEVELOP data=%s", format_table(developdata, true)) ..
		     "", "Metadata")
		     
        --
	-- Start by fixing the process version to the latest
	--
	local processversion = developdata['ProcessVersion']
	debugmessage("NDHData",
		     string.format("%s:\n", path) ..
		     string.format("Process Version = %s\n", processversion) ..
		     -- string.format("AutoExposure = %s\n", developdata['AutoExposure']) ..
		     -- string.format("AutoBrightness = %s\n", developdata['AutoBrightness']) ..
		     -- string.format("AutoContrast = %s\n", developdata['AutoContrast']) ..
		     -- string.format("AutoShadows = %s\n", developdata['AutoShadows']) ..
		     -- string.format("DEVELOP data=%s", format_table(developdata, true)) ..
		     "", "Metadata1")
	if (processversion ~= "15.4") then
	  if (dofix) then
	    if (developdata['ProcessVersion'] ~= "15.4") then
	      local write = catalog:withWriteAccessDo("setRawMetadata1", function()
		p:applyDevelopSettings(setProcess, nil, true)
		countfixprocess = countfixprocess + 1
	      end)
	      if (write ~= "executed") then
		debugmessage("NDHLoadMetadata", string.format("Write failed: %s (setRawMetadata1)", write), "writeaccess")
	      end
	    end
	  end
	end

	--
	-- If exposure/contrast/white/black/highlight/shadow are set to default, apply Auto settings
	-- If clarity and texture are set to 0, apply 20.
	--
	local exposure = developdata['Exposure']
	local contrast2012 = developdata['Contrast2012']
	local whites2012 = developdata['Whites2012']
	local blacks2012 = developdata['Blacks2012']
	local highlights2012 = developdata['Highlights2012']
	local shadows2012 = developdata['Shadows2012']
	local clarity = developdata['Clarity2012']
	local texture = developdata['Texture']
	debugmessage("NDHData",
		     string.format("%s:\n", path) ..
		     string.format("Exposure = %s\n", exposure) ..
		     string.format("Contrast2012 = %s\n", contrast2012) ..
		     string.format("Highlights2012 = %s\n", highlights2012) ..
		     string.format("Shadows2012 = %s\n", shadows2012) ..
		     string.format("Whites2012 = %s\n", whites2012) ..
		     string.format("Blacks2012 = %s\n", blacks2012) ..
		     string.format("Clarity = %s\n", clarity) ..
		     string.format("Texture = %s\n", texture) ..
		     -- string.format("DEVELOP data=%s", format_table(developdata, true)) ..
		     "", "Metadata2")
	local doautoexposure = false
	if (exposure == 0 and contrast2012 == 0 and highlights2012 == 0 and shadows2012 == 0 and whites2012 == 0 and blacks2012 == 0) then
	  doautoexposure = true
	end
	local doclarity = false
	if (clarity == 0) then
	  doclarity = true
	end
	local dotexture = false
	if (texture == 0) then
	  dotexture = true
	end
	if (doautoexposure or doclarity or dotexture) then
	  if (dofix) then
	    local preset = nil
	    if (doautoexposure and not doclarity and not dotexture) then
	      countfixexposure = countfixexposure + 1
	      preset = presetNDHAuto
	    elseif (doautoexposure and doclarity and not dotexture) then
	      countfixexposure = countfixexposure + 1
	      countfixclarity = countfixclarity + 1
	      preset = presetNDHAutoClarity
	    elseif (doautoexposure and not doclarity and dotexture) then
	      countfixexposure = countfixexposure + 1
	      countfixtexture = countfixtexture + 1
	      preset = presetNDHAutoTexture
	    elseif (doautoexposure and doclarity and dotexture) then
	      countfixexposure = countfixexposure + 1
	      countfixclarity = countfixclarity + 1
	      countfixtexture = countfixtexture + 1
	      preset = presetNDHAutoClarityTexture
	    elseif (not doautoexposure and doclarity and not dotexture) then
	      countfixclarity = countfixclarity + 1
	      preset = presetNDHClarity
	    elseif (not doautoexposure and not doclarity and dotexture) then
	      countfixtexture = countfixtexture + 1
	      preset = presetNDHTexture
	    elseif (not doautoexposure and doclarity and dotexture) then
	      countfixclarity = countfixclarity + 1
	      countfixtexture = countfixtexture + 1
	      preset = presetNDHClarityTexture
	    else
	      debugmessage("NDHAuto", string.format("doautoexposure %s, doclarity %s, dotexture %s", doautoexposure, doclarity, dotexture), "assert")
	    end

	    local write = catalog:withWriteAccessDo("setRawMetadata2", function()
	      p:applyDevelopPreset(preset)
	      countfixpreset = countfixpreset + 1
	    end)
	    if (write ~= "executed") then
	      debugmessage("NDHLoadMetadata", string.format("Write failed: %s (setRawMetadata3)", write), "writeaccess")
	    end
	  end -- dofix
	end -- dostuff

	--
	-- If noise parameters are default, and ISO is high, the apply some noise filters
	--
	local luminancesmoothing = developdata['LuminanceSmoothing']
	local luminancenoisereductiondetail = developdata['LuminanceNoiseReductionDetail']
	local luminancenoisereductioncontrast = developdata['LuminanceNoiseReductionContrast']
	local colornoisereduction = developdata['ColorNoiseReduction']
	local colornoisereductiondetail = developdata['ColorNoiseReductionDetail']
	local colornoisereductionsmoothness = developdata['ColorNoiseReductionSmoothness']
	local isospeedrating = rawmetadata['isoSpeedRating']
	debugmessage("NDHData",
		     string.format("%s:\n", path) ..
		     string.format("LuminanceSmoothing = %s\n", luminancesmoothing) ..
		     string.format("LuminanceNoiseReductionDetail = %s\n", luminancenoisereductiondetail) ..
		     string.format("LuminanceNoiseReductionContrast = %s\n", luminancenoisereductioncontrast) ..
		     string.format("ColorNoiseReduction = %s\n", colornoisereduction) ..
		     string.format("ColorNoiseReductionDetail = %s\n", colornoisereductiondetail) ..
		     string.format("ColorNoiseReductionSmoothness = %s\n", colornoisereductionsmoothness) ..
		     -- string.format("DEVELOP data=%s", format_table(developdata, true)) ..
		     "", "Metadata3")
	-- LuminanceSmoothing = 0
	-- LuminanceNoiseReductionDetail = 50
	-- LuminanceNoiseReductionContrast = 0
	-- ColorNoiseReduction = 25
	-- ColorNoiseReductionDetail = 50
	-- ColorNoiseReductionSmoothness = 50
	if (luminancesmoothing == 0 and colornoisereduction == 25) then
	  if (isospeedrating > 320) then
	    if (isospeedrating <= 640) then
	      colornoisereduction = 50
	      colornoisereductionsmoothness = 25
	      luminancesmoothing = 50
	      luminancenoisereductiondetail = 50
	    elseif (isospeedrating <= 1600) then
	      colornoisereduction = 75
	      colornoisereductionsmoothness = 25
	      luminancesmoothing = 60
	      luminancenoisereductiondetail = 75
	    elseif (isospeedrating <= 3200) then
	      colornoisereduction = 80
	      colornoisereductionsmoothness = 25
	      luminancesmoothing = 70
	      luminancenoisereductiondetail = 80
	    elseif (isospeedrating <= 6400) then
	      colornoisereduction = 90
	      colornoisereductionsmoothness = 50
	      luminancesmoothing = 80
	      luminancenoisereductiondetail = 90
	    elseif (isospeedrating <= 12800) then
	      colornoisereduction = 100
	      colornoisereductionsmoothness = 75
	      luminancesmoothing = 90
	      luminancenoisereductiondetail = 100
	    else
	      colornoisereduction = 100
	      colornoisereductionsmoothness = 100
	      luminancesmoothing = 100
	      luminancenoisereductiondetail = 100
	    end
	    local setNoise = {
	    	  	       LuminanceSmoothing = luminancesmoothing,
	    	  	       LuminanceNoiseReductionDetail = luminancenoisereductiondetail,
	    	  	       LuminanceNoiseReductionContrast = luminancenoisereductioncontrast,
			       ColorNoiseReduction = colornoisereduction,
			       ColorNoiseReductionDetail = colornoisereductiondetail,
			       ColorNoiseReductionSmoothness = colornoisereductionsmoothness
	    	  	     }
	    local write = catalog:withWriteAccessDo("setRawMetadata3", function()
	      p:applyDevelopSettings(setNoise, nil, true)
	      countfixnoise = countfixnoise + 1
	    end)
	    if (write ~= "executed") then
	      debugmessage("NDHLoadMetadata", string.format("Write failed: %s (setRawMetadata3)", write), "writeaccess")
	    end
	  end -- (iso > 200)
	end -- (luminancesmoothing ~= 0 or colornoisereduction ~= 25)

      end -- not isvideo

      if (progress:isCanceled()) then
	return
      end

    end -- for in photos

    -- Outer wrap of withWriteAccessDo even slower...
    -- end) -- withWriteAccessDo
    -- if (write ~= "executed") then
    --   debugmessage("NDHLoadMetadata", string.format("Write failed: %s (setRawMetadata)", write), "writeaccess")
    -- end

    debugmessage("NDHData", string.format("Processed: %d photos\n%d process\n%d preset\n%d exposure\n%d clarity\n%d texture\n%d noise", #photos, countfixprocess, countfixpreset, countfixexposure, countfixclarity, countfixtexture, countfixnoise), "fix")

  end) -- FunctionContext

  return
end


-- Run main()
LrTasks.startAsyncTask(main)
