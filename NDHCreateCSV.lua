--[[-------------------------------------------------------------------------
NDHCreateCSV.lua

Exploring LRSDK

---------------------------------------------------------------------------]]

-- Set the names of root keyword and root collection set - can be edited to taste
local LrApplication = import 'LrApplication'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'
local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'
local LrPhotoInfo = import 'LrPhotoInfo'
local LrFileUtils = import "LrFileUtils"
local LrXml = import "LrXml"

require 'NDHiNat'
require 'NDHgps'
require 'NDHutils'

local prefs = LrPrefs.prefsForPlugin( nil )
-- Set defaults if never set before
if (prefs.gpxfile == nil) then
  prefs.gpxfile = '/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/Split/YEAR/2024GPX.gpx'
end
if (prefs.csvfile == nil) then
  prefs.csvfile = '/Users/neilhunt/DriveNeil/0 Personal Folders/Lightroom/PhotosWithDatesAndCaptions.csv'
end
prefs.gpxstatus = 'Not Loaded'
prefs.inattatus = 'Not Loaded'
prefs.capstatus = 'Not Loaded'

-- Set up the logger
local logger = LrLogger('NDH')
logger:enable("print") -- set to "logfile" to write to ~/Documents/lrClassicLogs/NDH.log
local log = logger:quickf('info')

local catalog = nil
local photos = nil

-- Defaults
local dryrun = false
local trygps = true -- up to and including 2019 contains GPSDateTime, BUT sometimes it's local time (in spite of having Z on the end)

verbose = true
verbose_flags["Metadata"] = false
verbose_flags["XML"] = false
verbose_flags["gpx"] = false
verbose_flags["Try TZ"] = false
verbose_flags["trkptB"] = false
verbose_flags["time format"] = false
verbose_flags["new time"] = false
verbose_flags["time offset"] = false
verbose_flags["GPX file"] = false
verbose_flags["TZ match"] = false
verbose_flags["TZ mismatch"] = false
verbose_flags["geolocate"] = false
verbose_flags["No DTO"] = false
verbose_flags["gpsdate"] = false
verbose_flags["caption"] = false
verbose_flags["output"] = false
verbose_flags["trkmatch"] = false
verbose_flags["Case A: geolocate"] = false
verbose_flags["Case B: trkpt"] = false
verbose_flags["Case C: Try TZ from GPS"] = false

local clearcapnotmatched = false -- Clear captions (without CaptionFromX) that no longer match
local cleartitlenotmatched = false -- Clear titles (without TitleFromX) that no longer match

local export = false
local progress

local function loadgpxfile(gpxfile)

  LrFunctionContext.postAsyncTaskWithContext("ProgressContextId", function(context)

    LrDialogs.attachErrorDialogToFunctionContext(context)
    
    progress = LrDialogs.showModalProgressDialog(
      {
        title = "Loading GPX file",
	caption = "",
        cannotCancel = false,
        functionContext = context
      }
    )
    LrTasks.sleep(0)
    
    progress:setIndeterminate()
    
    -- Load GPS file
    progress:setCaption("Loading GPX file")
    local gpxstring = LrFileUtils.readFile(gpxfile)
    debugmessage("NDHCreateCSV", string.format("Loaded %s: %d bytes", gpxfile, string.len(gpxstring)), "GPX file")
    -- progress:setPortionComplete(10,100)

    -- Parse GPX
    progress:setCaption("Parsing XML")
    gpxstring = string.gsub(gpxstring, "</gpx>%s*<[^<]+>%s*<gpx[^>]+>%s", "")
    gpxstring = string.gsub(gpxstring, "<gpxtpx:TrackPointExtension>", "<!-- gpxtpx:TrackPointExtension>")
    gpxstring = string.gsub(gpxstring, "</gpxtpx:TrackPointExtension>", "</gpxtpx:TrackPointExtension -->")
    local gpxxml = LrXml.parseXml(gpxstring)
    -- progress:setPortionComplete(20,100)

    debugmessage("NDHLoadXML", string.format("%s:\nRAW metadata=%s", gpxfile, gpxxml), "XML")

    progress:setCaption("Reading XML")
    -- Read XML
    local n = gpxxml:childCount()
    for i = 1,n do
      if (progress:isCanceled()) then
        prefs.gpxstatus = "Canceled"
        return
      end
      -- if (((i-1) % 10) == 0) then
        progress:setCaption(string.format("Reading %d of %d", i, n))
        -- progress.setPortionComplete(i, n)
	LrTasks.sleep(0)
      -- end
      NDHgps.parseGPXnode(gpxxml, i, n)
    end


    prefs.gpxstatus = string.format("Loaded %d trks (%d dups) %d trkpts (%d dups) from %s to %s UTC",
    		      			    NDHgps.counttrks,
						     NDHgps.countduptrks,
							       NDHgps.counttrkpts,
									 NDHgps.countduptrkpts, 
									                  stringfromtime(NDHgps.trkptsstart or 0),
								                                stringfromtime(NDHgps.trkptsend or 0))

    NDHgps.trkdebug()
  
  end)

end

local function loadcapfile(filename)

  LrFunctionContext.postAsyncTaskWithContext("ProgressContextId", function(context)

    LrDialogs.attachErrorDialogToFunctionContext(context)

    local status = NDHgps.loadcapfile(filename)
    prefs.capstatus = string.format("Loaded %s", status)

    NDHgps.capdebug()
    
  end)

end

local function loadinatfile(filename)

  LrFunctionContext.postAsyncTaskWithContext("ProgressContextId", function(context)

    LrDialogs.attachErrorDialogToFunctionContext(context)

    local status = NDHiNat.loadinatfile(filename)
    NDHiNat.inatdebug()
    
    prefs.inatstatus = string.format("Loaded %s", status)

  end)

end

local offsetlast = nil
local datetimeoriginallast = nil
local count
local file

local timemode = 'local'
local defaultoffset = -7*3600	-- Assume summertime in CA
local range = 300             -- 100 seconds tolerance of GPS track match


local function getcorephotodata(p, trygps)

  local filename = p:getFormattedMetadata('fileName')
  local filepath = p:getRawMetadata('path')
  local pathcopy = filepath
  local copyname = p:getFormattedMetadata('copyName')
  if (copyname ~= nil and copyname ~= "") then
    pathcopy = pathcopy .. "[" .. copyname .. "]"
  end
  local camera = p:getFormattedMetadata('cameraMake')

  -- Explore LrPhotoInfo
  -- Debugging available metadata...
  if (verbose_flags["Metadata"]) then
    local rawmetadata = p:getRawMetadata(nil)
    local formattedmetadata = p:getFormattedMetadata(nil)
    -- Explore custom metadata
    -- local custommetadata = rawmetadata['customMetadata']
    -- local gpsdata = custommetadata['info.regex.lightroom.gps.data']
    -- local gpstime = epochdate(gpsdata['time'])
    -- Print
     debugmessage("NDHCreateCSV",
	 string.format("%s:\nRAW metadata=%s", pathcopy, format_table(rawmetadata, true)) ..
		 string.format("\nFORMATTED metadata=%s", format_table(formattedmetadata, true)) ..
		 "", "Metadata")
  end

  --
  -- Get date/time metadata from LR
  -- 	   Some dates and times are recovered as a string, most are from the LR database in "Cocoa time"
  -- 	   Fixed Cocoa epoch used here - not necessarily right for other installations, or windows.
  --
  local capturetime = epochdate(p:getRawMetadata('captureTime'))
  local datetimeoriginal = epochdate(p:getRawMetadata('dateTimeOriginal'))
  local datetime = epochdate(p:getRawMetadata('dateTime'))
  local datetimeiso = p:getRawMetadata('dateTimeISO8601') --> "2018-01-01T00:35:57"
  local datetimeunix, datetimeoffset = timefromisostring(datetimeiso) -- Original time recorded in the file from the camera clock or adjusted at import on phone pics.
  local datetimeoriginaliso = p:getRawMetadata('dateTimeOriginalISO8601') --> "2018-01-01T00:35:57.962" or "2018-01-01T00:35:57.962-08:0"
  local datetimeoriginalunix, datetimeoriginaloffset = timefromisostring(datetimeoriginaliso) -- Current working time in Lightroom.
  local metadataoffset = datetimeoriginaloffset or datetimeoffset
  local gps = p:getRawMetadata('gps')

  -- Scan keywords for time related stuff
  local offset
  local offsetsource = ""
  local timez = nil
  local keywords = p:getRawMetadata('keywords')
  local keywordnames
  for x, key in ipairs(keywords) do
    local keyname
    repeat
      if (keyname == nil) then
	keyname = key:getName() -- starts with leaf name
      else
	keyname = key:getName() .. " > " .. keyname
      end
      key = key:getParent()
    until (key == nil)
    local offsetstring, offsetmins
    offsetsign, offsethours, offsetmins = string.match(keyname, "_Photography > TimeOffset=(\-?\+?)(%d+):?(%d*)")
    if (offsethours ~= nil) then
      if (offsetsign == "-") then
	offsetsign = -1;
      else
	offsetsign = 1;
      end
      if (offsetmins == nil or offsetmins == "") then
	offsetmins = "0"
      end
      offset = offsetsign * (tonumber(offsethours) * 3600 + tonumber(offsetmins) * 60) -- get the sign of offsetstring to multiply offsetmins too
      offsetsource = "Keyword"
      debugmessage("NDHCreateCSV", string.format("%s: Keyword Offset=%d", pathcopy, offset), "time offset")
    end
    if (keyname == "_Photography > TimeZ") then
      timez = true
    elseif (keyname == "_Photography > TimeLocal") then
      timez = false
    end
    keywordnames = stringbuild(keywordnames, keyname, "; ")
  end
  -- Cheap hack to make dq " into CSV-safe ""
  if (keywordnames) then
    keywordnames = string.gsub(keywordnames, '"', '""')
  end

  -- Get gps date/time fields
  -- if enabled
  -- if photo contains a GPS
  -- if the GPS is not added from Strava or nearby.
  local datetimegps, exiftimeoffset
  if (trygps and
      gps ~= nil and gps['latitude'] ~= nil and gps['longitude'] ~= nil and
      ((keywordnames == nil or (string.match(keywordnames, "GPSAdded") == nil and string.match(keywordnames, "GPSFrom") == nil)))) then

    local pipecommand = string.format('/usr/local/bin/exiftool -f -p \'$GPSDateTime,$OffsetTime\' \'%s\'', filepath) -- go to original not pathcopy
    local pipe = io.popen(pipecommand)
    local result = pipe:read()
    pipe:close()
    if (result) then
      local gpsdatetime, gpsoffset = string.match(result, "([^,]+),([^%c]+)")
      datetimegps, datetimegpsoffset = timefromgpsstring(gpsdatetime, gpsoffset) -- Z time of GPS, plus timeoffset as calculated by exiftool from extensions on timestamps.
    end
    debugmessage("NDHCreateCSV", string.format("%s\ngpsdatetimestring=%s (%s) (%s)", pathcopy, result, gpsdatetime, gpsoffset), "gpsdate")
  end

  debugmessage("NDHCreateCSV", string.format("%s:\n", pathcopy) ..
			       string.format("datetimeoriginal=%s\n", stringfromtime(datetimeoriginal or 0)) ..
			       string.format("datetime=%s\n", stringfromtime(datetime or 0)) ..
			       string.format("datetimeoriginaliso=%s\n", datetimeoriginaliso or "nil") ..
			       string.format("datetimeiso=%s\n", datetimeiso or "nil") ..
			       string.format("datetimeunix=%s\n", stringfromtime(datetimeunix or 0)) ..
			       string.format("datetimeoriginalunix=%s\n", stringfromtime(datetimeoriginalunix or 0)) ..
			       string.format("datetimeoffset=%s\n", metadataoffset) ..
			       string.format("capturetime=%s\n", stringfromtime(capturetime or 0)) ..
			       string.format("datetimegps=%s\n", (datetimegps and stringfromtime(datetimegps)) or "NIL") ..
			       string.format("exifoffset=%s (%s)\n", (exifoffset or 0), decimal(exifoffset or 0)) ..
			       "", "time format")

  --
  -- Get timestamps and pick the right ones...
  --
  local timesource = "DateTimeOriginal"
  local exception = ""

  --
  -- Some photos are missing key metadata
  -- make a best guess to dto, dt, ct
  --
  if (datetimeoriginal == nil) then
    if (capturetime ~= nil) then
      datetimeoriginal = capturetime
      timesource = "CaptureTime"
    elseif (datetime ~= nil) then
      datetimeoriginal = datetime
      timesource = "DateTime"
    else
      datetimeoriginal = 0
      timesource = "No times set"
    end
    exception = stringbuild(exception, string.format("No datetimeoriginal: guess %s", stringfromtime(datetimeoriginal)), "; ")
    debugmessage("NDHCreateCSV", string.format("%s: datetimeoriginal guess = %s (%s)",
					       pathcopy, datetimeoriginal, stringfromtime(datetimeoriginal)), "No DTO")
  end
  if (datetime == nil) then
    if (capturetime ~= nil) then
      datetime = capturetime
    elseif (datetimeoriginal ~= nil) then
      datetime = datetimeoriginal
    else
      datetime = 0
    end
  end
  if (datetimeunix == nil) then
    datetimeunix = datetimeoriginal
  end
  if (datetimeoriginalunix == nil) then
    datetimeoriginalunix = datetimeoriginal
  end

  -- And if the datetime is more than 24h away from datetimeoriginal, it's probably wrong.
  local delta = datetime and datetimeoriginal and (datetime - datetimeoriginal)
  if (delta and math.abs(delta) > 24*60*60) then
    -- LrDialogs.message("NDHCreateCSV", string.format("%s: datetime %d >> datetimeoriginal %d or type %s, resetting", filename, datetime, datetimeoriginal, type))
    -- datetime = datetimeoriginal
    exception = stringbuild(exception, string.format("Dates far apart: delta = %d (%s, %s)", 
							     delta,
							     stringfromtime(datetimeoriginal),
							     stringfromtime(datetime)), "; ")
  end

  -- Assert invariants:
  local dbg
  if (math.abs(datetime - datetimeunix) > 30) then
    dbg = stringbuild(dbg, string.format("%s: datetime %d ~= datetimeunix %d (%s, %s)", pathcopy, dateoriginaltime or 0, datetimeoriginalunix or 0, stringfromtime(datetime or 0), stringfromtime(datetimeunix or 0)), "\n")
  end
  if (math.abs(datetimeoriginal - datetimeoriginalunix) > 30) then
    dbg = stringbuild(dbg, string.format("%s: datetimeoriginal %d ~= datetimeoriginalunix %d (%s, %s)", pathcopy, dateoriginaltime or 0, datetimeoriginalunix or 0, stringfromtime(datetimeoriginal or 0), stringfromtime(datetimeoriginalunix or 0)), "\n")
  end
  if (dbg) then
    debugmessage("NDHCreateCSV", dbg, "Time Asserts")
  end
  
  -- At this point:
  --   datetimeoriginal is set to a good guess
  --   datetime could be nil if it was far far away
  --   datetimeoriginaloffset might be set or nil
  --   delta should be ignored

  -- Offset derived from:
  --  Offset (from keywords)
  --  MetadataOffset (from ISO string)
  --  Nearest preceeding photo.
  --  LATER: GPS guess from "nearest city" lookup, with timezone computation.
  if (offset ~= nil) then
    offsetlast = offset
    datetimeoriginallast = datetimeoriginal
  elseif (metadataoffset ~= nil) then
    offset = metadataoffset
    offsetlast = offset
    datetimeoriginallast = datetimeoriginal
    offsetsource = "ISO Time Metadata"
  elseif (offsetlast ~= nil and datetimeoriginallast ~= nil and math.abs(datetimeoriginal - datetimeoriginallast) < 7*24*3600) then
    offset = offsetlast
    datetimeoriginallast = datetimeoriginal
    offsetsource = "Carry forward from previous"
  else
    -- offset = defaultoffset
    -- offsetsource = "Guess (California summer)"
    dst, offset = isdst(datetimeoriginal)
    offsetlast = nil
    datetimeoriginallast = nil
    if (dst) then
      offsetsource = "Guess same as current local (dst)"
      offset = offset + 3600
    else
      offsetsource = "Guess same as current local (no dst)"
    end
  end

  --
  -- Initial estimate on timelocal or timeutc
  --

  local timelocal
  local timeutc

  --
  -- Figure out how to interpret times
  --
  if (timez == nil and timemode == nil and lasttimez ~= nil) then
    timez = lasttimez
  end
  if (timez == true) then
    timeutc = datetimeoriginal
    timelocal = datetimeoriginal + offset
  elseif (timez == false) then
    timelocal = datetimeoriginal
    timeutc = datetimeoriginal - offset
  elseif (timemode == 'utc') then
    timeutc = datetimeoriginal
    timelocal = datetimeoriginal + offset
  elseif (timemode == 'local') then
    timelocal = datetimeoriginal
    timeutc = datetimeoriginal - offset
  else

    -- HEREHERE

    -- if (camera == "Apple" or camera == "Google") then
    -- 	-- Phones generally originally captured in localtime.
    -- 	if (datetimeoriginal ~= datetime and math.abs(datetimeoriginal - datetime) < 10) then
    -- 	  -- Tweaked a little bit = that's interesting!
    -- 	  debugmessage("NDHCreateCSV", string.format("%s: %f ~~ %f (%s ~~ %s)", 
    -- 						     pathcopy,
    -- 							  datetimeoriginal, datetime, 
    -- 								    stringfromtime(datetimeoriginal),
    -- 									  stringfromtime(datetime)), "Mismatched Dates")
    -- 	end
    -- 	if (math.abs(datetimeoriginal - datetime) < 10) then
    -- 	  -- Up to 2017 and after 2023 - If it hasn't been tweaked, probably it's right
    -- 	  timelocal = datetimeoriginal
    -- 	  timesource = timesource or "datetimeoriginal"
    -- 	  status = "phone-unchanged"
    -- 	else -- (datetimeoriginal ~= datetime)
    -- 	  -- Phone pics from 2017..2023 adjusted to UTC which will leave timestamps different
    -- 	  -- Needs to be reset to localtime
    -- 	  timeutc = datetimeoriginal
    -- 	  timelocal = datetime
    -- 	  timesource = timesource or "datetimeoriginal and datetime"
    -- 	  status = "phone-tochange"
    -- 	end
    -- else -- NONPHONE Camera
    -- 	if ((datetimeoriginal < timefromisostring("2017-01-01T00:00:01Z")) or	-- looks like 2017 A7 is Z
    -- 	    (datetimeoriginal >= timefromisostring("2023-01-01T00:00:01Z"))) then
    -- 	  -- Non-phone cameras could be anywhere, but in general, shot in localtime, perhaps not adjusted for DST
    -- 	  if (datetimeoriginal == datetime) then
    -- 	    -- Might be shot in UK winter, or might be TZ not set.
    -- 	    timelocal = datetimeoriginal	   	 	    	       	     	-- timelocal from datetimeoriginal
    -- 	    timesource = timesource or "datetimeoriginal"
    -- 	    status = "nonphone-estimate"
    -- 	  else
    -- 	    -- Assume corrected for wrong timezone or DST
    -- 	    timelocal = datetimeoriginal						-- timelocal from datetimeoriginal
    -- 	    timesource = timesource or "datetimeoriginal"
    -- 	    status = "nonphone-estimate-fixed"
    -- 	  end
    -- 	else -- In 2017-2022 window
    -- 	  -- NONPHONE camera in UTC
    -- 	  timeutc = datetimeoriginal						-- timeutc from datetimeoriginal
    -- 	  timesource = timesource or "datetimeoriginal"
    -- 	  status = "nonphone-utc-from-guess"
    -- 	end
    -- end

    -- --
    -- -- If there is a GPS, compare with trkpts at different offsets
    -- --
    -- local trkpt = nil
    -- local trk = nil
    -- if (gps ~= nil) then
    -- 	local dbg = ""
    -- 	local tzoffsets = { -7, -8, 0, 1, 2, 7, 8, 9, -9, -10, -11, -12, 3, 4, 5, 6, 10, 11, 12 }
    -- 	local tryutc
    -- 	local lat = gps['latitude']
    -- 	local lon = gps['longitude']
    -- 	local dist
    -- 	local tzoff
    -- 	if (timelocal) then
    -- 	  for _, tzoffset in ipairs(tzoffsets) do
    -- 	    tryutc = timelocal - tzoffset*3600
    -- 	    dbg = dbg .. string.format("Try %s - %d = %s %d\n", stringfromtime(timelocal), tzoffset, stringfromtime(tryutc), tryutc)
    -- 	    trkpt = NDHgps.getnearesttrkpt(tryutc, 600)
    -- 	    if (trkpt) then
    -- 	      dist = NDHgps.gpsdiff(lat, lon, trkpt['lat'], trkpt['lon'])
    -- 	      if (dist > 100) then
    -- 		trkpt = nil
    -- 	      else
    -- 		tzoff = tzoffset
    -- 		break
    -- 	      end
    -- 	    end
    -- 	  end
    -- 	  if (trkpt) then
    -- 	    dbg = dbg .. string.format("Returns %d (%d) (delta_time=%d) %f %f %f vs %f %f (dist=%f)\n", tzoff, tryutc, tryutc - trkpt['t'], trkpt['lat'], trkpt['lon'], trkpt['ele'], lat, lon, dist)
    -- 	    -- Fix times if necessary
    -- 	    offset = tzoff
    -- 	    offsetlast = tzoff
    -- 	    if (timeutc ~= tryutc) then
    -- 	      timeutc = tryutc
    -- 	      timesource = "GPS location match"
    -- 	    end
    -- 	  else
    -- 	    dbg = dbg .. "Not found"
    -- 	  end
    -- 	elseif (timeutc) then
    -- 	  tryutc = timeutc
    -- 	  dbg = dbg .. string.format("Try %s %d\n", stringfromtime(timeutc), tryutc)
    -- 	  trkpt = NDHgps.getnearesttrkpt(tryutc, 600)
    -- 	  if (trkpt) then
    -- 	    dist = NDHgps.gpsdiff(lat, lon, trkpt['lat'], trkpt['lon'])
    -- 	    if (dist > 100) then
    -- 	      trkpt = nil
    -- 	    end
    -- 	  end
    -- 	  if (trkpt) then
    -- 	    dbg = dbg .. string.format("Returns (%d) (delta_time=%d) %f %f %f vs %f %f (dist=%f)\n", tryutc, tryutc - trkpt['t'], trkpt['lat'], trkpt['lon'], trkpt['ele'], lat, lon, dist)
    -- 	    -- We know timelocal is missing, but we don't know when it is.
    -- 	  else
    -- 	    dbg = dbg .. "Not found"
    -- 	  end
    -- 	else
    -- 	  dbg = dbg .. "Neither timelocal nor timeutc set"
    -- 	end
    -- 	debugmessage ("NDHGPS", dbg, "Try TZ")
    -- end

    -- --
    -- -- Try to figure out the time offset WITHOUT GPS
    -- --

    -- if (datetimegps and datetime) then
    -- 	-- Best guess for UTC is from GPS timestamp, if any.
    -- 	-- Calculate offset from ORIGINAL CAPTURE TIME so that it generates the same answer even after modification.
    -- 	offset = datetime and round((datetime - datetimegps)/900)/4
    -- 	offsetsource = string.format("datetime offset %s from GPS time", offset)
    -- elseif (datetimegpsoffset and datetime) then
    -- 	-- Next best guess is from the offset in the GPS date time string, if any.
    -- 	offset = datetimegpsoffset and round(datetimegpsoffset/900)/4
    -- 	offsetsource = string.format("direct offset %s from GPS", round(datetimegpsoffset/900)/4)
    -- elseif (datetimeoriginaloffset) then
    -- 	-- Next choice is to use the offset encoded in the datetimeoriginal string
    -- 	offset = round(datetimeoriginaloffset/900)/4
    -- 	offsetsource = string.format("direct offset %s from datetimeoriginal", round(datetimeoriginaloffset/900)/4)
    -- elseif (datetimeoffset and math.abs(delta) < 24*60*60) then
    -- 	-- Next choice is to use the offset encoded in the datetime string
    -- 	offset = round(datetimeoffset/900)/4
    -- 	offsetsource = string.format("direct offset %s from datetime", round(datetimeoffset/900)/4)
    -- else
    -- 	offsetsource = "no offset at all"
    -- end

    -- -- Offset ~= nil when there is a clear offset from the timestring or difference.
    -- if (offset ~= nil) then
    -- 	-- offsetlast = offset;
    -- else
    -- 	-- offset = offsetlast
    -- 	offsetsource = string.format("No offset; using last known %s", offsetlast)
    -- end

    -- --
    -- -- Calculate the best guesses
    -- --
    -- -- BROKEN HEREHERE
    -- local timelocal
    -- local timeutc
    -- local timeutc2
    -- local status = "unknown"

    -- -- datetimeoriginal is set to a good guess
    -- -- datetime could be nil if it was far far away
    -- if (camera == "Apple" or camera == "Google") then
    -- 	-- Phones generally originally captured in localtime.
    -- 	if (datetimeoriginal ~= datetime and math.abs(datetimeoriginal - datetime) < 10) then
    -- 	  -- Tweaked a little bit = that's interesting!
    -- 	  debugmessage("NDHCreateCSV", string.format("%s: %f ~~ %f (%s ~~ %s)", 
    -- 						     pathcopy,
    -- 							  datetimeoriginal, datetime, 
    -- 								    stringfromtime(datetimeoriginal),
    -- 									  stringfromtime(datetime)), "Mismatched Dates")
    -- 	end
    -- 	if (math.abs(datetimeoriginal - datetime) < 10) then
    -- 	  -- Up to 2017 and after 2023 - If it hasn't been tweaked, probably it's right
    -- 	  timelocal = datetimeoriginal
    -- 	  timeutc = timelocal - (offset or offsetlast or 0) *3600
    -- 	  timesource = timesource or "datetimeoriginal"
    -- 	  status = "phone-unchanged"
    -- 	else -- (datetimeoriginal ~= datetime)
    -- 	  -- Phone pics from 2017..2023 adjusted to UTC which will leave timestamps different
    -- 	  -- Needs to be reset to localtime
    -- 	  timeutc = datetimeoriginal
    -- 	  timelocal = datetime or timeutc + (offset or offsetlast or 0) *3600 -- if datetime is too far away (nil), then correct it back from UTC.
    -- 	  timeutc2 = timelocal - (offset or offsetlast or 0) *3600
    -- 	  timesource = timesource or "datetimeoriginal"
    -- 	  if (timeutc == timeutc2) then
    -- 	    status = "phone-restore"
    -- 	  else
    -- 	    status = "phone-guess"
    -- 	  end
    -- 	end
    -- else -- NONPHONE Camera
    -- 	if ((datetimeoriginal < timefromisostring("2017-01-01T00:00:01Z")) or		-- looks like 2017 A7 is Z
    -- 	    (datetimeoriginal >= timefromisostring("2023-01-01T00:00:01Z"))) then
    -- 	  -- Non-phone cameras could be anywhere, but in general, shot in localtime, perhaps not adjusted for DST
    -- 	  if (datetimeoriginal == datetime) then
    -- 	    -- Might be shot in UK winter, or might be TZ not set.
    -- 	    if(false) then
    -- 	      -- Assume offset from timestamp is bogus
    -- 	      offset = nil -- could be anything -- ignore.
    -- 	      offsetsource = offsetsource .. " killed"
    -- 	    end
    -- 	    -- Assume localtime using offset (from camera) or lastoffset (from nearby photos)
    -- 	    timelocal = datetimeoriginal	   	 	    	       	     	-- timelocal from datetimeoriginal
    -- 	    timeutc = timelocal - (offset or offsetlast or 0) *3600		-- timeutc via offset
    -- 	    timesource = timesource or "datetimeoriginal"
    -- 	    status = "nonphone-estimate"
    -- 	  else
    -- 	    -- Assume corrected for wrong timezone or DST
    -- 	    timelocal = datetimeoriginal						-- timelocal from datetimeoriginal
    -- 	    timeutc = timelocal - (offset or offsetlast or 0) *3600		-- timeutc via offset
    -- 	    timeutc2 = datetime							-- but could be better to use timeutc from datetime
    -- 	    timesource = timesource or "datetimeoriginal"
    -- 	    status = "nonphone-estimate-fixed"
    -- 	  end
    -- 	else -- In 2017-2022 window
    -- 	  -- NONPHONE camera in UTC use offset (likely offsetlast) to fix.
    -- 	  timeutc = datetimeoriginal						-- timeutc from datetimeoriginal
    -- 	  timelocal = timeutc + (offset or offsetlast or 0) *3600			-- timelocal via offset
    -- 	  timesource = timesource or "datetimeoriginal"
    -- 	  status = "nonphone-utc-from-guess"
    -- 	end
    -- end

  end -- if timemode

  debugmessage("NDHCreateCSV", string.format("%s\n", pathcopy) ..
  			       string.format("timez=%s\n", (timez or "nil")) ..
			       string.format("timemode=%s\n", (timemode or "nil")) ..
			       string.format("timesource=%s\n", (timesource or "nil")) ..
			       string.format("offsetsource=%s\n", (offsetsource or "nil")) ..
			       string.format("datetimeoriginal=%d (%s)\n", datetimeoriginal, stringfromtime(datetimeoriginal)) ..
			       string.format("datetime=%d (%s)\n", datetime, stringfromtime(datetime)) ..
			       string.format("offset=%d\n", offset) ..
			       string.format("timelocal=%s\n", stringfromtime(timelocal)) ..
			       string.format("timeutc=%s\n", stringfromtime(timeutc)) ..
			       "", "new time")

  assert(datetimeoriginal)
  assert(datetime)
  assert(timeutc)
  assert(timelocal)

  --
  -- Get other fields
  --
  local title = string.gsub(string.gsub(p:getFormattedMetadata('title') or '', '"', ''), '[\r\n]+', ' ')
  local caption = string.gsub(string.gsub(p:getFormattedMetadata('caption') or '', '"', ''), '[\r\n]+', ' ')
  local stars = p:getRawMetadata('rating')
  local flag = p:getRawMetadata('pickStatus')

  -- local test = 'abc\rdef\nghi\r\njkl'
  -- local tested = string.gsub(test, '[\r\n]+', ' ')
  -- local b = string.match(test, '\r')
  -- debugmessage("NDHCreateCSV", string.format("test '%s' tested '%s' b='%s'", test, tested, b), "line breaks")
  
  -- title = string.gsub(title, '[\r\n]+', ' ')
  -- caption = string.gsub(caption, '[\r\n]+', ' ')

  -- Get collections
  local collections = p:getContainedCollections()
  local cnames
  for x, c in ipairs(collections) do
    local cname
    repeat
      if (cname == nil) then
	cname = c:getName() -- starts with leaf name
      else
	cname = c:getName() .. " > " .. cname
      end
      c = c:getParent()
    until (c == nil)
    cnames = stringbuild(cnames, cname, "; ")
  end

  return filename, pathcopy, copyname, camera,
    capturetime, datetimeoriginal, datetime, datetimeiso, datetimeunix, datetimeoriginaliso, metadataoffset,
    timesource, offsetsource, exception,
    gps,
    keywordnames, offset, timez,
    timelocal, timeutc, datetimegps,
    title, caption, stars, flag,
    cnames

end

local function processphoto(p)

  local filename, pathcopy, copyname, camera,
    capturetime, datetimeoriginal, datetime, datetimeiso, datetimeunix, datetimeoriginaliso, metadataoffset,
    timesource, offsetsource, exception,
    gps,
    keywordnames, offset, timez,
    timelocal, timeutc, datetimegps,
    title, caption, stars, flag,
    cnames
    = getcorephotodata(p, trygps)

  -- This is the one time field you can write.
  -- catalog:withWriteAccessDo("setRawMetadata", function()
  --   p:setRawMetadata('dateCreated', '2010-09-04T21:10:16+02:00')
  -- end)

  --
  -- Generate the output
  --

  --
  -- If no GPS, try to find it in the tracklogs.
  -- If there is a GPS, verify the offset time.
  --
  local trkpt = nil
  local tzoffsetfromgpsmatch = ""
  local lat = ""
  local lon = ""
  local source
  local dist
  local newkeywordnames
  if ((datetimegps ~= nil and gps ~= nil) or (NDHgps.trkptsstart ~= nil and NDHgps.trkptsstart <= timeutc and NDHgps.trkptsend >= timeutc)) then
    -- Tracklog exists...
    -- Three cases:
    --   A: gps is empty, possible match and add with GPSAdded=Strava string.
    --   B: gps is present from prev match, if we have a better one, fix it; if not, delete it.
    --   C: gps is present from camera, test for timezone match, never update GPS from camera.
    if (gps == nil or gps['latitude'] == nil or gps['longitude'] == nil) then
      -- A: No GPS attached to the photo - see if we can find one from the tracklog
      trkpt = NDHgps.getnearesttrkpt(timeutc, range)
      if (trkpt) then
	-- Currently empty - add lat, lon
	lat = trkpt['lat']
	lon = trkpt['lon']
	source = trkpt['source']
	newkeywordnames = stringbuild(newkeywordnames, string.format("_Photography > GPSAdded=%s", source), "; ")
	debugmessage("NDHCreateCSV", string.format("Geolocated %s (%d near %d) at [%f %f %s %s]", pathcopy, timeutc, trkpt['t'], trkpt['lat'], trkpt['lon'], trkpt['ele'], trkpt['source']), "Case A: geolocate")
      end
    elseif (keywordnames ~= nil and string.match(keywordnames, "GPSAdded")) then -- (gps ~= nil and added from tracklog)
      -- B: gps present from previous match - see if it's changed.
      trkpt = NDHgps.getnearesttrkpt(timeutc, range)
      debugmessage("NDHCreateCSV", string.format("Trkpt: case B: prev strava match: return %s (%s %s %s)", trkpt or "NIL",
													   ((trkpt and trkpt['lat']) or ""),
													   ((trkpt and trkpt['lon']) or ""),
													   ((trkpt and trkpt['t']) or "")),
		   "Case B: trkpt")
      if (trkpt ~= nil) then
	dist = NDHgps.gpsdiff(gps['latitude'], gps['longitude'], trkpt['lat'], trkpt['lon'])
	source = trkpt['source']
	if (((trkpt['lat'] ~= oldlat or trkpt['lon'] ~= oldlon) and dist > 0.10)) then -- moves dist > 0.10 meters -- temporary
	  -- Overwrite old presumably bad GPS match
	  lat = trkpt['lat']
	  lon = trkpt['lon']
	  newkeywordnames = stringbuild(newkeywordnames, string.format("!GPSAdded; _Photography > GPSAdded=%s", source), "; ")
	else
	  -- No change - leave as they are
	  -- newkeywordnames = stringbuild(newkeywordnames, string.format("!GPSAdded; _Photography > GPSAdded=%s", source), "; ")
	end
      else
	if (oldlat or oldlon) then
	  if ((string.match(keywordnames, "GPSAdded=Strava")) and (NDHgps.trkptsstart ~= nil) and (NDHgps.trkptsstart <= timeutc) and (NDHgps.trkptsend >= timeutc)) then
	    -- No match, but had a strava match, and strava data is loaded, and strava data contains this timeutc --> kill it
	    lat = "!"
	    lon = "!"
	  elseif ((string.match(keywordnames, "GPSAdded=Strava")) and (NDHgps.adjctptsstart ~= nil) and (NDHgps.adjctptsstart <= timeutc) and (NDHgps.adjctptsend >= timeutc)) then
	    -- No match, but had a adjacentphoto match, and adjacentphotodata is loaded, and adjacentphotodatadata contains this timeutc --> kill it
	    lat = "!"
	    lon = "!"
	  else
	    -- We haven't loaded data that would contradict it, so keep it.
	  end
	else
	  -- No change - leave empty
	end
      end
    else
      -- C: gps present not from trkpt, so from camera - validate the time settings.
      -- Likely offsets in hours in order of likelihood
      local dbg
      if (datetimegps) then
        tzoffsetfromgpsmatch = round((timelocal - datetimegps) / 450) * 450
        dbg = string.format("TZOffset from EXIFGPS = %s (%d - %d)", tzoffsetfromgpsmatch, timelocal, (datetimegps or 0))
      else
	local oldlat = gps['latitude']
	local oldlon = gps['longitude']
        dbg = string.format("Trying range of offsets to match GPS (%f, %f) against tracklog", oldlat, oldlon)
	local tzoffsets = { 99,
			    -7*3600, -8*3600, 0*3600, 1*3600, 2*3600, 7*3600, 8*3600, 9*3600,
			    -9*3600, -10*3600, -11*3600, -12*3600, -5*3600, -4*3600, -3.5*3600, -3*3600, -2.5*3600, -2*3600, -1*3600,
			     3*3600, 4*3600, 5*3600, 5.5*3600, 6*3600, 10*3600, 11*3600, 12*3600 }
	local tryutc
	local rangetztimematch = 10 -- when matching timezone bands, more generous width for Julie being ahead or behind Neil (photos don't line up)
	local rangetzdistmatch = 10

	-- local besttrkpt
	for _, tzoffset in ipairs(tzoffsets) do
	  if (tzoffset == 99) then
	    tzoffset = timelocal - timeutc
	  end
	  tryutc = timelocal - tzoffset
	  dbg = stringbuild(dbg, string.format("Try %s - %d = %s %d ", stringfromtime(timelocal), tzoffset, stringfromtime(tryutc), tryutc), "\n")
	  local exclude = true -- exclude "AdjacentPhoto"
	  trkpt = NDHgps.getnearesttrkpt(tryutc, rangetztimematch, exclude)
	  if (trkpt) then
	    local delta = tryutc - trkpt['t']
	    dist = NDHgps.gpsdiff(oldlat, oldlon, trkpt['lat'], trkpt['lon'])
	    if (delta > rangetztimematch or dist > rangetzdistmatch) then
	      trkpt = nil
	      dist = nil
	    else
	      tzoffsetfromgpsmatch = tzoffset
	      break
	    end
	  end
	end
	if (trkpt) then
	  -- Check times
	  assert(tzoffsetfromgpsmatch ~= nil)
	  if (tzoffsetfromgpsmatch ~= offset) then
	    debugmessage("NDHGPS", string.format("%s: GPS match gives offset %d DOES NOT MATCH %d from %s", pathcopy, tzoffsetfromgpsmatch, offset, offsetsource), "TZ mismatch")
	  else
	    debugmessage("NDHGPS", string.format("%s: GPS match gives offset %d MATCHES OK %d from %s", pathcopy, tzoffsetfromgpsmatch, offset, offsetsource), "TZ match")
	  end
	  -- offset = tzoff
	  -- offsetlast = tzoff
	  -- if (timeutc ~= tryutc) then
	  --  timeutc = tryutc
	  --  timesource = "GPS location match"
	  -- end
	  -- See which lat/lon to keep
	  if (dist and dist > 10) then
	    dbg = dbg .. "Lat lon don't match\n"
	  end
	  dbg = dbg .. string.format("Returns %d (%d) (delta_time=%d) %f %f vs %f %f (dist=%s)\n", tzoffsetfromgpsmatch, tryutc, tryutc - trkpt['t'], trkpt['lat'], trkpt['lon'], oldlat or 0, oldlon or 0, dist or 0)
	  -- Never update camera GPS
	  -- if (oldlat ~= trkpt['lat] or oldlon ~= trkpt['lon']) then
	  --   lat = trkpt['lat']
	  --   lon = trkpt['lon']
	  -- end
	else
	  dbg = dbg .. "Not found"
	end
      end -- !datetimegps
      debugmessage("NDHCreateCSV", string.format("%s: tzoffsetfromgpsmatch=%s\n%s", tzoffsetfromgpsmatch, dbg), "Case C: Try TZ from GPS")
    end
  end

  -- Caption from GPS track data or caps file
  local newcaption
  local trk
  local cap
  local trknooverride = false
  if (NDHgps.trkptsstart ~= nil and NDHgps.trkptsstart <= timeutc and NDHgps.trkptsend >= timeutc) then 
    -- See if we have a caption from Strava
    trk = NDHgps.getbesttrk(timeutc, 0) -- range = 0 - no spillover.
    debugmessage("NDHCreateCSV", string.format("%s: trkmatch returned %s (%s)", pathcopy, (trk or "NIL"), ((trk and trk['trkname']) or "NIL")), "caption")
    if (trk and trk['trkname']) then
      -- Caption from strava
      newcaption = trk['trkname']
      newkeywordnames = stringbuild(newkeywordnames, "!Caption; _Photography > CaptionFromStrava", "; ")
      debugmessage("NDHCreateCSV", string.format("%s: getbesttrk = %s (%s <= %s <= %s)",
						  pathcopy,            trk['trkname'],
								       stringfromtime(trk['trk_t']),
									     stringfromtime(timeutc),
										   stringfromtime(trk['last_t'])), "caption")
    else
      -- Remove an erroneous trkname added from a bad track
      local captionfromstrava = (keywordnames ~= nil and string.match(keywordnames, "CaptionFromStrava"))
      if (captionfromstrava) then
	newkeywordnames = stringbuild(newkeywordnames, "!CaptionFromStrava", "; ")
      end
      if ((clearcapnotmatched or captionfromstrava) and
	  (caption ~= nil and caption ~= "")) then
	newcaption = "!"
	debugmessage("NDHCreateCSV", string.format("%s: no track match, !caption (%s %s)", pathcopy, clearcapnotmatched, captionfromstrava), "trkmatch")
      else
	debugmessage("NDHCreateCSV", string.format("%s: no track match", pathcopy), "trkmatch")
      end
    end
  else
    if (keywordnames ~= nil and string.match(keywordnames, "CaptionFromStrava")) then
      trknooverride = true -- block overwriting of caption from Strava if we haven't loaded gps
    end
  end
  if (not trknooverride and (newcaption == nil or newcaption == "!") and NDHgps.capstart ~= nil and NDHgps.capstart <= math.max(timelocal, timeutc) and NDHgps.capend ~= nil and NDHgps.capend >= math.min(timelocal, timeutc)) then
    cap = NDHgps.capmatch(timelocal, timeutc, pathcopy)
    debugmessage("NDHCreateCSV", string.format("%s: capmatch returned %s (%s)", pathcopy, (cap or "NIL"), ((cap and cap['Activity Name']) or "NIL")), "caption")
    if (cap and cap['Activity Name']) then
      -- Found new caption name
      newcaption = cap['Activity Name']
      newkeywordnames = stringbuild(newkeywordnames, "!Caption; _Photography > CaptionFromTable", "; ")
      debugmessage("NDHCreateCSV", string.format("%s: capmatch = %s (%s <= %s <= %s)",
						  pathcopy,          cap['Activity Name'],
								     cap['Activity Start Local'],
									   stringfromtime(timelocal),
										 (cap['Activity End Local'] or "NIL")), "caption")
    else
      -- Remove an erroneous caption added from a bad track
      local captionfromtable = (keywordnames ~= nil and string.match(keywordnames, "CaptionFromTable"))
      if (captionfromtable) then
	newkeywordnames = stringbuild(newkeywordnames, "!CaptionFromTable", "; ")
      end
      if ((clearcapnotmatched or captionfromtable) and
	  (caption ~= nil and caption ~= "")) then
	newcaption = "!"
	debugmessage("NDHCreateCSV", string.format("%s: no caption match, !caption (%s %s)", pathcopy, clearcapnotmatched, captionfromtable), "trkmatch")
      else
	debugmessage("NDHCreateCSV", string.format("%s: no caption match", pathcopy), "trkmatch")
      end
    end
  end

  -- Try to match iNat
  local newtitle = ""
  local inatid = ""
  local inatphotoid = ""
  local inatphoto = ""
  local titlefrominat = (keywordnames ~= nil and string.match(keywordnames, "TitleFromINat"))
  if (NDHiNat.inatstart ~= nil and NDHiNat.inatstart <= timelocal and NDHiNat.inatend >= timelocal) then
    local p = NDHiNat.inatmatch(pathcopy, filename, camera, timelocal, timeutc)
    if (p ~= ni) then
      local commonname = titlecaps(p['CommonName'])
      local taxonname = p['TaxonName']
      local candidatetitle = string.format("%s (%s)", commonname, taxonname)
      inatid = p['ID']
      if (title == "" or titlefrominat or cleartitlenotmatched) then
	newtitle = candidatetitle
	local oldid = nil
	if (keywordnames ~= nil) then
	  oldid = string.match(keywordnames, "INatID=\"?(%d+)\"?")
	end
	-- debugmessage("NDHCreateCSV", string.format("Matched old INatID %s vs %s\n %s", oldid, p['ID'], keywordnames), "id match")
	if (oldid ~= nil and oldid ~= p['ID']) then
	  newkeywordnames = stringbuild(newkeywordnames, "!INatID", "; ") -- remove wrong old ID
	end
	newkeywordnames = stringbuild(newkeywordnames, "_Photography > TitleFromINat2024; _Photography > INat > INatID=" .. p['ID'], "; ")
	if (p['Taxonomy'] ~= nil and p['Taxonomy'] ~= "") then
	  newkeywordnames = stringbuild(newkeywordnames, "!_Taxonomy; _Nature > _Taxonomy > " .. p['Taxonomy'], "; ")
	end
	if (p['Hierarchy'] ~= nil and p['Hierarchy'] ~= "") then
	  newkeywordnames = stringbuild(newkeywordnames, "!_Common; _Nature > _Common > " .. p['Hierarchy'], "; ")
	end
	if (p['Quality'] ~= nil and p['Quality'] ~= "") then
	  newkeywordnames = stringbuild(newkeywordnames, "_Photography > INat > INatQuality=" .. p['Quality'], "; ")
	end
	inatphotoid = p['PhotoID']
	inatphoto = p['Filename']
      else
        debugmessage("NDHCreateCSV", string.format("%s: Existing title '%s' not overwritten '%s'", path, title, candidatetitle), "warning")
      end
    else
      -- Remove erroneous title/keywords from a bad match
      if (titlefrominat) then
	newkeywordnames = stringbuild(newkeywordnames, "!TitleFromINat; !InINat; !INatID; !INatQuality", "\; ")
      end
      if ((cleartitlenotmatched or titlefrominat) and
	  (title ~= nil and title ~= "")) then
	newtitle = "!"
      end
    end
    debugmessage("NDHCreateCSV", string.format("INat: title=%s, keywordnames=%s", newtitle, newkeywordnames), "INat output")
  end

  local datetimeoriginalstr = stringfromtime(datetimeoriginal)
  local datetimestr = stringfromtime(datetime or 0)
  local timeutcstr = stringfromtime(timeutc)
  local timelocalstr = stringfromtime(timelocal)
  local datetimegpsstr = (datetimegps and stringfromtime(datetimegps)) or ""
  local tzoffseterror = ""
  if (tzoffsetfromgpsmatch ~= nil and offset ~= nil and tzoffsetfromgpsmatch ~= "" and tzoffsetfromgpsmatch ~= offset) then
    tzoffseterror = "TZError"
  end
  
  debugmessage("NDHCreateCSV",
	       string.format("Pathname=\"%s\"\n", pathcopy) ..
	       string.format("DateTimeOriginal=%s\n", datetimeoriginalstr) ..
	       string.format("DateTime=%s\n", datetimestr) ..
	       string.format("Offset=%s\n", offset or "") ..
	       string.format("OffsetLast=%s\n", offsetlast or "") ..
	       string.format("OffsetFromGPSMatch=%s\n", tzoffsetfromgpsmatch) ..
	       string.format("OffsetError=%s\n", tzoffseterror) ..
	       string.format("TimeSource=\"%s\"\n", timesource) ..
	       string.format("Exception=\"%s\"\n", exception) ..
	       string.format("OffsetSource=\"%s\"\n", offsetsource or "") ..
	       string.format("TimeLocal=%s\n", timelocalstr) ..
	       string.format("TimeUTC=%s\n", timeutcstr) ..
	       string.format("DateTimeGPS=%s\n", datetimegpsstr) ..
	       string.format("Camera=%s\n", camera) ..
	       string.format("Status=%s\n", status) ..
	       string.format("OldLat=%s\n", ((gps and gps['latitude']) or "")) ..
	       string.format("OldLong=%s\n", ((gps and gps['longitude']) or "")) ..
	       string.format("NewLat=%s\n", ((trkpt and trkpt['lat']) or "")) ..
	       string.format("NewLong=%s\n", ((trkpt and trkpt['lon']) or "")) ..
	       string.format("Dist=%s\n", dist or "") ..
	       string.format("Lat=%s\n", lat) ..
	       string.format("Long=%s\n", lon) ..
	       string.format("OldTitle=\"%s\"\n", title) ..
	       string.format("Title=\"%s\"\n", newtitle) ..
	       string.format("OldCaption=\"%s\"\n", caption) ..
	       string.format("Trkname=\"%s\"\n", (trk and trk['trkname']) or "") ..
	       string.format("Capname=\"%s\"\n", (cap and cap['Activity Name']) or "") ..
	       string.format("Caption=\"%s\"\n", newcaption or "") ..
	       string.format("OldKeywords=\"%s\"\n", keywordnames or "") ..
	       string.format("Keywords=\"%s\"\n", newkeywordnames or "") ..
	       string.format("Collections=\"%s\"\n", cnames or "") ..
	       string.format("INatID=\"%s\"\n", inatid) ..
	       string.format("INatPhotoID=\"%s\"\n", inatphotoid) ..
	       string.format("INatPhoto=\"%s\"\n", inatphoto) ..
	       "", "output")

  if (not dryrun) then

    if (count == 0) then
      file:write("Pathname,DateTimeOriginal,DateTime,Offset,OffsetLast,OffsetFromGPSMatch,OffsetError,TimeSource,Exception,OffsetSource,TimeLocal,TimeUTC,DateTimeGPS,Camera,Status,OldLat,OldLong,NewLat,NewLong,Dist,Lat,Long,Flag,Stars,OldTitle,Title,OldCaption,TrackName,CaptionName,Caption,OldKeywords,Keywords,Collections,INatID,INatPhotoID,INatPhoto\n")
    end

    --                           pa   da da of of of   err    tsrc   excp   osrc ti ti gt ca st ol ol nl nl di la lo fl st   oldti  nwtit  oldca  trknm  capnm  cap    oldke  key    coll ID PID  Photo
    local txt = string.format("\"%s\",%s,%s,%s,%s,%s,\"%s\",\"%s\",\"%s\",\"%s\",%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",%s,%s,\"%s\"\n",
				 csvprotect(pathcopy),
				      datetimeoriginalstr,
					 datetimestr,
					    offset or "",
					       offsetlast or "",
						  tzoffsetfromgpsmatch or "",
							 tzoffseterror or "",
							      csvprotect(timesource or ""),
								     csvprotect(exception),
									    csvprotect(offsetsource or ""),
										 timelocalstr,
										    timeutcstr,
										       datetimegpsstr,
											  camera,
											     status,
												(gps and gps['latitude']) or "",
												   (gps and gps['longitude']) or "",
												      (trkpt and trkpt['lat']) or "",
													 (trkpt and trkpt['lon']) or "",
													    (dist or ""),
													       lat,
														  lon,
														     flag,
															stars,
															     csvprotect(title),
																    csvprotect(newtitle),
																	   csvprotect(caption),
																		  csvprotect((trk and trk['trkname']) or ""),
																			 csvprotect((cap and cap['Activity Name']) or ""),
																				csvprotect(newcaption or ""),
																				       csvprotect(keywordnames or ""),
																					      csvprotect(newkeywordnames or ""),
																						     csvprotect(cnames or ""),
																							  inatid,
																							     inatphotoid,
																								  csvprotect(inatphoto))

	  file:write(txt)

  end

  if (offset ~= nil) then
    offsetlast = offset;
  end

  count = count + 1

end

--
-- OLD
--
-- Get the data for each photo, match to GPS, with "range" time interval (default 100s).
--
-- local function processphotos(csvfile)

--   -- Open the file early in case it fails
--   if (not dryrun) then
--     file = io.open(csvfile, "w")
--   end

--   --
--   -- Iterate over all selected photos...
--   -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
--   --
--   for pass = 1, 1 do
--     count = 0
--     for j, p in ipairs(photos) do
--       processphoto(p)
--     end -- for ipairs photos
--   end -- pass = 1, 2
  
--   if (not dryrun) then
--     file:close()
--     LrDialogs.message("NDHCreateCSV", string.format("Wrote %d entries in %s", count, csvfile))
--   else
--     LrDialogs.message("NDHCreateCSV", string.format("Dryrun %d entries for %s", count, csvfile))
--   end
--   return
-- end

local photogpsloaded = nil

local function extractphotogps()

  LrFunctionContext.postAsyncTaskWithContext("ProgressContextId", function(context)

    LrDialogs.attachErrorDialogToFunctionContext(context)
    
    progress = LrDialogs.showModalProgressDialog(
      {
        title = "Extracting GPS from Photos",
	caption = "",
        cannotCancel = false,
        functionContext = context
      }
    )
    LrTasks.sleep(0)
    
    progress:setIndeterminate()

    local startingtrkpts = NDHgps.counttrkpts
    
    --
    -- Iterate over all selected photos...
    -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
    --
    count = 0
    for j, p in ipairs(photos) do

      local gps = p:getRawMetadata('gps')
      if (gps ~= nil) then
    
	local filename, pathcopy, copyname, camera,
	  capturetime, datetimeoriginal, datetime, datetimeiso, datetimeunix, datetimeoriginaliso, metadataoffset,
	  timesource, offsetsource, exception,
	  gps,
	  keywordnames, offset, timez,
    	  timelocal, timeutc, datetimegps,
	  title, caption, stars, flag,
	  cnames
	  = getcorephotodata(p, false) -- trygps=false for this pass.

	if ((keywordnames == nil or (string.match(keywordnames, "GPSAdded") == nil and string.match(keywordnames, "GPSFrom") == nil)) and
	    -- (camera == "Apple" or camera == "Google") and
	   true) then
          local filename = p:getFormattedMetadata('fileName')
          progress:setCaption(string.format("Processing %d (%s)", count, filename))
	  NDHgps.savetrkpt(timeutc, gps['latitude'], gps['longitude'], 0, "AdjacentPhoto")
	end

	if (progress:isCanceled()) then
	  -- prefs.gpxstatus = "Canceled"
	  return
	end

      end -- if gps
      count = count + 1
    end -- for photos

    local status = string.format("Extracted %d trkpts", NDHgps.counttrkpts - startingtrkpts)
    prefs.extractstatus = string.format("Loaded %s", status)
    photogpsloaded = true

  end)
  
end

local function createCSV(filename)

  LrFunctionContext.postAsyncTaskWithContext("ProgressContextId", function(context)

    LrDialogs.attachErrorDialogToFunctionContext(context)
    
    progress = LrDialogs.showModalProgressDialog(
      {
        title = "Creating CSV file",
	caption = "",
        cannotCancel = false,
        functionContext = context
      }
    )
    LrTasks.sleep(0)
    
    progress:setIndeterminate()
    
    -- Load GPS file
    progress:setCaption("Create CSV file")

    -- Open the file early in case it fails
    if (not dryrun) then
      file = io.open(filename, "w")
    end

    --
    -- Iterate over all selected photos...
    -- NOTE: iteration seems to iterate by current sort order, nothing to do with selection order.
    --
    count = 0
    for j, p in ipairs(photos) do

      local filename = p:getFormattedMetadata('fileName')
      progress:setCaption(string.format("Processing %d (%s)", count, filename))

      processphoto(p)

      if (progress:isCanceled()) then
	-- prefs.gpxstatus = "Canceled"
	return
      end

    end -- for ipairs photos

    if (not dryrun) then
      file:close()
    end

    local status = string.format("Wrote %d entries in %s", count, filename)
    prefs.writestatus = status
    
  end)

end

local function doitall()
  assert(0)
  -- these fork off async threads, which run in parallel, and never signal 
  if (prefs.gpxfile and NDHgps.trkptsstart == nil) then
    loadgpxfile(prefs.gpxfile)
  end
  if (prefs.capfile and NDHgps.capstart == nil) then
    loadcapfile(prefs.capfile)
  end
  if (prefs.inatfile and NDHiNat.inatstart == nil) then
    loadinatfile(prefs.inatfile)
  end
  if (not photogpsloaded) then
    extractphotogps()
  end
end

--
-- Set up parameters in setupdialog
--
local function setupdialog()

  prefs.gpxstatus = 'Not Loaded'
  prefs.capstatus = 'Not Loaded'
  prefs.inatstatus = 'Not Loaded'
  prefs.extractstatus = 'Not Loaded'
  prefs.writestatus = ''

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

    -- Load plugin preferences
    -- Create a bindable table.  Whenever a field in this table changes
    -- then notifications will be sent.
    -- local props = LrBinding.makePropertyTable( context )
    -- props.usegpx = false
    -- props.gpxfile = '/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/Split/YEAR/2024GPX.gpx'

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
        title = 'Load GPX file:',
	alignment = 'left',
      },

      -- f:checkbox {
      -- 	title = "Use GPX location and trackname",
      -- 	value = LrView.bind( "usegpx" ),
      -- },

      f:row {

	f:edit_field {
	  width = 600,
	  value = LrView.bind("gpxfile"), -- "/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/Split/YEAR/2024GPX.gpx",
	  -- enabled = LrView.bind( "usegpx" )
	},

	f:push_button {
	  title = "Browse",
	  action = function()
	    local files = LrDialogs.runOpenPanel{title = 'GPX File location',
						   allowsMultipleSelection = false,
						   canChooseDirectories = false,
						   initialDirectory = '/Users/neilhunt/DriveNeil/0 Personal Folders/Maps/Split/YEAR/2024GPX.gpx'
						  }
	    if (files) then
	      prefs.gpxfile = files[1]
	      -- prefs.usegpx = true
	    else
	      prefs.gpxfile = nil
	      -- prefs.usegpx = false
	    end
	  end
	},
      },

      f:row {

	f:push_button {
	  -- enabled = LrView.bind("usegpx"),
	  title = "Load GPX Data",
	  place_horizontal = 0,
	  action = function()
	    loadgpxfile(prefs.gpxfile)
	  end
	},

	f:static_text {
	  width = 700,
	  title = LrView.bind("gpxstatus"),
	},
      },

------

      f:separator { 
        width = 600,
	-- place_horizontal = 50,
      },

      f:static_text {
        title = 'Load Captions file:',
	alignment = 'left',
      },

      -- f:checkbox {
      -- 	title = "Use captions from CSV file",
      -- 	value = LrView.bind( "usecap" ),
      -- },

      f:row {

	f:edit_field {
	  width = 600,
	  value = LrView.bind("capfile"), -- "/Users/neilhunt/DriveNeil/0 Personal Folders/Lightroom/2024Captions.csv",
	  -- enabled = LrView.bind( "usecap" )
	},

	f:push_button {
	  title = "Browse",
	  action = function()
	    local files = LrDialogs.runOpenPanel{title = 'Caps file location',
						   allowsMultipleSelection = false,
						   canChooseDirectories = false,
						   initialDirectory = '/Users/neilhunt/DriveNeil/Lightroom/2024Captions.csv',
						  }
	    if (files) then
	      prefs.capfile = files[1]
	      -- prefs.usecap = true
	    else
	      prefs.capfile = nil
	      -- prefs.usecap = false
	    end
	  end
	},
      },

      f:row {

	f:push_button {
	  -- enabled = LrView.bind("usecap"),
	  title = "Load captions data",
	  place_horizontal = 0,
	  action = function()
	    loadcapfile(prefs.capfile)
	  end
	},

	f:static_text {
	  width = 700,
	  title = LrView.bind("capstatus"),
	},
      },

------

      f:separator { 
        width = 600,
	-- place_horizontal = 50,
      },

      f:static_text {
        title = 'Load iNat file:',
	alignment = 'left',
      },

      -- f:checkbox {
      -- 	title = "Use iNaturalist titles",
      -- 	value = LrView.bind( "useinat" ),
      -- },

      f:row {

	f:edit_field {
	  width = 600,
	  value = LrView.bind("inatfile"), -- "/Users/neilhunt/DriveNeil/0 Personal Folders/iNaturalist/20240429-observations-426945.csv",
	  enabled = LrView.bind( "usegpx" )
	},

	f:push_button {
	  title = "Browse",
	  action = function()
	    local files = LrDialogs.runOpenPanel{title = 'iNat File location',
						   allowsMultipleSelection = false,
						   canChooseDirectories = false,
						   initialDirectory = '/Users/neilhunt/DriveNeil/0 Personal Folders/iNaturalist/20240429-observations-426945.csv',
						  }
	    if (files) then
	      prefs.inatfile = files[1]
	      -- prefs.useinat = true
	    else
	      prefs.inatfile = nil
	      -- prefs.useinat = false
	    end
	  end
	},
      },

      f:row {

	f:push_button {
	  -- enabled = LrView.bind("useinat"),
	  title = "Load iNaturalist Data",
	  place_horizontal = 0,
	  action = function()
	    loadinatfile(prefs.inatfile)
	  end
	},

	f:static_text {
	  width = 700,
	  title = LrView.bind("inatstatus"),
	},
      },

-------

      f:separator { 
        width = 600,
	-- place_horizontal = 50,
      },

      f:static_text {
        title = 'Load GPS for nearest match:',
	alignment = 'left',
      },

      f:row {

	f:push_button {
	  title = "Extract Photo GPS",
	  place_horizontal = 0,
	  action = function()
	    extractphotogps()
	  end
	},

	f:static_text {
	  width = 700,
	  title = LrView.bind("extractstatus"),
	},
      },

-------

      f:separator { 
        width = 600,
	-- place_horizontal = 50,
      },

      f:static_text {
        title = 'Save to CSV file:',
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
	    local file = LrDialogs.runSavePanel {
	      title = 'CSV file location',
	      allowsMultipleSelection = false,
	      initialDirectory = '/Users/neilhunt/DriveNeil/0 Personal Folders/Lightroom/PhotosWithDatesAndCaptions.csv',
	      requiredFileType = 'csv',
	      canCreateDirectors = false,
	    }
	    if (file) then
	      prefs.csvfile = file
	    else
	      prefs.csvfile = nil;
	    end
	  end
	},
      },

      f:row {

	f:push_button {
	  -- enabled = LrView.bind("useinat"),
	  title = "Create CSV",
	  place_horizontal = 0,
	  action = function()
	    createCSV(prefs.csvfile)
	  end
	},

	f:static_text {
	  width = 700,
	  title = LrView.bind("writestatus"),
	},
      },

    }
    
    export = LrDialogs.presentModalDialog {
      title = "Create CSV with Metadata",
      actionVerb = "Do it all!",
      cancelVerb = "Dismiss",
      contents = c,
    }

  end)

  if (export == "ok") then
    -- doitall()
  end

end

-- Invoke setup dialog
LrTasks.startAsyncTask(setupdialog)



-- OLD Run main()
-- LrTasks.startAsyncTask(main)

