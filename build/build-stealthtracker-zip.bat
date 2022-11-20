:: Assumes running from StealthTracker\build
mkdir out\StealthTracker
copy ..\extension.xml out\StealthTracker\
copy ..\readme.txt out\StealthTracker\
mkdir out\StealthTracker\scripts
copy ..\scripts\stealthtracker.lua out\StealthTracker\scripts\
mkdir out\StealthTracker\graphics\icons
copy ..\graphics\icons\stealth_icon.png out\StealthTracker\graphics\icons\
cd out
CALL ..\zip-items StealthTracker
rmdir /S /Q StealthTracker\
copy StealthTracker.zip StealthTracker.ext
cd ..
