--
-- NDH GPS functions.
--

require 'NDHutils'

NDHgps = {}

NDHgps.trkptbuckets = {} -- Array by buckets of time of sets of { time, lat, lon, ele }
NDHgps.trkbuckets = {} -- Array by buckets of time of tracks.  Each track appears in each bucket it spans.
NDHgps.count = 0
NDHgps.counttrks = 0
NDHgps.countduptrks = 0
NDHgps.counttrkpts = 0
NDHgps.countduptrkpts = 0
NDHgps.trkptsstart = nil
NDHgps.trkptsend = nil
NDHgps.adjctptsstart = nil
NDHgps.adjctptsend = nil

local trkptbucketsize = 60 -- 60 seconds +/-30 around each minute mark.
local trkbucketsize = 3600*24 -- day-size buckets -- about 1-2 trks per bucket; trks spanning day ends will appear in two


-- Function to calculate distance (m) between two coords lat/lon
-- lat m/deg = 111132.92 + -559.82*cos(2*lat*pi()/180)+1.175*cos(4*lat*pi()/180)+-0.0023*cos(6*lat*pi()/180)
-- lon m/deg = 111412.84 * cos(lat*pi()/180)+-93.5*cos(3*lat*pi()/180)+0.118*cos(5*lat*pi()/180)

function NDHgps.gpsdiff (lat1, lon1, lat2, lon2)
  if (lat1 == nil or lat2 == nil or lon1 == nil or lon2 == nil) then
    return 999999999
  end
  local lat = (lat1 + lat2) / 2.0
  local latmdeg = 111132.92 - 559.82*math.cos(2*lat*math.pi/180.0) + 1.175*math.cos(4*lat*math.pi/180.0) - 0.0023*math.cos(6*lat*math.pi/180)
  local lonmdeg = 111412.84 * math.cos(lat*math.pi/180.0) - 93.5*math.cos(3*lat*math.pi/180.0) + 0.118*math.cos(5*lat*math.pi/180.0)
  local delta_lat = (lat1 - lat2)*latmdeg
  local delta_lon = (lon1 - lon2)*lonmdeg
  local sumsq = math.pow(delta_lat,2) + math.pow(delta_lon,2)
  local dist = math.sqrt(sumsq)
  -- debugmessage("NDHGPS", string.format("gpsdiff([%f, %f], [%f, %f] / lat=%f delta_lat=%fm delta_lon=%fm sumsq=%f (latmdeg=%f lonmdeg=%f) --> %f",
  --                                                lat1, lon1, lat2, lon2, lat,  delta_lat,   delta_lon,   sumsq,    latmdeg,  lonmdeg,       dist))
  return dist
end

local debug_histogram_time = { } -- array of counts by log10(x10)
local debug_histogram_dist = { } -- array of counts by log10(x10)
local debug_histogram_total_time = 0
local debug_histogram_total_dist = 0
local debug_histogram_time_max = 0
local debug_histogram_dist_max = 0

verbose_flags["GPS State Machine Top"] = false
verbose_flags["GPS State Machine Top.trk"] = false
verbose_flags["GPS State Machine Top.trk.trkseg"] = false
verbose_flags["GPS State Machine Top.trk.trkseg.trkpt"] = false
verbose_flags["Trkpt"] = false
verbose_flags["Hist time"] = false
verbose_flags["Hist time +"] = false
verbose_flags["Hist dist"] = false
verbose_flags["Hist dist +"] = false
verbose_flags["GPX Sample"] = false
verbose_flags["Test Samples"] = false
verbose_flags["Trk buckets"] = false
verbose_flags["insert skip trkpt dups"] = false

function NDHgps.parseGPX (gpxxml)

  -- local attributestop = gpxxml:attributes()
  local n = gpxxml:childCount()
  
  -- Top: looking for <trk>
  for i = 1,n do
    -- NDHgps.parseGPXnode(gpxxml, i, n)
  end
  
end

verbose_flags['Strava time overrides'] = false
verbose_flags['skip trk'] = false
verbose_flags['trkptmatch1'] = false

function NDHgps.parseGPXnode (gpxxml, i, n)

  local topchild = gpxxml:childAtIndex(i)
  local name = topchild:name()
  local text = topchild:text()
  debugmessage("NDHgps", string.format("Top getting child %d of %d (%s)\ntext:%s", i, n, name, string.sub(text, 1, 100)), "GPS State Machine Top")
  if (name == "trk") then
    -- Top.trk: looking for <!-- > | <name> | <desc> | <type> | <extensions> | <trkseg>
    local trkname, trk_t
    local last_t
    local last_lat, last_lon
    local overridestartdate
    local overrideenddate
    local n = topchild:childCount()
    for i = 1,n do
      local trkchild = topchild:childAtIndex(i)
      local name = trkchild:name()
      local text = trkchild:text()
      debugmessage("NDHgps", string.format("Trk getting trkchild %d of %d (%s)\ntext:%s", i, n, name, string.sub(text, 1, 100)), "GPS State Machine Top.trk")
      if (name == nil) then
	-- source="../Legacy GPX/2003 NDH.gpx"
	-- StravaActivity="10475981090"
    	-- StravaFilename="activities/11210686127.fit.gz"
    	-- StravaStartDate="1704135463" (2024-01-01T18:57:43Z)
    	-- StravaEndDate="1704143013" (2024-01-01T21:03:33Z)
	local d, s
	d, s = string.match(text, "StravaStartDate=\"(%d*)\" %((.*)%)")
	if (d ~= nil) then
	  debugmessage("NDHgps", string.format("Trk found start overrides %d %d %s", timefromisostring(s), d, s), "Strava time overrides")
	  overridestartdate = timefromisostring(s)
	end
	d, s = string.match(text, "StravaEndDate=\"(%d*)\" %((.*)%)")
	if (d ~= nil and s ~= nil) then
	  overrideenddate = timefromisostring(s)
	  debugmessage("NDHgps", string.format("Trk found end overrides %d %s", d, s), "Strava time overrides")
	end
      elseif (name == "name") then
	trkname = text
      elseif (name == "desc") then
      elseif (name == "type") then
      elseif (name == "number") then
      elseif (name == "extensions") then
      elseif (name == "trkseg") then
	-- Top.trk.trkseg: looking for <trkpt ..> | <!-- >
	local n = trkchild:childCount()
	for i = 1,n do
	  local trksegchild = trkchild:childAtIndex(i)
	  local name = trksegchild:name()
	  local text = trksegchild:text()
	  debugmessage("NDHgps", string.format("Trk.trkseg getting trksegchild %d of %d (%s)\ntext:%s", i, n, name, string.sub(text, 1, 100)), "GPS State Machine Top.trk.trkseg")
	  if (name == "trkpt") then
	    NDHgps.counttrkpts = NDHgps.counttrkpts + 1
	    local trkpt = trksegchild
	    local attributes = trkpt:attributes()
	    local lat = attributes['lat']['value']
	    local lon = attributes['lon']['value']
	    local time, t, o, ele
	    local n = trkpt:childCount()
	    for i = 1,n do
	      local trkptchild = trkpt:childAtIndex(i)
	      local name = trkptchild:name()
	      local text = trkptchild:text()
	      debugmessage("NDHgps", string.format("Trk.trkseg.trkpt getting child %d of %d (%s)\n%s", i, n, name, string.sub(text, 1, 100)), "GPS State Machine Top.trk.trkseg.trkpt")
	      if (name == "time") then
		time = text
		t, o = timefromisostring(time)
		if (trk_t == nil) then
		  trk_t = t;
		end
		assert(t ~= nil, "t is nil");
		assert(((o == nil) or (o == 0)), string.format("NDHgps: GPStimestamp %s (%d %d) appears to carry a timezone", time, t, o or -1))
	      elseif (name == "ele") then
		ele = text
	      elseif (name == nil) then
		-- interval="60"
		-- dateimeguess="2003-01-04-22:00:00Z"
		-- datetimesynthesized
		local interval = string.match(text, "interval=\"(.*)\"")
		local datetimeguess = string.match(text, "datetimeguess=\"(.*)\"")
		local datetimesynthesized = string.match(text, "datetimesynth")
		-- debugmessage("NDHgps", string.format("NDHgps: comment %d %s", i, string.sub(text, 1, 100)), "Trkpt")
		if (interval ~= nil) then
		elseif (datetimeguess ~= nil) then
		elseif (datetimesynthesized) then
		else
		  debugmessage("NDHgps", string.format("NDHgps: unrecognized comment %d %s", i, string.sub(text, 1, 100)), "Trkpt")
		end
	      else
		debugmessage("NDHgps", string.format("NDHgps: other %d %s", i, string.sub(text, 1, 100)), "Trkpt")
	      end
	    end
	    assert(t ~= nil, string.format("Missing t %f %f", lat, lon))

	    if (verbose_flags["Hist time"]) then
	      -- DEBUG HISTOGRAM of time delta distribution
	      if (last_t ~= nil) then
		local delta = (t - last_t) or 1
		local bucket = math.floor(math.log10(delta)*10)
		debug_histogram_time_max = math.max(debug_histogram_time_max, bucket)
		debug_histogram_total_time = debug_histogram_total_time + 1
		if (debug_histogram_time[bucket] == nil) then
		  debug_histogram_time[bucket] = 1
		else
		  debug_histogram_time[bucket] = debug_histogram_time[bucket] + 1
		  if (delta > 1000) then
		    debugmessage("NDHGPS", string.format("%s: delta %d: %d (%s) [%f %f]", trkname, delta, t, time, lat, lon), "Hist time +")
		  end
		end
		debugmessage("NDHGPS", string.format("%s: delta %d: (%d of %d) t %d (%s) [%f %f]", trkname, delta, bucket, debug_histogram_time_max, t, time, lat, lon), "Hist time +")
	      end
	    end

	    if (verbose_flags["Hist dist"]) then
	      -- DEBUG HISTOGRAM of distance delta distribution
	      if (last_lat ~= nil and last_lon ~= nil) then
		local delta = NDHgps.gpsdiff(lat, lon, last_lat, last_lon)
		local bucket = math.floor(math.log10(delta)*10)
		debug_histogram_dist_max = math.max(debug_histogram_dist_max, bucket)
		debug_histogram_total_dist = debug_histogram_total_dist + delta
		if (debug_histogram_dist[bucket] == nil) then
		  debug_histogram_dist[bucket] = 1
		else
		  debug_histogram_dist[bucket] = debug_histogram_dist[bucket] + 1
		  if (delta > 10000) then
		    debugmessage("NDHGPS", string.format("%s: delta %d: %d (%s) [%f %f]", trkname, delta, t, time, lat, lon), "Hist dist +")
		  end
		end
		debugmessage("NDHGPS", string.format("%s: delta %dm: (%d of %d) [%f %f]", trkname, delta, bucket, debug_histogram_dist_max, lat, lon), "Hist dist +")
	      end
	    end
	    last_t = t
	    last_lat = lat
	    last_lon = lon

	    NDHgps.savetrkpt(t, lat, lon, ele, "Strava")

	  end -- <trkpt>

	end -- iteration over trkseg

      else
	debugmessage("NDHgps", string.format("%s: trk child %d of %d --> UNKNWON %s %s", debug, i, n, name, string.sub(text, 1, 100)))
      end  -- <trkseg>

    end -- iteration over <trk>

    -- Store trk in trkbuckets
    if (trk_t ~= nil) then
      if (overridestartdate) then
        debugmessage("NDHgps", string.format("Cropping start %d -> %d (%d)", trk_t, overridestartdate, overridestartdate-trk_t), "Strava time overrides")
        trk_t = overridestartdate
      end
      if (overrideenddate) then
        debugmessage("NDHgps", string.format("Cropping end %d -> %d (%d)", last_t, overrideenddate, last_t-overrideenddate), "Strava time overrides")
        last_t = overrideenddate
      end
      if (trkname ~= nil) then
        NDHgps.savetrk(trk_t, last_t, trkname)
      end
    else
      debugmessage("NDHgpx", string.format("Trk %s NOT added  from %d to %d\n", trkname, (trk_t or 0), (last_t or 0)), "Trk buckets")
    end

  end -- <trk>
  
end

function NDHgps.savetrkpt(t, lat, lon, ele, source)
  -- Store trkpt in trkptbuckets
  local trkptbucket = math.floor((t+trkptbucketsize/2)/trkptbucketsize)
  -- -- Trackpoints are stored in each bucket they could be nearest.
  -- --   13:45 .. 14:45 --> 14
  -- local lowerbucket = math.floor((t+trkptbucketsize/2)/trkptbucketsize)
  -- local upperbucket = math.floor((t+trkptbucketsize/2)/trkptbucketsize)
  if (NDHgps.trkptbuckets[trkptbucket] == nil) then
    NDHgps.trkptbuckets[trkptbucket] = { }
  end
  for i, trkpt in ipairs(NDHgps.trkptbuckets[trkptbucket]) do
    if (trkpt['t'] == t and trkpt['lat'] == lat and trkpt['lon'] == lon and trkpt['ele'] == ele) then
      debugmessage("NDHgpx", string.format("Duplicate trkpt at %s: (%f, %f, %s)", t, lat, lon, ele), "insert skip trkpt dups")
      NDHgps.countduptrkpts = NDHgps.countduptrkpts + 1
      return
    end
  end
  table.insert(NDHgps.trkptbuckets[trkptbucket], { t=t, lat=lat, lon=lon, ele=ele, source=source })
  -- Record count and max min times
  NDHgps.counttrkpts = NDHgps.counttrkpts + 1
  if (source == "Strava") then
    if (NDHgps.trkptsstart == nil or (t < NDHgps.trkptsstart)) then
      NDHgps.trkptsstart = t
    end
    if (NDHgps.trkptsend == nil or (t > NDHgps.trkptsend)) then
      NDHgps.trkptsend = t
    end
  elseif (source == "AdjacentPhoto") then
    if (NDHgps.adjctptsstart == nil or (t < NDHgps.adjctptsstart)) then
      NDHgps.adjctptsstart = t
    end
    if (NDHgps.adjctptsend == nil or (t > NDHgps.adjctptsend)) then
      NDHgps.adjctptsend = t
    end
  else
    debugmessage("NDHgpx", string.format("Unknown source %s", source), "warning")
  end

end

function NDHgps.savetrk(trk_t, last_t, trkname)
  if (trkname == nil or trkname == "") then
    debugmessage("NDHgpx", string.format("Unnamed trk at [%d..%d]", trk_t, last_t), "skip trk")
    return
  end
  local n = 0
  for bucket = math.floor(trk_t/trkbucketsize)*trkbucketsize, math.ceil(last_t/trkbucketsize)*trkbucketsize, trkbucketsize do
    if (NDHgps.trkbuckets[bucket] == nil) then
      NDHgps.trkbuckets[bucket] = { }
    end
    for i, trk in ipairs(NDHgps.trkbuckets[bucket]) do
      if (trk['trk_t'] == trk_t and trk['last_t'] == last_t and trk['trkname'] == trkname) then
        debugmessage("NDHgpx", string.format("Duplicate trk at [%d..%d] %s", trk_t, last_t, trkname), "insert skip trk dups")
        NDHgps.countduptrks = NDHgps.countduptrks + 1
        return
      end
    end
    table.insert(NDHgps.trkbuckets[bucket], { trk_t=trk_t, last_t=last_t, trkname=trkname })
    n = n + 1
  end
  debugmessage("NDHgpx", string.format("Trk %s added to %d buckets from %d to %d\n", trkname, n, trk_t, last_t), "Trk buckets")
  NDHgps.counttrks = NDHgps.counttrks + 1
end

--
-- lastt,t  10  20  30
-- ts      1
-- ts       10
-- ts           20
-- ts             22
-- ts               30
-- ts                   35

-- 1672597243 --> [38.4685120, -120.0447540] @2233.0
-- 1672630009 --> [38.4602730, -120.0403500] @2196.4
-- 1672597246 --> [38.4684930, -120.0447110] @2232.8
-- 1672631034 --> [38.4604600, -120.0337550] @2198.0
-- ...
-- 1673162508 --> [37.3635080, -122.0809080] @20.2

local testtimes = { 123, 1672597240, 1672597243, 1672597246, 1672630000, 1672630009, 1672630011, 1673162500, 1673162508, 1673162522, 1673262508 }


function NDHgps.getnearesttrkpt (ts, range, exclude)
  for b = 0,math.ceil(range/trkptbucketsize) do
    for bb = -b, b, math.max(2*b, 1) do
      local bucket = math.floor((ts+trkptbucketsize/2)/trkptbucketsize)+bb
      local nearby = NDHgps.trkptbuckets[bucket]
      local nearesttrkpt, nearestdelta
      if (nearby ~= nil) then
	for i, trkpt in ipairs(nearby) do
	  if ((exclude == nil) or (trkpt['source'] ~= "AdjacentPhoto")) then
	    local t = trkpt['t']
	    local delta = math.abs(ts - t)
	    local better = false
	    local debug = ""
	    if (delta <= range) then
	      debug = "in range"
	      if (nearesttrkpt == nil) then
		debug = stringbuild(debug, "first match", ", ")
		better = true
	      else
		debug = stringbuild(debug, string.format("comp new %d %s vs prev %d %s %d <? %d", trkpt['t'], trkpt['source'],
											 nearesttrkpt['t'], nearesttrkpt['source'],
											 delta, nearestdelta), ", ")
		if ((trkpt['source'] == "Strava") and (nearesttrkpt['source'] == "AdjacentPhoto")) then
		  debug = stringbuild(debug, "Strava match is better than Adjacent", ", ")
		  better = true
		end
		if ((trkpt['source'] == "Strava") and (delta < nearestdelta)) then
		  debug = stringbuild(debug, "Strava match is nearer", ", ")
		  better = true
		end
		if ((trkpt['source'] == "AdjacentPhoto") and (nearesttrkpt['source'] == "AdjacentPhoto") and (delta < nearestdelta)) then
		  debug = stringbuild(debug, "A closer AdjacentPhoto", ", ")
		  better = true
		end
	      end
	      debugmessage("NDHgps", string.format("getnearesttrkpt %d %s (%s)", ts, debug, better), "trkptmatch1")
	      if (better) then
		nearestdelta = delta
		nearesttrkpt = trkpt
	      end
	    end
	  end
	end
	if (nearesttrkpt ~= nil) then
	  return nearesttrkpt, bb
	end
      end
    end
  end
  return nearesttrkpt, 99
end

function NDHgps.getbesttrk (ts, range)
  local bucket = math.floor(ts/trkbucketsize)*trkbucketsize
  local trks = NDHgps.trkbuckets[bucket]
  if (trks == nil) then
    return nil
  end
  local besttrk = nil
  for i, trk in ipairs(trks) do
    if (ts >= (trk['trk_t'] - range) and ts <= (trk['last_t'] + range)) then
      -- ts is within this trk...
      if (besttrk == nil) then
        besttrk = trk
      elseif (trk['trk_t'] >= besttrk['trk_t']) then
        -- this trk is newer than the previoulsy noted besttrk, grab it.
        besttrk = trk
      end
    end
  end
  return besttrk
end

verbose_flags["GPX Tracks"] = false

function NDHgps.trkdebug ()

  if (verbose_flags["GPX Sample"]) then
    local count = 0
    local dbg = ""
    for b, trkpts in pairs(NDHgps.trkptbuckets) do
      dbg = dbg .. string.format("Bucket %s:\n", b)
      for i, trkpt in ipairs(trkpts) do
	count = count+1
	dbg = dbg .. string.format("  %d %s %f %f %f\n", trkpt['t'], stringfromtime(trkpt['t']), trkpt['lat'], trkpt['lon'], trkpt['ele'] or 0)
      end
      if (count > 20) then
	dbg = dbg .. "...\n"
	break
      end
    end
    debugmessage("NDHGPS", dbg, "GPX Sample")
  end

  if (verbose_flags["GPX Tracks"]) then
    local count = 0
    local dbg = ""
    for b, trks in pairs(NDHgps.trkbuckets) do
      dbg = dbg .. string.format("Bucket %s:\n", b)
      for i, trk in ipairs(trks) do
	count = count + 1
	dbg = dbg .. string.format("  %d: %s %s: %s\n", b, stringfromtime(trk['trk_t']), stringfromtime(trk['last_t']), trk['trkname'] or "NIL")
      end
      if (count > 20) then
	dbg = dbg .. " ...\n"
	break
      end
    end
    debugmessage("NDHGPS", dbg, "GPX Tracks")
  end

  -- PRINT HISTOGRAMS
  if (verbose_flags["Hist time"]) then
    local recount = 0
    local dbg = string.format("Histogram: %d %d\n", debug_histogram_total_time, debug_histogram_time_max)
    for t = 0, debug_histogram_time_max do
      local buckettime = math.ceil(math.pow(10,t/10))
      if (buckettime < 100) then
        dbg = dbg .. string.format("%3f:\t%d\n", buckettime, debug_histogram_time[t] or 0)
      end
      recount = recount + (debug_histogram_time[t] or 0)
    end
    dbg = dbg .. string.format("Recount = %d\n", recount)
    debugmessage("NDHGPS", dbg, "Hist time")
  end

  if (verbose_flags["Hist dist"]) then
    local recount = 0
    local dbg = string.format("Histogram: %d %d\n", debug_histogram_total_dist, debug_histogram_dist_max)
    for t = 0, debug_histogram_dist_max do
      local bucketdist = math.ceil(math.pow(10,t/10))
      if (bucketdist < 100) then
        dbg = dbg .. string.format("%3f:\t%d\n", bucketdist, debug_histogram_dist[t] or 0)
      end
      recount = recount + (debug_histogram_dist[t] or 0) * bucketdist
    end
    dbg = dbg .. string.format("Recount = %d\n", recount)
    debugmessage("NDHGPS", dbg, "Hist dist")
  end

  if (verbose_flags["Test Samples"] == nil or verbose_flags["Test Samples"]) then
    for i, t in ipairs(testtimes) do
      local trkpt, dbg = NDHgps.getnearesttrkpt(t, 600)
      if (trkpt ~= nil) then
	local time = trkpt['t']
	local tstring = stringfromtime(time)
	local lat = trkpt['lat']
	local lon = trkpt['lon']
	local ele = trkpt['ele']
	if (not debugmessage("NDHGPS", string.format("%d: %d (%s) (pass %s) (%f, %f, %f)",
						      t, time, tstring, dbg, lat, lon, ele), "Test Samples")) then
	  return
	end
      else
	if (not debugmessage("NDHGPS", string.format("%d: no match", t), "Test Samples")) then
	  return
	end
      end
    end
  end
end

NDHgps.fieldnames = nil
NDHgps.capstart = nil
NDHgps.capend = nil
NDHgps.capcount = 0
NDHgps.capbuckets = { }  -- Array by buckets of time of tracks.  Each caption appears in each bucket it spans.
local capbucketsize = 3600*24 -- Day

verbose_flags["cap line"] = false
verbose_flags["null caption"] = false
verbose_flags["buckets"] = false
verbose_flags["cap table new"] = false
verbose_flags["cap table dup"] = false
verbose_flags["debug add"] = false

local function checkemptybuckets(s)
  for b, caps in pairs(NDHgps.capbuckets) do
    local count = 0
    for i, bucket in ipairs(caps) do
      count = count + 1
    end
  end
  if (count == 0) then
    debugmessage("NDHgps", string.format("Empty cap bucket at %d\n%s", b, s), "empty buckets")
  end
end

function NDHgps.loadcapfile(filename)

  -- Load captions file
  local line
  local countlines = 0
  local countdups = 0
  -- debugmessage("NDHgps", string.format("Loading captions %s", filename), "Debug loadcapfile")
  for line in io.lines(filename) do
    countlines = countlines + 1
    line = line:gsub("%c$", "") -- chomp
    local split = csvsplit(line)
    if (NDHgps.fieldnames == nil) then
      NDHgps.fieldnames = split
    elseif (split[1] ~= NDHgps.fieldnames[1]) then -- skip duplicate title lines (split[1] == "ID")
      local captionrecord = split
      local captionrecordtable = { }
      for i, f in ipairs(NDHgps.fieldnames) do
	captionrecordtable[f] = split[i]
	debugmessage("NDHgps", string.format("%d: Adding %s->%s %s %d", countlines, f, captionrecord[i], split[i], i), "debug add")
      end
      debugmessage("NDHgps", string.format("Process %s %s\n%s..%s %s..%s %s", countlines, line, captionrecord['Activity Name'], captionrecord['Activity Start Local'], captionrecord['Activity End Local'], captionrecordtable['Activity Start UTC'], captionrecordtable['Activity End UTC']), "cap line")

      if (captionrecordtable['Activity Name'] == nil or captionrecordtable['Activity Name'] == "") then
        debugmessage("NDHgps", string.format("Skipping unnamed caption record %s", format_table(captionrecordtable, true)), "null caption")
      else
      
	-- Activity Start UTC or Activity Start Local (if no time, then assume 00:00 for the whole day) 
	-- Activity End UTC or Activity End Local (if no time, then assume 23:59:59 for the whole day) [Could be missing to speficy duration to end of day]
	-- Activity Name
	-- Each caption record goes in every hour-long bucket within its time range, BOTH in localtime and UTC (same buckets)
	-- Look in the two buckets - each photo's localtime and UTC time.
	for l = 0, 1 do  -- Local, UTC
	  local activitystartstring
	  local activityendstring
	  if (l == 0) then
	    activitystartstring = captionrecordtable['Activity Start Local']
	    activityendstring = captionrecordtable['Activity End Local']
	  else
	    activitystartstring = captionrecordtable['Activity Start UTC']
	    activityendstring = captionrecordtable['Activity End UTC']
	  end
	  if (activitystartstring ~= nil and activitystartstring ~= "") then
	    local activitystart = timefromstring(activitystartstring, "00:00:00") -- default time start of day
	    if (activityendstring == nil or activityendstring == "") then
	      activityendstring = string.match(activitystartstring, "(%d+/%d+/%d+)")
	    end
	    activityend = timefromstring(activityendstring, "23:59:59") -- default end of day

	    -- Add start/end time_t to the record.
	    if (l == 0) then
	      captionrecordtable['Start Local'] = activitystart
	      captionrecordtable['End Local'] = activityend 
	    else
	      captionrecordtable['Start UTC'] = activitystart 
	      captionrecordtable['End UTC'] = activityend
	    end
	    
	    if (NDHgps.capstart == nil or activitystart < NDHgps.capstart) then
	      NDHgps.capstart = activitystart
	    end
	    if (NDHgps.capend == nil or NDHgps.capend < activityend) then
	      NDHgps.capend = activityend
	    end
	    local debug = string.format("Add Activity (l=%d): %s %s-%s", l, captionrecordtable['Activity Name'],
						              stringfromtime(activitystart),
							            stringfromtime(activityend))

	    local activitystartbucket = math.floor(activitystart / capbucketsize) * capbucketsize
	    local activityendbucket = math.floor(activityend / capbucketsize) * capbucketsize
	    debug = debug .. string.format(" buckets %s-%s", stringfromtime(activitystartbucket), stringfromtime(activityendbucket))
	    for bucket = activitystartbucket, activityendbucket, capbucketsize do
	      if (NDHgps.capbuckets[bucket] == nil) then
		NDHgps.capbuckets[bucket] = { }
	      end
	      for i, p in ipairs(NDHgps.capbuckets[bucket]) do
		if ((p['Activity Name'] == captionrecordtable['Activity Name']) and
		    ((p['Start UTC'] == activitystart and p['End UTC'] == activityend) or
		     (p['Start Local'] == activitystart and p['End Local'] == activityend))) then
		  debug = debug .. string.format("Dup record %d.%d %s", bucket, i, activitystart)
		  countdups = countdups + 1
		  table.remove(NDHgps.capbuckets[bucket], i)
		  debug = debug .. string.format("New record %s %d", debug, activitystart)
		end
	      end
	      debug = debug .. string.format(" + %d", bucket)
	      table.insert(NDHgps.capbuckets[bucket], captionrecordtable)
	      assert(captionrecordtable['Activity Name'])
	    end
	    debugmessage("NDHgps", debug, "buckets")
	  end
	end
      end
    end
  end
  local capstartstring = stringfromtime(NDHgps.capstart or 0)
  local capendstring = stringfromtime(NDHgps.capend or 0)

  return string.format("%d lines (%d dups) from %s to %s", countlines, countdups, capstartstring, capendstring)
  
end

verbose_flags["capmatch"] = false
verbose_flags["capmatch2"] = false

function NDHgps.capmatch(timelocal, timeutc, path)

  debugmessage("NDHgps", string.format("Capmatch %s\ntimelocal %d (%s) timeutc %d (%s)",
                                                 path,
						               timelocal,
							           stringfromtime(timelocal),
								               timeutc,
									            stringfromtime(timeutc)),
		"capmatch")
		
  for l = 0, 1 do -- Local, UTC
    local t
    local best = nil
    if (l == 0) then
      t = timelocal
    else
      t = timeutc
    end
    local bucket = math.floor(t / capbucketsize) * capbucketsize
    local debug = string.format("Looking up l=%d time %d %d (%s)\n",
     	  	  			      l,      bucket,
						         t,  stringfromtime(t))
    if (NDHgps.capbuckets[bucket] == nil) then
      debug = debug .. "No buckets"
    else
      debug = debug .. "Buckets:\n "
      local beststart
      local bestend
      local beststartdelta
      local bestenddelta
      for i, p in ipairs(NDHgps.capbuckets[bucket]) do
	local activitystart
	local activityend
	debug = debug .. string.format("Bucket[%d]: ", i)
	if (p['Exclude'] ~= nil and p['Exclude'] ~= "" and string.match(path, p['Exclude'])) then
	  debug = debug .. "Excluded by pattern\n"
	else
	  if (l == 0) then
	    activitystart = p['Start Local']
	    activityend = p['End Local']
	  else
	    activitystart = p['Start UTC']
	    activityend = p['End UTC']
	  end
	  if (activitystart ~= nil and activityend ~= nil) then
	    debug = debug .. string.format("Considering %d .. %d vs %d (%s .. %s vs %s): ",
						        activitystart,
							      activityend,
								    t,
									stringfromtime(activitystart),
									      stringfromtime(activityend),
										    stringfromtime(t))
	    if (activitystart <= t and t <= activityend) then
	      if (best == nil) then
		best = p
		beststart = activitystart
		bestend = activityend
		bestenddelta = activityend - t
		beststartdelta = t - activitystart
		debug = debug .. "first"
	      else
		-- Best is the one that ends soonest, or if the same, starts latest
		if ((activityend - t < bestenddelta) or ((activityend - t == bestenddelta) and (t - activitystart < beststartdelta))) then
		  best = p
		  beststart = activitystart
		  bestend = activityend
		  bestenddelta = activityend - t
		  beststartdelta = t - activitystart
		  debug = debug .. "better\n"
		else
		  debug = debug .. "not better\n"
		end
	      end
	    else
	      debug = debug .. "no span\n"
	    end -- if activity time spans t
	    debug = debug .. p['Activity Name'] .. "\n"
	  end -- if activitystart and activityend
	end -- if ! exclude
      end -- for buckets
    end -- if buckets
    debug = debug .. "\nbest=" .. ((best and best['Activity Name']) or "NIL")
    debugmessage("NDHgps", debug, "capmatch2")
    if (best ~= nil) then
      return best
    end
  end -- for l = 0, 1
  return nil
end

verbose_flags['capdebug'] = false

function NDHgps.capdebug()
  if (verbose_flags['capdebug']
    -- and NDHgps.capstart ~= nil
    ) then
    local startbucket = math.floor(NDHgps.capstart / capbucketsize) * capbucketsize
    local endbucket = math.floor(NDHgps.capend / capbucketsize) * capbucketsize
    local count = 0
    local debug = string.format("Debug captions %d, %d, %d\n", startbucket, endbucket, capbucketsize)
    for b, caps in pairs(NDHgps.capbuckets) do
      debug = debug .. string.format("Bucket %d (%s):\n", b, stringfromtime(b))
      if (count > 20) then
        debug = debug .. " ...\n"
	break
      end
      for i, p in ipairs(caps) do
	count = count + 1
	debug = debug .. string.format("  %d %s .. %s (%s .. %s): %s\n", b,
	      (p['Activity Start Local']) or "",
	      (p['Activity End Local'] or ""),
	      (p['Activity Start UTC']) or "",
	      (p['Activity End UTC'] or ""),
	      (p['Activity Name'] or ""))
      end
    end
    debugmessage("NDHgps", debug, "capdebug")
  end
end




--[[
2010.gps:
Histogram: 35646
1:	1621
2:	1696
3:	1931
4:	7611
6:	5052n
7:	5239
8:	7106
10:	3164
13:	517
16:	365
20:	398
26:	184
32:	166
40:	137
51:	110
64:	88
80:	62
100:	52
126:	39
159:	24
200:	24
252:	16
317:	7
399:	6
502:	5
631:	6
795:	5
1000:	2
1259:	2
1585:	2
1996:	2
2512:	1
3163:	0
3982:	1
5012:	0
6310:	2
7944:	0
10000:	0
12590:	1
15849:	2
19953:	0
Recount = 35646
-- About a dozen breaks longer than 1000 seconds which appear to be pause/resume.  Can be a long distance between

2023.gps
Histogram: 341889
1:	142849
2:	54244
3:	37743
4:	50277
6:	16454
7:	12868
8:	15024
10:	6180
13:	1862
16:	1371
20:	1157
26:	680
32:	480
40:	301
51:	177
64:	95
80:	55
100:	41
126:	14
159:	9
200:	4
252:	1
317:	1
399:	0
502:	2
631:	0
795:	0
1000:	0
Recount = 341889
-- No breaks over 1000 seconds.

2010.gps DISTANCE (m)
Histogram: 1,082,204
1.000000:	395
2.000000:	508
2.000000:	607
2.000000:	735
3.000000:	911
4.000000:	1153
4.000000:	1478
6.000000:	1852
7.000000:	2164
8.000000:	2563
10.000000:	2972
13.000000:	3277
16.000000:	3024
20.000000:	2852
26.000000:	2653
32.000000:	2333
40.000000:	2150
51.000000:	1595
64.000000:	755
80.000000:	269
100.000000:	55
126.000000:	11
159.000000:	3
200.000000:	2
252.000000:	0
317.000000:	0
399.000000:	0
502.000000:	1
631.000000:	0
795.000000:	0
1000.000000:	0
1259.000000:	1
1585.000000:	1
Recount = 633,789

2023.gpx
Histogram: 1,525,151
1.000000:	23295
2.000000:	27352
2.000000:	28876
2.000000:	24804
3.000000:	23122
4.000000:	24111
4.000000:	22479
6.000000:	20470
7.000000:	18041
8.000000:	16077
10.000000:	14443
13.000000:	9989
16.000000:	5230
20.000000:	3345
26.000000:	1608
32.000000:	1094
40.000000:	755
51.000000:	1443
64.000000:	94
80.000000:	25
100.000000:	16
126.000000:	5
159.000000:	6
200.000000:	4
252.000000:	2
317.000000:	2
399.000000:	1
502.000000:	1
Recount = 1438323

--]]