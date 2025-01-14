--
-- NDH iNat Matching functions.
--

local LrDialogs = import 'LrDialogs'

require 'NDHutils'

NDHiNat = {}
NDHiNat.buckets = {} -- Array by buckets of time of photorecordtables
NDHiNat.count = 0
NDHiNat.fieldnames = nil
NDHiNat.inatstart = nil
NDHiNat.inatend = nil


-- Match photos within +/- 600 seconds of the observation.
-- Each record goes in all buckets within +/-600.

-- 600 seconds: bucket = floor(t/600)*600
-- -60..+300:   will place record at t-60 +i*bucketsize to t+300
local inatbucketsize = 3600 -- 600
local inatmatchrangebefore = 300 -- HERE was 60
local inatmatchrangeafter = 300
local inatmatchrangebeforenamed = 3600*24 -- allow for wrong timezone.  -- 3600+120 -- 3600 is a hack to manage DST changes fixed after the iNat export.
local inatmatchrangeafternamed = 3600*24 -- allow for wrong timezone.  -- 3600+900

verbose_flags["debug iNat table add"] = false
verbose_flags["debug iNat table dup"] = false
verbose_flags["debug add"] = false
verbose_flags["debug lines"] = false
verbose_flags["inatmatch0"] = false
verbose_flags["inatmatch1"] = false
verbose_flags["inatmatch2"] = false
verbose_flags["inatmatch3"] = false
verbose_flags["inatmatch4"] = false
verbose_flags["inatmatch5"] = false
verbose_flags["inatmatch6"] = false


function NDHiNat.loadinatfile(filename)

  -- Load iNaturalist File
  local line
  local countlines = 0
  local countdups = 0
  -- debugmessage("NDHiNat", string.format("Loading inat %s", filename), "Debug loadinatfile")
  for line in io.lines(filename) do
    if (countlines % 100 == 0) then
      debugmessage("NDHiNat", string.format("Line %d: %s", countlines, line), "debug lines")
    end
    countlines = countlines + 1
    line = line:gsub("%c$", "") -- chomp
    local split = csvsplit(line)
    if (NDHiNat.fieldnames == nil) then
      NDHiNat.fieldnames = split
    elseif (split[1] == NDHiNat.fieldnames[1]) then -- Skip duplicate title lines (split[1] == "ID") and reload the keys
      NDHiNat.fieldnames = split
    else
      local photorecord = split
      local photorecordtable = { }
      for i, f in ipairs(NDHiNat.fieldnames) do
	photorecordtable[f] = split[i]
      end
      local dbg = string.format("Photorecordtable %s =", photorecordtable);
      for f, v in pairs(photorecordtable) do
        dbg = stringbuild(dbg, string.format("%s=\"%s, ", f, v), "\n")
      end
      debugmessage("NDHiNat", dbg, "debug add")
      local timeobservedstring = photorecordtable['TimeObserved']
      if (timeobservedstring == nil) then
	debugmessage("NDHiNat", string.format("File %s (line %d) may not be an iNaturalist export file\n\"%s\"", filename, countlines, debug), "iNat file format error")
	return
      end
      local timeobserved = timefromisostring(timeobservedstring)
      local rangebefore = inatmatchrangebefore
      local rangeafter = inatmatchrangeafter
      if (photorecordtable['Filename'] ~= "original") then
        rangebefore = inatmatchrangebeforenamed
	rangeafter = inatmatchrangeafternamed
      end
      if (NDHiNat.inatstart == nil or (timeobserved - rangebefore) < NDHiNat.inatstart) then
	NDHiNat.inatstart = timeobserved - rangebefore
      end
      if (NDHiNat.inatend == nil or NDHiNat.inatend < (timeobserved + rangeafter)) then
	NDHiNat.inatend = timeobserved + rangeafter
      end
      for td = -rangebefore, rangeafter+inatbucketsize-1, inatbucketsize do  -- -60, 540 or -120, 480, 1080
	local t = timeobserved + td
	local bucket = math.floor(t / inatbucketsize) * inatbucketsize
	if (NDHiNat.buckets[bucket] == nil) then
	  NDHiNat.buckets[bucket] = { }
	  -- debugmessage("NDHinat", string.format("Bucket %d (%d %d) is empty, add %d", bucket, td, t, photorecordtable['PhotoID']), "debug inat bucket empty")
	else
	  -- debugmessage("NDHinat", string.format("Bucket %d (%d %d) is not empty, add %d", bucket, td, t, photorecordtable['PhotoID']), "deg inat bucket empty")
	end
	-- local dbg = "Before:"
	for i, p in ipairs(NDHiNat.buckets[bucket]) do
	  -- dbg = stringbuild(dbg, p['Filename'], "+")
	  if (p['PhotoID'] == photorecordtable['PhotoID'] and p['Filename'] == photorecordtable['Filename']) then
	    debugmessage("NDHiNat", string.format("Replacing dup record %s %s with %s %s, updated %s with %s", p['PhotoID'], p['Filename'], photorecordtable['PhotoID'], photorecordtable['Filename'], p['TimeUpdated'], photorecordtable['TimeUpdated']), "debug iNat table dup")
	    table.remove(NDHiNat.buckets[bucket], i)
	    countdups = countdups + 1
	    break
	  end
	end
	debugmessage("NDHiNat", string.format("Adding %s to\nbucket %s:\nrecord %s\n%s\n%s", photorecordtable, stringfromtime(bucket), (photorecordtable['TimeObserved']), photorecordtable['PhotoID'], photorecordtable['Filename']), "debug iNat table add")
	table.insert(NDHiNat.buckets[bucket], photorecordtable)
	-- dbg = stringbuild(dbg, "After", "\n")
	-- for i, p in ipairs(NDHiNat.buckets[bucket]) do
	  -- dbg = stringbuild(dbg, p['Filename'], "+")
	-- end
	-- debugmessage("NDHiNat", string.format("Added %s, Table:\n%s", photorecordtable['ID'], dbg), "debug iNat table post")
      end
    end
  end
  local inatstartstring = stringfromtime(NDHiNat.inatstart or 0)
  local inatendstring = stringfromtime(NDHiNat.inatend or 0)
  local retval = string.format("%d lines (%d dups) from %s to %s", countlines, countdups, inatstartstring, inatendstring)
  debugmessage("NDHiNat", string.format("Return %d %s", countlines, retval), "debug lines")
  return retval
  
end

function NDHiNat.inatdebug()

  local count = 0
  local dbg = "Debug iNat Load\n"
  -- for bucket, bucketlist in pairs(NDHiNat.buckets) do -- Random order
  for bucket = math.floor(NDHiNat.inatstart / inatbucketsize) * inatbucketsize, (NDHiNat.inatend+inatbucketsize-1), inatbucketsize do
    bucketlist = NDHiNat.buckets[bucket]
    dbg = stringbuild(dbg, string.format("Bucket %d (%s)", bucket, stringfromtime(bucket)))
    if (bucketlist ~= nil) then
      -- dbg = stringbuild(dbg, string.format("  Bucketlist = %s (%s)", bucketlist, type(bucketlist)))
      for i, p in ipairs(bucketlist) do
	local pfilename = p['Filename']
	local ptimeobservedstring = p['TimeObserved']
	local ptime = timefromisostring(ptimeobservedstring)
	local pcamera = p['Make']
	dbg = stringbuild(dbg, string.format("  %d (%s) %s", ptime, stringfromtime(ptime), pfilename))
      end
    else
      stringbuild(dbg, string.format("  Empty bucket %d", bucket))
    end
    count = count + 1
    if (count > 100) then
      break
    end
  end
  dbg = stringbuild(dbg, string.format("iNatstart = %d (%s)\niNatend = %d (%s)", NDHiNat.inatstart, stringfromtime(NDHiNat.inatstart), NDHiNat.inatend, stringfromtime(NDHiNat.inatend)))
  debugmessage("NDHiNat", dbg, "inatmatch6")
  
end


-- Match photoname/camera at timelocal in library with all possible photos in iNat bucket.
function NDHiNat.inatmatch(path, filename, camera, timelocal, timeutc)

  local best = nil
  local besttime = nil
  local photoname = string.match(filename, "([^.]+)\.%w+")
  for l = 0, 1 do
    local time
    if (l == 0) then
      time = timelocal
      debugmessage("NDHiNat", string.format("Looking local at photo %s (%s) %d %s", photoname, filename, time, stringfromtime(time)), "inatmatch0")
    else
      time = timeutc
      debugmessage("NDHiNat", string.format("Looking utc at photo %s (%s) %d %s", photoname, filename, time, stringfromtime(time)), "inatmatch0")
    end
    local bucket = math.floor(time / inatbucketsize) * inatbucketsize
    local bucketlist = NDHiNat.buckets[bucket]
    debugmessage("NDHiNat", string.format("Photo %s: Bucket %d", photoname, bucket), "inatmatch1")
    if (bucketlist ~= nil) then
      for i, p in ipairs(bucketlist) do
	local pfilename = p['Filename']
	local ptimeobservedstring = p['TimeObserved']
	local ptime = timefromisostring(ptimeobservedstring)
	-- local pcamera = p['Make']

	local status = ""
	debugmessage("NDHiNat", string.format("Looking %d at %s %s ?= %s\nbucket=%d %s\nptime=%d %s\nlocaltime=%s %s",
						       i, path, photoname, pfilename,
									      bucket, stringfromtime(bucket),
											    ptime, stringfromtime(ptime),
													     time, stringfromtime(time)),
					  "inatmatch2")
	local match = false
	local debug = ""
	if ((time <  ptime and (ptime - time) <= inatmatchrangebefore) or -- photo before obs within range
	    (ptime <= time and (time - ptime) <= inatmatchrangeafter)) then  -- photo after obs within range
	  debug = stringbuild(debug, "Inside narrow time window", ", ")
	  if ((camera == "Apple" or camera == "Google") and
	      (string.find(pfilename, "original", 1, true))) then
	    debug = stringbuild(debug, string.format("Camera %s: %s matches 'original'", camera, pfilename), ", ")
	    match = true
	  else
	    debug = stringbuild(debug, string.format("Camera %s: %s not match 'original'", camera, pfilename), ", ")
	  end
	end
	if ((time <  ptime and (ptime - time) <= inatmatchrangebeforenamed) or -- photo before obs within range
	    (ptime <= time and (time - ptime) <= inatmatchrangeafternamed)) then  -- photo after obs within range
	  debug = stringbuild(debug, "Inside wide time window", ", ")
	  if (string.find(pfilename, photoname, 1, true)) then
	    debug = stringbuild(debug, string.format("Camera %s: %s matches explicit %s", camera, pfilename, photoname), ", ")
	    match = true
	  else
	    debug = stringbuild(debug, string.format("Camera %s: %s not match explicit %s", camera, pfilename, photoname), ", ")
	  end
	end
	debugmessage("NDHiNat", string.format("Observation matching %s: %s", match, debug), "inatmatch3")
	-- if (((
	--       (time <  ptime and (ptime - time) <= inatmatchrangebefore) or -- photo before obs within range
	--       (ptime <= time and (time - ptime) <= inatmatchrangeafter)) and  -- photo after obs within range
	--      ((string.find(pfilename, "original", 1, true)) and
	--       -- (string.match(path, "/J") == nil) and
	--       (camera == "Apple" or camera == "Google"))) or
	--     ((
	--       (time <  ptime and (ptime - time) <= inatmatchrangebeforenamed) or -- photo before obs within range
	--       (ptime <= time and (time - ptime) <= inatmatchrangeafternamed)) and  -- photo after obs within range
	--      ((string.find(pfilename, photoname, 1, true))))) then
	if (match) then
	  if (best == nil) then
	    -- Always best if the first
	    best = p
	    besttime = ptime
	    status = status .. "First"
	  else
	    if (besttime < time) then
	      if (ptime > besttime) then
		best = p
		besttime = ptime
		status = string.format("%s New best (%d closer before %d)", status, ptime, time)
	      else
		status = string.format("%s Not better (%d farther before %d)", status, ptime, time)
	      end
	    else -- (besttime >= time)
	      if (ptime < besttime) then
		best = p
		besttime = ptime
		status = string.format("%s New best (%d closer after %d)", status, ptime, time)
	      else
		status = string.format("%s Not better (%d farther after %d)", status, ptime, time)
	      end
	    end
	  end
	  debugmessage("NDHiNat", string.format("Found %s == %s at %d: %s", photoname, pfilename, bucket, status), "inatmatch4")
	else
	  debugmessage("NDHiNat", string.format("No match %s ~= %s at %d: %s", photoname, pfilename, bucket, status), "inatmatch5")
	end
      end
    end
  end
  return best
end

