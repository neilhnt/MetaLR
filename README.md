# MetaLR

Scripts to manage photo metadata in Lightroom Classic:
- Match against CSV of iNaturalist observations, and attach iNat metadata to photographs
- Match against CSV of Strava activities, and apply photo captions from activity names
- Match against GPX files of Strava or other activities, and geolocate photos, using appropriate timezone logic
- Match against logfile CSV of caption names with date/time ranges (potentially overlapping)

Scripts to fix and tweak photos
- Find photos with color temperature set to 2000 (lowest value) (typically Nikon raw that LRC has corrupted and restore an "As Shot" value
- Find photos with high ISO and apply a default noise reduction
- Find photos with no lighting edits, and apply "Auto"
- Find photos with no Clarity or Vibrance, and apply typical values
