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

  local verbose = (#photos < 2)
  -- LrDialogs.message("NDH debug", string.format("Verbose = %s count = %d", verbose, #photos))

  local offsetlast
  
  --  LrDialogs.resetDoNotShowFlag()

  -- Iterate over all selected photos...
  -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
  for j, p in ipairs(photos) do
    local filename = p:getFormattedMetadata('fileName')
    local path = p:getRawMetadata('path')
    local camera = p:getFormattedMetadata('cameraMake')
    if (verbose) then
      -- Debugging available metadata...
      local metadata = p:getRawMetadata(nil)
      LrDialogs.message("NDH debug metadata", string.format("%s: RAW metadata=%s", filename, format_table(metadata)))
    end
    if (false and camera ~= 'Apple' and camera ~= 'Google') then -- TEMP try all images HEREHERE
      if (verbose) then
	-- Debugging available metadata...
        local metadata = p:getRawMetadata(nil)
        LrDialogs.message("NDH debug metadata", string.format("%s: RAW metadata=%s", filename, format_table(metadata)))
	-- Skip
        LrDialogs.message("NDH", string.format("Skipping %s (%s)", filename, camera))
      end
    else

      -- -- Debugging available metadata...
      -- local metadata = p:getRawMetadata(nil)
      -- LrDialogs.message("NDH debug metadata", string.format("%s: RAW metadata=%s", filename, format_table(metadata)))

      -- Debugging available metadata...
      -- metadata = p:getFormattedMetadata(nil)
      -- LrDialogs.message("NDH debug metadata", string.format("%s: FORMATTED metadata=%s", filename, format_table(metadata)))

      -- -- Get date/time metadata from LR
      -- local datetime = p:getRawMetadata('dateTime') --> comes up with erroneous date in 1978 - obviously an epoch bug
      -- local datetimeoriginal = p:getRawMetadata('dateTimeOriginal')  --> comes up with erroneous date in 1978 - obviously an epoch bug

      -- Original time recorded in the file from the camera clock or adjusted at import on phone pics.
      local datetimeiso = p:getRawMetadata('dateTimeISO8601') --> "2018-01-01T00:35:57"
      local datetime, datetimeoffset = timefromisostring(datetimeiso)

      -- Current working time in Lightroom.
      local datetimeoriginaliso = p:getRawMetadata('dateTimeOriginalISO8601') --> "2018-01-01T00:35:57.962" or "2018-01-01T00:35:57.962-08:0"
      local datetimeoriginal, datetimeoriginaloffset = timefromisostring(datetimeoriginaliso)

      -- Get gps date/time fields (if enabled)
      local datetimegps, datetimegpsoffset
      if (trygps) then
        local pipecommand = string.format('/usr/local/bin/exiftool -f -p \'$GPSDateTime,$OffsetTime\' \'%s\'', path)
        local pipe = io.popen(pipecommand)
        local result = pipe:read()
        pipe:close()
	local gpsdatetime, gpsoffset = string.match(result, "([^,]+),([^%c]+)")
	datetimegps, datetimegpsoffset = timefromgpsstring(gpsdatetime, gpsoffset) -- Z time of GPS, plus timeoffset as calculated by exiftool from extensions on timestamps.
        -- LrDialogs.message("NDH debug gps", string.format("%s\ngpsdatetimestring=%s (%s) (%s)", path, result, gpsdatetime, gpsoffset))
      end

      -- Handle DNG/PNG/PSDs where datetime is the time of creation of the file, nothing to do with the image.
      local type = string.match(filename, "%.(.-)$")
      if (type) then
        type = string.lower(type)
	if (type ~= 'psd' and type ~= 'png' and type ~= 'dng') then
          type = nil
	end
      end


      -- And if the datetime is more than 24h away from datetimeoriginal, it's probably wrong.
      if (datetime and datetimeoriginal and (datetime - datetimeoriginal) > 24*60*60 or type) then
        -- LrDialogs.message("NDH debug", string.format("%s: datetime %d >> datetimeoriginal %d or type %s, resetting", filename, datetime, datetimeoriginal, type))
	datetime = nil
      end

      --
      -- Calculate offset from ORIGINAL CAPTURE TIME (dateTime)
      --
      
      -- First try with datetimegps (if set)
      local dbg = ''
      if (datetime ~= nil and datetimegps ~= nil) then
        offset = round((datetime - datetimegps)/900)/4 -- Round to nearest 900 seconds = 15 mins.
        dbg = dbg .. string.format("%f Offset from GPS\n", offset)
      end

      -- Next try with datetimegpsoffset (if set)
      if (offset == nil and datetimegpsoffset ~= nil) then
        offset = round(datetimegpsoffset/900)/4
        dbg = dbg .. string.format("%f Direct Offset from GPS\n", round(datetimegpsoffset/900)/4)
      end

      -- Next try offset captured from dateTimeISO
      if (offset == nil and datetimeoffset ~= nil) then
        offset = round(datetimeoffset/900)/4
        dbg = dbg .. string.format("%f Direct Offset from datetime\n", round(datetimeoffset/900)/4)
      end

      -- Next try  offset captured from dateTimeOriginalISO
      if (offset == nil and datetimeoriginaloffset ~= nil) then
        offset = round(datetimeoriginaloffset/900)/4
        dbg = dbg .. string.format("%f Direct Offset from datetimeoriginal\n", round(datetimeoriginaloffset/900)/4)
      end

      -- If none of the above work, reuse the time from the last photo processed.
      if (offset == nil and offsetlast ~= nil) then
        offset = offsetlast
        dbg = dbg .. string.format("%f Offset from previous photo\n", offsetlast)
      end

      -- HEREHERE

      if (offset == nil) then
        dbg = dbg .. "No offset at all\n"
      end

      --
      -- Calculate correction needed on OPERATING TIME (dateTimeOriginal)
      -- We should have an "offset" in hours (to .25) which is best guess
      -- Invariant upon repeat use...
      --
      local dbgaction
      local targettime
      local remainingoffset
      local addkeyword, addkeyoffset, unlesskeyword
      if (offset == nil) then
        dbgaction = 'INSUFFICIENT DATA'
      else
        offsetlast = offset
	addkeyoffset = 'TimeOffset=' .. decimal(offset)
        -- See if we are already adjusted in DATE TIME ORIGINAL
	-- For preference, use datetime which is the unmodified version if we might have already offset this photo.
	-- If there is no datetime, then try datetimeoriginal

	if (datetime == nil or datetimeoriginal == nil) then
	  addkeyword = 'DoTimeOffset=' .. decimal(offset)
	  unlesskeyword = 'DoneTimeOffset=' .. decimal(offset)
	  dbgaction = string.format("MAYBE WRITE KW %s Unless %s", addkeyword, unlesskeyword)
	else
	  targettime = (datetime or datetimeoriginal) - offset*3600
	  if (math.abs(targettime - datetimeoriginal) > 450) then
	    remainingoffset = round((datetimeoriginal - targettime)/900)/4
	    addkeyword = 'DoTimeOffset=' .. decimal(remainingoffset)
	    dbgaction = string.format("WRITE KW %s", addkeyword)
	  else
	    addkeyword = nil
	    dbgaction = 'NO CHANGE'
	  end
        end
      end

      -- fix MOV references (test with new)
      -- fix PNG double match (JPG E files from PNG get changed repeatedly)
      if (verbose) then
        LrDialogs.message("NDH debug times",
			  string.format("%s (%s):\ndatetime=%s(%d)\ndatetimeoriginal=%s(%d)\ndatetimegps=%s(%d)\n%s\noffset=%d\nDateTimeOriginal=%d\nNewDateTimeOriginal=%d (%s)\n%s",
			  		filename,
                                        camera,
                                        datetime and os.date("%Y-%m-%dT%H-%M-%S", datetime) or '-',
					datetimeoffset and datetimeoffset/3600 or -99,
                                        datetimeoriginal and os.date("%Y-%m-%dT%H-%M-%S", datetimeoriginal) or '-',
					datetimeoriginaloffset and datetimeoriginaloffset/3600 or 0,
                  			datetimegps and os.date("%Y-%m-%dT%H-%M-%S", datetimegps) or '-',
					datetimegpsoffset and datetimegpsoffset/3600 or 0,
					dbg,
					offset or 0,
					datetimeoriginal or 0,
					targettime or 0,
					targettime and os.date("%Y-%m-%dT%H-%M-%S", targettime) or '-',
      					dbgaction
                            ))
      end

      --
      -- Create and add the keyword, if needed
      --
      -- Update photo to have addkeyword = "DoTimeOffset=-08.75"
      -- Update photo to have addkeyoffset = "TimeOffset=-06.75"
      -- Update photo to have "TimeZ"
      -- Remove incorrect DoTimeOffset keywords


      catalog:withWriteAccessDo("Create keyword", function()

  --    p:setRawMetadata('dateCreated', '2023-01-04T14:51:51-08:00') -- Succeeds, but doesn't have the correct effect.
  --    p:setRawMetadata('dateTimeOriginal', '2005-09-20T15:10:55Z') -- Fails unimplemented.
  --	p:setRawMetadata('dateTime', 1568613164) -- Fails unimplemented.

	-- Create TimeZ keyword to attach to changed pics
	local rootkey = catalog:createKeyword('_Photography', {}, true, nil, true) -- Create or get existing keyword _Photography

	-- Remove any old words
	local keywords = p:getRawMetadata('keywords')
	for k, kw in ipairs(keywords) do
	  local kwname = kw:getName()
	  local s = string.match(kwname, "^(DoTimeOffset=[%+%-]?%d+.?%d*)")
	  if (s and s ~= addkeyword) then
	    LrDialogs.message("NDH debug assertion", string.format("Removing %s", s))
	    local keyDelete = catalog:createKeyword(s, {}, true, rootkey, true) -- Get existing keyword s
	    p:removeKeyword(keyDelete)
	  end
	  s = string.match(kwname, "^(TimeOffset=[%+%-]?%d+.?%d*)")
	  if (s and s ~= addkeyoffset) then
	    LrDialogs.message("NDH debug assertion", string.format("Removing %s", s))
	    local keyDelete = catalog:createKeyword(s, {}, true, rootkey, true) -- Get existing keyword s
	    p:removeKeyword(keyDelete)
	  end
	  if (kwname == unlesskeyword) then
	    addkeyword = 0
	  end
	end


	if (addkeyword ~= nil) then
	  LrDialogs.message("NDH debug assertion", string.format("Adding %s", s))
	  local keyDoTimeOffset = catalog:createKeyword(addkeyword, {}, true, rootkey, true) -- Create or get existing keyword DoTimeOffset=-08
	  p:addKeyword(keyDoTimeOffset)
	end
	local keyTimeOffset = catalog:createKeyword(addkeyoffset, {}, true, rootkey, true) -- Create or get existing keyword TimeOffset=-08
	p:addKeyword(keyTimeOffset)

	LrDialogs.message("NDH debug assertion", string.format("Adding %s", 'TimeZ'))
	local keyTimeZ = catalog:createKeyword('TimeZ', {}, true, rootkey, true) -- Create or get existing keyword TimeZ
	p:addKeyword(keyTimeZ)

      end)
    end
  end

  return
end


-- Run main()
LrTasks.startAsyncTask(main)

